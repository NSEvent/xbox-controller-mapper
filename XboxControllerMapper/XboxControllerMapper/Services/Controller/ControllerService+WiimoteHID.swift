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
        setWiimotePointerEngaged(false)
        guard wiimoteHIDManager != nil || !wiimoteHIDRegistrations.isEmpty else { return }
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

}
