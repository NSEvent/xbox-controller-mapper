import Foundation
import IOKit
import IOKit.hid

// MARK: - 8BitDo D-input Pad HID Monitoring (Home + Star buttons)

/// The Home button on the 8BitDo Micro (D-input / Android mode) is dropped by
/// Apple's GameController framework — the SDL row maps it to `guide`, which
/// macOS intercepts. We monitor the underlying HID device (vendor 0x2DC8)
/// directly and synthesize the press.
///
/// Micro (PID 0x9020) input report (report ID 0x03, 11 bytes) — VERIFIED by raw
/// capture (the report buffer includes the report ID at byte 0):
///   [0]=reportID 0x03  [1]=0x08  [2..5]=analog axes (neutral 0x7F)
///   [6..7]=L2/R2 analog  [8]=Button usages 1-8  [9]=Button usages 9-16  [10]=0x42
///   byte[9]: u9(0x01) u10(0x02) Select/u11(0x04) Start/u12(0x08)
///            Home/u13(0x10) Star/u14(0x20) u15(0x40) u16(0x80)
///
/// Home = usage 13 (the SDL `guide` slot) → byte[9] & 0x10. Confirmed working.
///
/// Star: the mask below targets usage 14 (byte[9] & 0x20) for completeness, but
/// the Micro emits NOTHING when Star is pressed in D-input mode — verified by
/// isolated capture (zero reports) and by HID interface enumeration (the pad
/// exposes only one Game Pad collection, no consumer/keyboard interface). Star
/// is a controller-side function/shortcut key with no standalone HID event, so
/// it cannot be mapped on macOS in this mode. The detection is left in place in
/// case a firmware/mode variant ever does report it.
///
/// The Zero 2 (PID 0x3230) sends a different, longer report and is skipped until
/// its layout is captured — see the length/PID guard in handleEightBitDoHIDReport.

/// Weak callback context to prevent use-after-free when ControllerService is
/// deallocated. Carries the device's productID so per-pad quirks can branch.
fileprivate final class EightBitDoHIDCallbackContext {
    weak var service: ControllerService?
    let productID: Int
    init(service: ControllerService, productID: Int) {
        self.service = service
        self.productID = productID
    }
}

/// Per-device registration state. Mirrors NintendoHIDRegistration: each matched
/// device gets its own report buffer and callback context so multiple pads never
/// share a buffer, and cleanup can unregister every registration.
struct EightBitDoHIDRegistration {
    let device: IOHIDDevice
    let reportBuffer: UnsafeMutablePointer<UInt8>
    let callbackContext: UnsafeMutableRawPointer
}

@MainActor
extension ControllerService {

    private static let eightBitDoHIDReportBufferSize = 64

    /// 8BitDo vendor ID (D-input / Android mode). In Switch mode the pads
    /// impersonate Nintendo (VID 0x057E) and are handled by the Nintendo path.
    private static let eightBitDoVendorID = 0x2DC8

    /// D-input product IDs for the small stickless pads whose Home/Star the
    /// GameController profile omits. Micro 0x9020, Zero 2 0x3230.
    private static let eightBitDoDInputProductIDs = [microProductID, zero2ProductID]

    // Report-parsing constants. `nonisolated` so handleEightBitDoHIDReport (which
    // runs nonisolated, off the HID run loop) can read them without crossing the
    // MainActor boundary — same pattern as the Nintendo HID dump constants.
    nonisolated private static let microProductID = 0x9020
    nonisolated private static let zero2ProductID = 0x3230
    /// Only the standard input report carries the button bytes.
    nonisolated private static let eightBitDoInputReportID: UInt32 = 0x03

    // Micro (PID 0x9020) input report — 11 bytes, verified by raw capture:
    //   [0]=reportID 0x03  [1]=0x08  [2..5]=analog axes (neutral 0x7F)
    //   [6..7]=L2/R2 analog  [8]=Button usages 1-8  [9]=Button usages 9-16
    //   [10]=0x42
    // Home (HID usage 13, the SDL `guide` slot) = byte 9 bit 4; Star (usage 14)
    // = byte 9 bit 5. (The earlier byte-2 guess was an analog axis — reading it
    // as buttons fired phantom Home/Star presses that corrupted every chord.)
    nonisolated private static let microReportLength = 11
    nonisolated private static let microButtonsHighOffset = 9
    nonisolated private static let eightBitDoHomeMask: UInt8 = 0x10   // HID Button usage 13
    nonisolated private static let eightBitDoStarMask: UInt8 = 0x20   // HID Button usage 14

    func setupEightBitDoHIDMonitoring() {
        // Clean up any previous monitoring
        if eightBitDoHIDManager != nil || !eightBitDoHIDRegistrations.isEmpty {
            cleanupEightBitDoHIDMonitoring()
        }

        eightBitDoHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = eightBitDoHIDManager else { return }

        let matches: [[String: Any]] = Self.eightBitDoDInputProductIDs.map { pid in
            [
                kIOHIDVendorIDKey as String: Self.eightBitDoVendorID,
                kIOHIDProductIDKey as String: pid,
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices {
                setupEightBitDoHIDDeviceCallback(device)
            }
        }
    }

    private func setupEightBitDoHIDDeviceCallback(_ device: IOHIDDevice) {
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.eightBitDoHIDReportBufferSize)
        let ctx = EightBitDoHIDCallbackContext(service: self, productID: productID)
        let retainedContext = Unmanaged.passRetained(ctx).toOpaque()
        eightBitDoHIDRegistrations.append(
            EightBitDoHIDRegistration(
                device: device,
                reportBuffer: buffer,
                callbackContext: retainedContext
            )
        )

        IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.eightBitDoHIDReportBufferSize, { context, _, _, _, reportID, report, reportLength in
            guard let context = context else { return }
            let holder = Unmanaged<EightBitDoHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
            guard let service = holder.service else { return }
            service.handleEightBitDoHIDReport(
                productID: holder.productID,
                reportID: reportID,
                report: report,
                length: Int(reportLength)
            )
        }, retainedContext)

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        NSLog("[ControllerKeys] 8BitDo HID monitoring started (Home/Star) pid=0x%04X", productID)
    }

    func cleanupEightBitDoHIDMonitoring() {
        // Same ordering as cleanupNintendoHIDMonitoring — unregister callbacks
        // first, then unschedule, close the manager, and only then release
        // contexts and deallocate buffers.
        for registration in eightBitDoHIDRegistrations {
            IOHIDDeviceRegisterInputReportCallback(
                registration.device,
                registration.reportBuffer,
                Self.eightBitDoHIDReportBufferSize,
                nil,
                nil
            )
        }

        for registration in eightBitDoHIDRegistrations {
            IOHIDDeviceUnscheduleFromRunLoop(
                registration.device,
                CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue
            )
        }

        if let manager = eightBitDoHIDManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        eightBitDoHIDManager = nil

        for registration in eightBitDoHIDRegistrations {
            Unmanaged<EightBitDoHIDCallbackContext>.fromOpaque(registration.callbackContext).release()
            registration.reportBuffer.deallocate()
        }
        eightBitDoHIDRegistrations.removeAll()

        // Release any latched Home/Star so a disconnect can't leave them stuck.
        storage.lock.lock()
        let homeWasDown = storage.lastEightBitDoHomeState
        let starWasDown = storage.lastEightBitDoStarState
        storage.lastEightBitDoHomeState = false
        storage.lastEightBitDoStarState = false
        storage.lock.unlock()
        if homeWasDown {
            controllerQueue.async { [weak self] in self?.handleButton(.xbox, pressed: false) }
        }
        if starWasDown {
            controllerQueue.async { [weak self] in self?.handleButton(.share, pressed: false) }
        }
    }

    /// Parse the 8BitDo D-input report for the Home and Star buttons and emit
    /// edge-triggered presses. Home → `.xbox` (house glyph), Star → `.share`
    /// (star glyph) — matching the minimap's 8BitDo button rendering.
    nonisolated func handleEightBitDoHIDReport(productID: Int, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        // Diagnostic (CK_HID_DUMP=1): log raw report bytes whenever they change.
        // Off by default; reports arrive regardless of focus, so launch the app
        // binary directly and read its stderr while pressing buttons.
        if Self.hidDumpEnabled {
            Self.logChangedReport(reportID: reportID, report: report, length: length)
        }

        // Only the Micro's 11-byte layout is verified. The Zero 2 (PID 0x3230)
        // sends a different, longer report — skip it rather than misread an
        // axis byte as buttons (which would fire phantom presses). Capture its
        // layout before enabling.
        guard reportID == Self.eightBitDoInputReportID,
              productID == Self.microProductID,
              length == Self.microReportLength else { return }

        let buttonsHigh = report[Self.microButtonsHighOffset]
        let homePressed = (buttonsHigh & Self.eightBitDoHomeMask) != 0
        let starPressed = (buttonsHigh & Self.eightBitDoStarMask) != 0

        storage.lock.lock()
        let homeChanged = homePressed != storage.lastEightBitDoHomeState
        let starChanged = starPressed != storage.lastEightBitDoStarState
        if homeChanged { storage.lastEightBitDoHomeState = homePressed }
        if starChanged { storage.lastEightBitDoStarState = starPressed }
        // Only bump activity on an actual edge — this callback fires on every
        // report (high rate), and unconditionally stamping would keep the pad
        // perpetually "active" for idle detection.
        if homeChanged || starChanged {
            storage.lastInputTime = CFAbsoluteTimeGetCurrent()
        }
        storage.lock.unlock()

        if homeChanged {
            controllerQueue.async { [weak self] in
                self?.handleButton(.xbox, pressed: homePressed)
            }
        }
        if starChanged {
            controllerQueue.async { [weak self] in
                self?.handleButton(.share, pressed: starPressed)
            }
        }
    }
}
