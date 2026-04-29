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


@MainActor
extension ControllerService {

    private static let nintendoHIDReportBufferSize = 64

    /// Nintendo Switch Pro Controller identifiers
    private static let nintendoVendorID = 0x057E
    private static let proControllerProductID = 0x2009

    func setupNintendoHIDMonitoring() {
        // Clean up any previous monitoring
        if nintendoHIDManager != nil {
            cleanupNintendoHIDMonitoring()
        }

        nintendoHIDReportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.nintendoHIDReportBufferSize)

        nintendoHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = nintendoHIDManager else {
            nintendoHIDReportBuffer?.deallocate()
            nintendoHIDReportBuffer = nil
            return
        }

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
        nintendoHIDDevice = device

        guard let buffer = nintendoHIDReportBuffer else { return }

        // Release previous context if any
        if let existingCtx = nintendoHIDCallbackContext {
            Unmanaged<NintendoHIDCallbackContext>.fromOpaque(existingCtx).release()
        }

        let ctx = NintendoHIDCallbackContext(service: self)
        let retainedContext = Unmanaged.passRetained(ctx).toOpaque()
        nintendoHIDCallbackContext = retainedContext

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
        // Same ordering as cleanupHIDMonitoring — unregister callback first, then release resources

        if let device = nintendoHIDDevice, let buffer = nintendoHIDReportBuffer {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.nintendoHIDReportBufferSize, nil, nil)
        }

        if let device = nintendoHIDDevice {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        nintendoHIDDevice = nil

        if let manager = nintendoHIDManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        nintendoHIDManager = nil

        if let ctx = nintendoHIDCallbackContext {
            Unmanaged<NintendoHIDCallbackContext>.fromOpaque(ctx).release()
            nintendoHIDCallbackContext = nil
        }

        if let buffer = nintendoHIDReportBuffer {
            buffer.deallocate()
        }
        nintendoHIDReportBuffer = nil
    }

    /// Parse Nintendo Pro Controller HID input reports for the Home button.
    nonisolated func handleNintendoHIDReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        // The report buffer includes the report ID as byte 0.
        // Both report formats have Home at bit 4 (0x10) of the "buttons2" byte.
        //
        // Standard full report (0x30): buffer layout is
        //   [0]=0x30 [1]=timer [2]=battery [3]=buttons1 [4]=buttons2 [5]=buttons3 ...
        //   buttons2Offset = 4
        //
        // Simple report (0x3F): buffer layout is
        //   [0]=0x3F [1]=buttons_lo [2]=buttons_hi [3]=hat+pad ...
        //   buttons2Offset = 2  (Home=0x10 in buttons_hi)
        let buttons2Offset: Int
        if reportID == 0x30 && length >= 5 {
            buttons2Offset = 4  // Standard full report
        } else if reportID == 0x3F && length >= 3 {
            buttons2Offset = 2  // Simple report
        } else {
            return
        }

        guard buttons2Offset < length else { return }

        let buttons2 = report[buttons2Offset]
        let homePressed = (buttons2 & 0x10) != 0

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
}
