import Foundation
import IOKit
import IOKit.hid

// MARK: - Nintendo Pro Controller HID Monitoring (Home button)


/// The Home button on the Nintendo Switch Pro Controller is intercepted by macOS
/// and not exposed via GCExtendedGamepad or physicalInputProfile.
/// We monitor raw HID input reports to detect it directly.
///
/// Pro Controller Bluetooth HID report formats:
///
/// Simple report (Report ID 0x3F, 11 bytes) — default Bluetooth mode:
///   Bytes 0-1: 16 button bits (Usage Page 9, Usages 1-16)
///     Byte 0: Y(0x01) B(0x02) A(0x04) X(0x08) L(0x10) R(0x20) ZL(0x40) ZR(0x80)
///     Byte 1: Minus(0x01) Plus(0x02) LStick(0x04) RStick(0x08) Home(0x10) Capture(0x20)
///   Byte 2: Hat switch (4 bits) + padding (4 bits)
///   Bytes 3-10: 4x 16-bit axes (sticks)
///
/// Standard full report (Report ID 0x30, 49 bytes) — enabled by subcommand:
///   Byte 0: Timer
///   Byte 1: Battery/connection info
///   Byte 2: buttons1 — Y(0x01) X(0x02) B(0x04) A(0x08) SR_R(0x10) SL_R(0x20) R(0x40) ZR(0x80)
///   Byte 3: buttons2 — Minus(0x01) Plus(0x02) RStick(0x04) LStick(0x08) Home(0x10) Capture(0x20)
///   Byte 4: buttons3 — Down(0x01) Up(0x02) Right(0x04) Left(0x08) SR_L(0x10) SL_L(0x20) L(0x40) ZL(0x80)
///   Bytes 5-10: Stick data
///   Bytes 11+: IMU data

/// Weak callback context to prevent use-after-free when ControllerService is deallocated.
fileprivate final class NintendoHIDCallbackContext {
    weak var service: ControllerService?
    init(service: ControllerService) { self.service = service }
}

/// Per-device registration state. Mirrors PlayStationHIDRegistration: each
/// matched device gets its own report buffer and callback context so multiple
/// devices never share a buffer, and cleanup can unregister every registration.
struct NintendoHIDRegistration {
    let device: IOHIDDevice
    let reportBuffer: UnsafeMutablePointer<UInt8>
    let callbackContext: UnsafeMutableRawPointer
}

@MainActor
extension ControllerService {

    private static let nintendoHIDReportBufferSize = 64

    /// Nintendo Switch Pro Controller identifiers
    private static let nintendoVendorID = 0x057E
    private static let proControllerProductID = 0x2009

    func setupNintendoHIDMonitoring() {
        // Clean up any previous monitoring
        if nintendoHIDManager != nil || !nintendoHIDRegistrations.isEmpty {
            cleanupNintendoHIDMonitoring()
        }

        nintendoHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = nintendoHIDManager else { return }

        // Match Nintendo Pro Controller
        let proControllerDict: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.nintendoVendorID,
            kIOHIDProductIDKey as String: Self.proControllerProductID,
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, [proControllerDict] as CFArray)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices {
                setupNintendoHIDDeviceCallback(device)
            }
        }
    }

    private func setupNintendoHIDDeviceCallback(_ device: IOHIDDevice) {
        // A genuine Pro Controller reports manufacturer "Nintendo Co.,Ltd.";
        // third-party clones (8BitDo Zero 2, etc.) leave it empty. Record that
        // so handleNintendoHIDReport can opt into the raw-HID d-pad override.
        let manufacturer = (IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String) ?? ""
        if manufacturer.trimmingCharacters(in: .whitespaces).isEmpty {
            // Flag at setup (not on first report) so the GameController
            // left-thumbstick is suppressed before any input arrives — no
            // first-press race. Genuine Nintendo pads report a manufacturer,
            // so this only catches clones, which send the 0x3F report we read.
            storage.lock.lock()
            storage.nintendoHIDManufacturerEmpty = true
            storage.isNintendoDPadStickClone = true
            storage.lock.unlock()
            NSLog("[ControllerKeys] Nintendo HID: empty manufacturer — driving left stick from raw HID (stickless clone)")
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.nintendoHIDReportBufferSize)
        let ctx = NintendoHIDCallbackContext(service: self)
        let retainedContext = Unmanaged.passRetained(ctx).toOpaque()
        nintendoHIDRegistrations.append(
            NintendoHIDRegistration(
                device: device,
                reportBuffer: buffer,
                callbackContext: retainedContext
            )
        )

        IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.nintendoHIDReportBufferSize, { context, result, sender, type, reportID, report, reportLength in
            guard let context = context else { return }
            let holder = Unmanaged<NintendoHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
            guard let service = holder.service else { return }
            service.handleNintendoHIDReport(reportID: reportID, report: report, length: Int(reportLength))
        }, retainedContext)

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        NSLog("[ControllerKeys] Nintendo HID monitoring started for Home button")
    }

    func cleanupNintendoHIDMonitoring() {
        // Same ordering as cleanupHIDMonitoring — unregister callbacks first,
        // then unschedule, close the manager, and only then release contexts
        // and deallocate buffers.

        for registration in nintendoHIDRegistrations {
            IOHIDDeviceRegisterInputReportCallback(
                registration.device,
                registration.reportBuffer,
                Self.nintendoHIDReportBufferSize,
                nil,
                nil
            )
        }

        for registration in nintendoHIDRegistrations {
            IOHIDDeviceUnscheduleFromRunLoop(
                registration.device,
                CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue
            )
        }

        if let manager = nintendoHIDManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        nintendoHIDManager = nil

        for registration in nintendoHIDRegistrations {
            Unmanaged<NintendoHIDCallbackContext>.fromOpaque(registration.callbackContext).release()
            registration.reportBuffer.deallocate()
        }
        nintendoHIDRegistrations.removeAll()
    }

    /// Parse Nintendo Pro Controller HID input reports for the Home button and,
    /// on stickless clones, the d-pad-driven left stick.
    nonisolated func handleNintendoHIDReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        // Diagnostic aid for bringing up new clone controllers: set CK_HID_DUMP=1
        // to log raw report bytes whenever they change (deduped). Off by default;
        // HID reports arrive regardless of app focus, so launch the app binary
        // directly and read its stderr while pressing buttons.
        if Self.hidDumpEnabled {
            Self.logChangedReport(reportID: reportID, report: report, length: length)
        }
        guard let parsed = NintendoHIDParser().parse(
            reportID: reportID,
            report: UnsafePointer(report),
            length: length
        ) else { return }

        // Raw-HID left-stick override for stickless clones (8BitDo Zero 2 etc.).
        // macOS funnels the d-pad through the phantom Pro-Controller stick and
        // mis-calibrates its sign per connection; the raw 0x3F axes are
        // deterministic, so we drive the left stick from them directly. Gated
        // on an empty-manufacturer device actually emitting 0x3F stick data, so
        // genuine Pro Controllers are never affected.
        if let x = parsed.leftStickX, let y = parsed.leftStickY {
            storage.lock.lock()
            let isClone = storage.isNintendoDPadStickClone
            storage.lock.unlock()
            if isClone {
                updateLeftStick(x: x, y: y)
            }
        }

        guard let homePressed = parsed.nintendoHome else { return }

        storage.lock.lock()
        let homeChanged = homePressed != storage.lastNintendoHomeState
        if homeChanged {
            storage.lastNintendoHomeState = homePressed
        }
        storage.lastInputTime = CFAbsoluteTimeGetCurrent()
        storage.lock.unlock()

        if homeChanged {
            controllerQueue.async { [weak self] in
                self?.handleButton(.xbox, pressed: homePressed)
            }
        }
    }

    // MARK: - Raw report diagnostic (CK_HID_DUMP=1)

    nonisolated static let hidDumpEnabled = ProcessInfo.processInfo.environment["CK_HID_DUMP"] == "1"
    nonisolated(unsafe) private static var lastDumpBytes: [UInt8] = []
    private static let dumpLock = NSLock()

    nonisolated static func logChangedReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        let n = min(length, 16)
        var bytes = [UInt8](repeating: 0, count: n)
        for i in 0..<n { bytes[i] = report[i] }
        dumpLock.lock()
        let changed = bytes != lastDumpBytes
        if changed { lastDumpBytes = bytes }
        dumpLock.unlock()
        guard changed else { return }
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        NSLog("[CK_HID_DUMP] id=0x%02X len=%d  %@", reportID, length, hex)
    }
}
