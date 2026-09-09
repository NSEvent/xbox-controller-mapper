import Combine
import Foundation
import GameController
import IOKit
import IOKit.hid

// MARK: - Wii Remote raw HID monitoring

/// A system-paired Wii Remote (see ~/dotfiles/scripts/wiimote-pair — modern
/// macOS needs a private-API pairing flow) attaches as a Bluetooth IOHID
/// gamepad, but its report descriptor exposes only opaque vendor byte-arrays,
/// so GameController ignores it and element-based parsing sees zero buttons.
/// We match it by VID/PID and parse raw input reports directly.
///
/// Report layout (byte 0 is the report ID, included by the input callback —
/// verified by live capture on an original RVL-CNT-01, 2026-09-08):
///   Core buttons 0x30 (3 bytes): [0x30, BB1, BB2], sent on change.
///   Status 0x20 (7 bytes): [0x20, BB1, BB2, flags, 0, 0, battery].
/// Parsing lives in WiimoteHIDParser (HIDReportParsers.swift).
///
/// Output reports (LEDs, status request) use the Bluetooth HID quirk: the
/// report ID must ALSO be the first byte of the buffer passed to
/// IOHIDDeviceSetReport, or the Wiimote acks with an error and ignores it.

/// Weak callback context to prevent use-after-free when ControllerService is
/// deallocated.
fileprivate final class WiimoteHIDCallbackContext {
    weak var service: ControllerService?
    /// The registered device, so report handlers can write back to the
    /// interface that actually delivered the report (0x20 mode re-sends).
    /// Nil for the manager-level matched/removed callback context.
    let device: IOHIDDevice?
    init(service: ControllerService, device: IOHIDDevice? = nil) {
        self.service = service
        self.device = device
    }
}

/// Per-device registration state. Mirrors NintendoHIDRegistration: each matched
/// device gets its own report buffer and callback context so multiple remotes
/// never share a buffer, and cleanup can unregister every registration.
struct WiimoteHIDRegistration {
    let device: IOHIDDevice
    let reportBuffer: UnsafeMutablePointer<UInt8>
    let callbackContext: UnsafeMutableRawPointer
    /// Serial-number key used to collapse the duplicate IOHID interfaces a
    /// single paired Wiimote exposes (see wiimoteDedupeKey).
    let dedupeKey: String
}

// Report delivery uses a dedicated run-loop thread (never the main run
// loop — see DedicatedHIDRunLoop; the stuck-button burst pathology was
// traced live 2026-09-09).
private let wiimoteHIDRunLoop = DedicatedHIDRunLoop(threadName: "ControllerKeys Wiimote HID")

/// Serial queue for pointer mode transitions (engage's ~140ms IR init and
/// disengage's teardown must never interleave), with a generation counter so
/// a superseded engage aborts between writes instead of finishing late and
/// leaving the remote streaming while disengaged.
private let wiimotePointerModeQueue = DispatchQueue(label: "com.controllerkeys.wiimote-pointer-mode", qos: .userInitiated)

private final class WiimoteModeGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    func isCurrent(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value == generation
    }
}

private let wiimoteModeGeneration = WiimoteModeGeneration()

/// Smoothed IR pointer state, shared between HID-thread reports.
private final class WiimotePointerState: @unchecked Sendable {
    private let lock = NSLock()
    private var smoothed: CGPoint?
    private var lastIRSample: TimeInterval = 0
    private var lastBlobCount = 0
    private var cachedScreenBounds: CGRect?

    /// Main-display bounds, cached per pointer session (refreshed on reset —
    /// engage/disengage/IR-loss) so the ~100 Hz IR path doesn't query
    /// CoreGraphics per report.
    func screenBounds() -> CGRect {
        lock.lock()
        defer { lock.unlock() }
        if let cachedScreenBounds { return cachedScreenBounds }
        let bounds = CGDisplayBounds(CGMainDisplayID())
        cachedScreenBounds = bounds
        return bounds
    }

    /// Stamp an IR sighting; used for the tilt-fallback grace period.
    func noteIRSeen(at time: TimeInterval) {
        lock.lock()
        lastIRSample = time
        lock.unlock()
    }

    /// Whether IR was seen within `grace` seconds — candle flicker drops
    /// blobs for a frame or two, and falling straight back to tilt while the
    /// remote is pitched yanks the cursor.
    func irSeenRecently(now: TimeInterval, grace: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return now - lastIRSample < grace
    }

    /// Exponentially smooth toward `target` and return the delta from the
    /// previous smoothed position (nil delta on the first sample after reset).
    /// Speed-adaptive (One-Euro-style): a slow or still hand gets heavy
    /// smoothing so candle flicker parks the cursor, while fast sweeps raise
    /// the blend factor and stay responsive.
    func advance(target: CGPoint, baseAlpha: CGFloat, blobCount: Int) -> CGPoint? {
        lock.lock()
        defer { lock.unlock() }
        // 2↔1 blob transitions shift the reference frame by half the blob
        // separation; re-anchor without emitting a delta so the cursor pauses
        // for a report instead of lurching (the adaptive alpha would amplify
        // the false jump).
        if blobCount != lastBlobCount {
            lastBlobCount = blobCount
            smoothed = target
            return nil
        }
        guard let previous = smoothed else {
            smoothed = target
            return nil
        }
        let distance = hypot(target.x - previous.x, target.y - previous.y)
        let alpha = min(0.85, baseAlpha + distance * 0.015)
        let next = CGPoint(
            x: previous.x + (target.x - previous.x) * alpha,
            y: previous.y + (target.y - previous.y) * alpha
        )
        smoothed = next
        return CGPoint(x: next.x - previous.x, y: next.y - previous.y)
    }

    func reset() {
        lock.lock()
        smoothed = nil
        lastBlobCount = 0
        cachedScreenBounds = nil
        lock.unlock()
    }
}

private let wiimotePointerState = WiimotePointerState()

/// IOHIDManager device-matched callback. Runs on the dedicated HID run loop;
/// hop to the MainActor for service state.
private nonisolated func wiimoteHIDDeviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard result == kIOReturnSuccess, let context else { return }
    let holder = Unmanaged<WiimoteHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
    guard let service = holder.service else { return }
    DispatchQueue.main.async {
        service.wiimoteDeviceAppeared(device)
    }
}

private nonisolated func wiimoteHIDDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let holder = Unmanaged<WiimoteHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
    guard let service = holder.service else { return }
    DispatchQueue.main.async {
        service.wiimoteDeviceRemoved(device)
    }
}

@MainActor
extension ControllerService {

    nonisolated private static let wiimoteHIDReportBufferSize = 64

    /// Wiimote core buttons → mappable ControllerButton identities. 1/2 ride
    /// the X/Y slots and +/− the menu/view slots so every Wiimote button is
    /// mappable with zero new enum cases; the `.wiimote` visual family
    /// relabels them (1, 2, +, −, Home) in the UI.
    nonisolated static let wiimoteButtonMap: [(wiimote: WiimoteButtons, button: ControllerButton)] = [
        (.a, .a),
        (.b, .b),
        (.one, .x),
        (.two, .y),
        (.plus, .menu),
        (.minus, .view),
        (.home, .xbox),
        (.dpadUp, .dpadUp),
        (.dpadDown, .dpadDown),
        (.dpadLeft, .dpadLeft),
        (.dpadRight, .dpadRight),
    ]

    func setupWiimoteHIDMonitoring() {
        if wiimoteHIDManager != nil || !wiimoteHIDRegistrations.isEmpty {
            cleanupWiimoteHIDMonitoring()
        }

        wiimoteHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = wiimoteHIDManager else { return }

        let ctx = WiimoteHIDCallbackContext(service: self)
        let retainedContext = Unmanaged.passRetained(ctx).toOpaque()
        wiimoteHIDCallbackContext = retainedContext

        IOHIDManagerSetDeviceMatchingMultiple(manager, WiimoteHIDDriverDescriptor().matchingCFArray)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, wiimoteHIDDeviceMatched, retainedContext)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, wiimoteHIDDeviceRemoved, retainedContext)

        // Schedule on the dedicated HID thread — never the main run loop
        // (see WiimoteHIDRunLoop).
        wiimoteHIDRunLoop.perform {
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

            if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
                for device in devices {
                    wiimoteHIDDeviceMatched(
                        context: retainedContext,
                        result: kIOReturnSuccess,
                        sender: nil,
                        device: device
                    )
                }
            }
        }
    }

    /// A paired Wiimote surfaces as TWO IOHID device objects (the Bluetooth
    /// event driver plus a user-device shim) with identical VID/PID and serial.
    /// Registering both delivers every report twice — and the shim can replay
    /// a press after the real release, leaving the button stuck down. Key on
    /// the serial (the remote's BT address) so only one interface per physical
    /// remote is registered.
    nonisolated private static func wiimoteDedupeKey(_ device: IOHIDDevice) -> String {
        if let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String,
           !serial.isEmpty {
            return serial
        }
        if let location = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int {
            return "loc-\(location)"
        }
        return "unkeyed"
    }

    func wiimoteDeviceAppeared(_ device: IOHIDDevice) {
        // An interface (re)appearing cancels a pending churn-debounced
        // disconnect — the remote never actually left.
        wiimoteDisconnectWorkItem?.cancel()
        wiimoteDisconnectWorkItem = nil
        guard !wiimoteHIDRegistrations.contains(where: { $0.device == device }) else { return }
        let key = Self.wiimoteDedupeKey(device)
        guard !wiimoteHIDRegistrations.contains(where: { $0.dedupeKey == key }) else {
            NSLog("[ControllerKeys] Wii Remote duplicate HID interface skipped (serial %@)", key)
            return
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.wiimoteHIDReportBufferSize)
        let ctx = WiimoteHIDCallbackContext(service: self, device: device)
        let retainedContext = Unmanaged.passRetained(ctx).toOpaque()
        wiimoteHIDRegistrations.append(
            WiimoteHIDRegistration(
                device: device,
                reportBuffer: buffer,
                callbackContext: retainedContext,
                dedupeKey: key
            )
        )

        IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.wiimoteHIDReportBufferSize, { context, _, _, _, reportID, report, reportLength in
            guard let context else { return }
            let holder = Unmanaged<WiimoteHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
            guard let service = holder.service, let device = holder.device else { return }
            service.handleWiimoteHIDReport(device: device, reportID: reportID, report: report, length: Int(reportLength))
        }, retainedContext)

        wiimoteHIDRunLoop.perform {
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        NSLog("[ControllerKeys] Wii Remote HID monitoring started")

        // Initialize the remote: player LED 1 (also stops the post-connect
        // blink) and a status request so battery comes back in a 0x20 report.
        // The reporting mode honors the pointer engagement state — adoption
        // of a churned interface mid-hold must restore streaming+IR, not
        // silently revert to buttons-only 0x30.
        Self.sendWiimoteReport(device, [0x11, 0x10])
        Self.sendWiimoteReport(device, [0x15, 0x00])
        let engaged = storage.lock.withLock { storage.wiimotePointerEngaged }
        enqueueWiimotePointerMode(engaged: engaged, device: device)

        activateWiimoteHIDSessionIfNeeded(device)
    }

    func wiimoteDeviceRemoved(_ device: IOHIDDevice) {
        var removedKey: String?
        var removedRegistration = false
        if let index = wiimoteHIDRegistrations.firstIndex(where: { $0.device == device }) {
            let registration = wiimoteHIDRegistrations.remove(at: index)
            removedKey = registration.dedupeKey
            removedRegistration = true
            let buffer = registration.reportBuffer
            let completed = wiimoteHIDRunLoop.performAndWait {
                IOHIDDeviceRegisterInputReportCallback(
                    device,
                    buffer,
                    Self.wiimoteHIDReportBufferSize,
                    nil,
                    nil
                )
                IOHIDDeviceUnscheduleFromRunLoop(
                    device,
                    CFRunLoopGetCurrent(),
                    CFRunLoopMode.defaultMode.rawValue
                )
            }
            if completed {
                Unmanaged<WiimoteHIDCallbackContext>.fromOpaque(registration.callbackContext).release()
                registration.reportBuffer.deallocate()
            } else {
                NSLog("[ControllerKeys] Wii Remote HID teardown timed out; leaking buffer to avoid use-after-free")
            }
        }

        // A dedupe-skipped twin interface churning away must not synthesize
        // releases — the registered interface is still reporting the hold.
        guard removedRegistration else { return }

        guard wiimoteHIDActiveDevice == device else {
            releaseLatchedWiimoteButtons()
            return
        }
        wiimoteHIDActiveDevice = nil

        // macOS tears down and recreates the paired Wiimote's two HID
        // interfaces independently, so the registered one dying doesn't mean
        // the remote left — adopt a surviving twin interface for the same
        // remote before declaring a disconnect. The adoption's status request
        // (0x15) refreshes the button mask, healing any release report lost
        // in the churn gap. Rate-limited: a second removal within 2s of an
        // adoption means the interfaces are ping-ponging (e.g. the remote is
        // powering off) — stop adopting and let the disconnect debounce run.
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - wiimoteLastAdoptionUptime > 2.0,
           let manager = wiimoteHIDManager,
           let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            let twin = devices.first { candidate in
                candidate != device
                    && (removedKey == nil || Self.wiimoteDedupeKey(candidate) == removedKey)
            }
            if let twin {
                NSLog("[ControllerKeys] Wii Remote interface churned — adopting surviving twin")
                wiimoteLastAdoptionUptime = uptime
                // No latched-button release here: the adopted interface's 0x15
                // status request refreshes the mask, healing any lost release.
                wiimoteDeviceAppeared(twin)
                if wiimoteHIDActiveDevice == nil {
                    wiimoteHIDActiveDevice = twin
                }
                return
            }
        }

        releaseLatchedWiimoteButtons()

        // Debounce the disconnect: churn can momentarily leave zero
        // interfaces before a recreated one arrives. Flapping isConnected
        // animates the empty-state card ("jittering" UI), so wait 1.5s and
        // only disconnect if nothing reappeared.
        wiimoteDisconnectWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.wiimoteDisconnectWorkItem = nil
            guard self.wiimoteHIDRegistrations.isEmpty,
                  self.wiimoteHIDActiveDevice == nil,
                  self.isConnected,
                  self.connectedController == nil else { return }
            self.controllerDisconnected()
            NSLog("[ControllerKeys] Wii Remote disconnected")
        }
        wiimoteDisconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    /// Present the Wiimote as the connected controller — but never steal the
    /// slot from a live GameController/Steam session; in that case the remote
    /// still injects its buttons as an auxiliary input source (8BitDo model).
    private func activateWiimoteHIDSessionIfNeeded(_ device: IOHIDDevice) {
        guard connectedController == nil,
              steamHIDActiveDevice == nil,
              !isConnected else {
            NSLog("[ControllerKeys] Wii Remote attached as auxiliary input (another controller is active)")
            return
        }

        wiimoteHIDActiveDevice = device
        if genericHIDController != nil {
            genericHIDController?.stop()
            genericHIDController = nil
            isGenericController = false
        }

        currentControllerIdentity = ControllerIdentityResolver.identity(
            for: device,
            fallbackName: "Wii Remote"
        )
        controllerName = "Wii Remote"
        controllerMappingSource = nil
        isGenericController = false

        detectConnectionType(device: device)

        storage.lock.lock()
        resetMotionStateLocked()
        resetTouchpadStateLocked()
        storage.applyControllerTypeLocked(.wiimote)
        storage.elitePaddleEventSource = .none
        storage.lock.unlock()

        isConnected = true
        reportControllerConnectionForTelemetry(fallback: .nintendo)

        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasXboxEliteKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasSteamControllerKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasAppleTVRemoteKey)
        UserDefaults.standard.set(true, forKey: Config.lastControllerWasWiimoteKey)

        batteryLevel = -1
        batteryState = .unknown
        startDisplayUpdateTimer()

        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }

        NSLog("[ControllerKeys] Wii Remote connected via raw HID")
    }

    func cleanupWiimoteHIDMonitoring() {
        let registrations = wiimoteHIDRegistrations
        wiimoteHIDRegistrations.removeAll()
        let manager = wiimoteHIDManager
        wiimoteHIDManager = nil

        // Same ordering as the per-device teardown: unregister callbacks and
        // unschedule ON the HID run loop, and only free the buffers/contexts
        // once that completed (a timed-out wait means the loop may still touch
        // them — leak instead of use-after-free, like the Steam teardown).
        let completed = wiimoteHIDRunLoop.performAndWait {
            for registration in registrations {
                IOHIDDeviceRegisterInputReportCallback(
                    registration.device,
                    registration.reportBuffer,
                    Self.wiimoteHIDReportBufferSize,
                    nil,
                    nil
                )
                IOHIDDeviceUnscheduleFromRunLoop(
                    registration.device,
                    CFRunLoopGetCurrent(),
                    CFRunLoopMode.defaultMode.rawValue
                )
            }
            if let manager {
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            }
        }

        if completed {
            for registration in registrations {
                Unmanaged<WiimoteHIDCallbackContext>.fromOpaque(registration.callbackContext).release()
                registration.reportBuffer.deallocate()
            }
            if let ctx = wiimoteHIDCallbackContext {
                Unmanaged<WiimoteHIDCallbackContext>.fromOpaque(ctx).release()
                wiimoteHIDCallbackContext = nil
            }
        } else {
            NSLog("[ControllerKeys] Wii Remote HID manager teardown timed out; leaking registrations to avoid use-after-free")
            wiimoteHIDCallbackContext = nil
        }
        wiimoteHIDActiveDevice = nil
        wiimoteDisconnectWorkItem?.cancel()
        wiimoteDisconnectWorkItem = nil
        storage.lock.withLock { storage.wiimotePointerEngaged = false }

        releaseLatchedWiimoteButtons()
    }

    /// Release any held buttons so a disconnect can't leave one stuck.
    private func releaseLatchedWiimoteButtons() {
        storage.lock.lock()
        let latched = WiimoteButtons(rawValue: storage.lastWiimoteButtons)
        storage.lastWiimoteButtons = 0
        storage.lock.unlock()
        guard !latched.isEmpty else { return }
        for entry in Self.wiimoteButtonMap where latched.contains(entry.wiimote) {
            let button = entry.button
            controllerQueue.async { [weak self] in
                self?.handleButton(button, pressed: false)
            }
        }
    }

    // MARK: Pointer (tilt/IR mouse via the mapped Pointer (Hold) action)

    /// Pointer tuning, user-adjustable in the Wii Remote settings tab.
    /// UserDefaults is thread-safe and internally cached — fine at 100 Hz.
    nonisolated private static func wiimoteTuning(_ key: String, default defaultValue: Double) -> Double {
        let value = UserDefaults.standard.double(forKey: key)
        return value == 0 ? defaultValue : value
    }

    /// Default-true boolean toggle (UserDefaults returns false for unset keys).
    nonisolated private static func wiimoteFlag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: key)
    }

    /// Quadratic response: gentle tilts give fine control, hard tilts sprint.
    nonisolated private static func wiimoteTiltVelocity(_ g: Float, maxPerReport: Float, deadzone: Float) -> CGFloat {
        let magnitude = abs(g)
        guard magnitude > deadzone else { return 0 }
        let normalized = min(1.0, (magnitude - deadzone) / (1.0 - deadzone))
        let speed = normalized * normalized * maxPerReport
        return CGFloat(g < 0 ? -speed : speed)
    }

    /// Absolute-style IR aiming, delivered as relative moves through the
    /// MAPPING ENGINE's simulator (so held mapped clicks turn moves into
    /// drags): smooth the midpoint of the visible blobs and scale
    /// camera-space deltas (1024×768) to screen scale, camera axes mirrored
    /// (pointing right moves the blob image left).
    nonisolated private func moveWiimotePointerByIR(_ points: [WiimoteIRPoint]) {
        let blobCount = min(points.count, 2)
        let mx: CGFloat
        let my: CGFloat
        if points.count >= 2 {
            mx = CGFloat(points[0].x + points[1].x) / 2
            my = CGFloat(points[0].y + points[1].y) / 2
        } else {
            mx = CGFloat(points[0].x)
            my = CGFloat(points[0].y)
        }
        let alpha = CGFloat(Self.wiimoteTuning(Config.wiimoteIRSmoothingKey, default: 0.25))
        guard let delta = wiimotePointerState.advance(
            target: CGPoint(x: mx, y: my),
            baseAlpha: alpha,
            blobCount: blobCount
        ) else { return }
        let gain = CGFloat(Self.wiimoteTuning(Config.wiimoteIRSpeedKey, default: 1.0))
        let bounds = wiimotePointerState.screenBounds()
        let dx = -delta.x * (bounds.width / 1024.0) * gain
        let dy = delta.y * (bounds.height / 768.0) * gain
        if abs(dx) > 0.01 || abs(dy) > 0.01 {
            wiimotePointerSimulator?.moveMouse(dx: dx, dy: dy)
        }
    }

    /// Engine-facing engage/disengage for the mapped "Pointer (Hold)" action.
    /// Idempotent; any button bound to the action can drive it.
    func setWiimotePointerEngaged(_ engaged: Bool) {
        let changed = storage.lock.withLock { () -> Bool in
            guard storage.wiimotePointerEngaged != engaged else { return false }
            storage.wiimotePointerEngaged = engaged
            return true
        }
        guard changed else { return }
        setWiimoteMotionReporting(engaged)
    }

    /// Switch the remote between on-change core buttons (0x30) and continuous
    /// buttons+accel+IR (0x33). Streaming runs only while the pointer is
    /// engaged. Engaging also runs the IR camera init sequence so the pointer
    /// can use absolute IR aiming when IR sources are visible, falling back
    /// to tilt when they aren't. Targets the pointer's session device (the
    /// active one), not merely the first registration.
    func setWiimoteMotionReporting(_ enabled: Bool) {
        guard let device = wiimoteHIDActiveDevice ?? wiimoteHIDRegistrations.first?.device else { return }
        wiimotePointerState.reset()
        enqueueWiimotePointerMode(engaged: enabled, device: device)
        NSLog("[ControllerKeys] Wii Remote pointer %@", enabled ? "engaged" : "disengaged")
    }

    /// Enqueue a mode transition on the serial pointer-mode queue. The
    /// generation token lets a superseding transition abort an in-flight
    /// engage between its paced writes, so rapid press-release can never
    /// leave the remote streaming while disengaged (or vice versa).
    func enqueueWiimotePointerMode(engaged: Bool, device: IOHIDDevice) {
        let generation = wiimoteModeGeneration.next()
        wiimotePointerModeQueue.async {
            guard wiimoteModeGeneration.isCurrent(generation) else { return }
            if engaged {
                Self.initializeWiimoteIRCamera(device, generation: generation)
            } else {
                Self.sendWiimoteReport(device, [0x12, 0x00, 0x30])
                // Power the IR camera back down (battery).
                Self.sendWiimoteReport(device, [0x13, 0x00])
                Self.sendWiimoteReport(device, [0x1A, 0x00])
            }
        }
    }

    /// WiiBrew IR camera bring-up (Marcan sensitivity, extended-format mode 3).
    /// Runs on the serial mode queue with small gaps between writes — the
    /// camera's register interface drops back-to-back writes — aborting
    /// between steps if a newer mode transition superseded this one.
    nonisolated private static func initializeWiimoteIRCamera(_ device: IOHIDDevice, generation: Int) {
        func step(_ body: () -> Void) -> Bool {
            guard wiimoteModeGeneration.isCurrent(generation) else { return false }
            body()
            usleep(20_000)
            return true
        }
        guard step({ sendWiimoteReport(device, [0x13, 0x04]) }),          // IR clock enable 1
              step({ sendWiimoteReport(device, [0x1A, 0x04]) }),          // IR clock enable 2
              step({ writeWiimoteRegister(device, address: 0xB0_0030, data: [0x01]) }),
              step({ writeWiimoteRegister(device, address: 0xB0_0000,
                                          data: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x90, 0x00, 0x41]) }),
              step({ writeWiimoteRegister(device, address: 0xB0_001A, data: [0x40, 0x00]) }),
              step({ writeWiimoteRegister(device, address: 0xB0_0033, data: [0x03]) }),  // extended mode
              step({ writeWiimoteRegister(device, address: 0xB0_0030, data: [0x08]) }),
              wiimoteModeGeneration.isCurrent(generation) else { return }
        sendWiimoteReport(device, [0x12, 0x04, 0x33])                     // continuous buttons+accel+IR
    }

    /// Write to the Wiimote's control registers: report 0x16, 0x04 = register
    /// space, 3-byte big-endian address, size byte, 16 data bytes (padded).
    nonisolated private static func writeWiimoteRegister(_ device: IOHIDDevice, address: UInt32, data: [UInt8]) {
        var bytes: [UInt8] = [
            0x16, 0x04,
            UInt8((address >> 16) & 0xFF), UInt8((address >> 8) & 0xFF), UInt8(address & 0xFF),
            UInt8(data.count),
        ]
        bytes += data
        bytes += [UInt8](repeating: 0, count: 16 - data.count)
        sendWiimoteReport(device, bytes)
    }

    /// Thread-agnostic output-report send (ID repeated as the buffer's first
    /// byte — Bluetooth HID quirk).
    nonisolated private static func sendWiimoteReport(_ device: IOHIDDevice, _ bytes: [UInt8]) {
        guard let reportID = bytes.first else { return }
        let rc = bytes.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), buf.baseAddress!, buf.count)
        }
        if rc != kIOReturnSuccess {
            NSLog("[ControllerKeys] Wii Remote output report 0x%02X failed: 0x%08X", reportID, UInt32(bitPattern: rc))
        }
    }

    /// Parse a Wii Remote input report, diff the button mask, and emit
    /// edge-triggered presses.
    nonisolated func handleWiimoteHIDReport(device: IOHIDDevice, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        if Self.hidDumpEnabled {
            Self.logChangedReport(reportID: reportID, report: report, length: length)
        }
        guard let parsed = WiimoteHIDParser().parse(
            reportID: reportID,
            report: UnsafePointer(report),
            length: length
        ) else { return }

        // Status reports (0x20) HALT all further data reporting until the
        // host re-sends the reporting mode (WiiBrew) — re-assert it for the
        // interface that delivered the report, per the engagement state.
        let statusEngaged: Bool? = reportID == 0x20
            ? storage.lock.withLock { storage.wiimotePointerEngaged }
            : nil
        if let statusEngaged {
            Self.sendWiimoteReport(device, statusEngaged ? [0x12, 0x04, 0x33] : [0x12, 0x00, 0x30])
        }

        if let level = parsed.wiimoteBatteryLevel {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.wiimoteHIDActiveDevice != nil else { return }
                self.batteryLevel = level
                self.batteryState = .discharging
            }
        }

        guard let buttons = parsed.wiimoteButtons else { return }

        // One lock section serves the pointer-engagement read AND the button
        // diff, so both come from the same instant.
        let (pointerEngaged, changed): (Bool, WiimoteButtons) = storage.lock.withLock {
            let previous = WiimoteButtons(rawValue: storage.lastWiimoteButtons)
            let diff = WiimoteButtons(rawValue: previous.rawValue ^ buttons.rawValue)
            if !diff.isEmpty {
                storage.lastWiimoteButtons = buttons.rawValue
                storage.lastInputTime = CFAbsoluteTimeGetCurrent()
            }
            return (storage.wiimotePointerEngaged, diff)
        }

        // Pointer: while the mapped "Pointer (Hold)" action is engaged, IR
        // aiming drives the cursor when the camera sees IR sources (sensor
        // bar / candles); otherwise gravity tilt drives pointer velocity.
        // Signs assume the pointing grip — face-up, IR end toward the screen.
        if pointerEngaged {
            let irEnabled = Self.wiimoteFlag(Config.wiimoteIREnabledKey)
            let tiltEnabled = Self.wiimoteFlag(Config.wiimoteTiltEnabledKey)
            let now = ProcessInfo.processInfo.systemUptime

            if irEnabled, let ir = parsed.wiimoteIRPoints, !ir.isEmpty {
                wiimotePointerState.noteIRSeen(at: now)
                moveWiimotePointerByIR(ir)
            } else if tiltEnabled,
                      // Grace period: candle flicker can drop blobs for a few
                      // frames; don't let tilt yank a pitched remote's cursor
                      // until IR has been gone for a beat.
                      !(irEnabled && wiimotePointerState.irSeenRecently(now: now, grace: 0.4)),
                      let ax = parsed.wiimoteAccelX, let ay = parsed.wiimoteAccelY {
                wiimotePointerState.reset()
                let deadzone = Float(Self.wiimoteTuning(Config.wiimoteTiltDeadzoneKey, default: 0.12))
                let dx = Self.wiimoteTiltVelocity(
                    ax,
                    maxPerReport: Float(Self.wiimoteTuning(Config.wiimoteTiltRollSpeedKey, default: 30)),
                    deadzone: deadzone
                )
                let dy = Self.wiimoteTiltVelocity(
                    ay,
                    maxPerReport: Float(Self.wiimoteTuning(Config.wiimoteTiltPitchSpeedKey, default: 44)),
                    deadzone: deadzone
                )
                if dx != 0 || dy != 0 {
                    wiimotePointerSimulator?.moveMouse(dx: dx, dy: dy)
                }
            }
        }

        guard !changed.isEmpty else { return }

        for entry in Self.wiimoteButtonMap where changed.contains(entry.wiimote) {
            let button = entry.button
            let pressed = buttons.contains(entry.wiimote)
            controllerQueue.async { [weak self] in
                self?.handleButton(button, pressed: pressed)
            }
        }
    }
}
