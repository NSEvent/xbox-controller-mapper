import Foundation
import CoreGraphics
import GameController
import IOKit.hid

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
final class WiimotePointerState: @unchecked Sendable {
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
    func advance(target: CGPoint, baseAlpha: CGFloat, blobCount: Int, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> CGPoint? {
        lock.lock()
        defer { lock.unlock() }
        let reacquired = time - lastIRSample >= 0.4
        lastIRSample = time
        // 2↔1 blob transitions shift the reference frame by half the blob
        // separation; re-anchor without emitting a delta so the cursor pauses
        // for a report instead of lurching (the adaptive alpha would amplify
        // the false jump).
        if blobCount != lastBlobCount || reacquired {
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
        lastIRSample = 0
        lastBlobCount = 0
        cachedScreenBounds = nil
        lock.unlock()
    }
}

private let wiimotePointerState = WiimotePointerState()

@MainActor
extension ControllerService {
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
        wiimotePointerState.reset()
        guard let device = wiimoteHIDActiveDevice ?? wiimoteHIDRegistrations.first?.device else {
            _ = wiimoteModeGeneration.next()
            return
        }
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
    nonisolated static func sendWiimoteReport(_ device: IOHIDDevice, _ bytes: [UInt8]) {
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
