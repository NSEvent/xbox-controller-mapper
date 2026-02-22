import Foundation
import IOKit
import IOKit.hid

// MARK: - PlayStation HID Monitoring (PS button, mic, Edge paddles)

/// Weak callback context for the PlayStation HID input report callback.
/// Prevents use-after-free when ControllerService is deallocated while a
/// pending HID callback fires on the run loop.
fileprivate final class PSHIDCallbackContext {
    weak var service: ControllerService?
    init(service: ControllerService) { self.service = service }
}

@MainActor
extension ControllerService {

    func setupPlayStationHIDMonitoring() {
        // Clean up any existing HID manager
        cleanupHIDMonitoring()

        // Allocate report buffer (must persist for callbacks)
        hidReportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 100)

        // Create HID manager
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else { return }

        // Match all PlayStation controllers
        let dualSenseDict: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x054C,  // Sony
            kIOHIDProductIDKey as String: 0x0CE6, // DualSense
        ]
        let dualSenseEdgeDict: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x054C,  // Sony
            kIOHIDProductIDKey as String: 0x0DF2, // DualSense Edge
        ]
        let dualShock4V1Dict: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x054C,  // Sony
            kIOHIDProductIDKey as String: 0x05C4, // DualShock 4 v1
        ]
        let dualShock4V2Dict: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x054C,  // Sony
            kIOHIDProductIDKey as String: 0x09CC, // DualShock 4 v2
        ]
        let matchingDicts = [dualSenseDict, dualSenseEdgeDict, dualShock4V1Dict, dualShock4V2Dict] as CFArray
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts)

        // Schedule with run loop first
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        // Get connected devices and set up input report callback on each
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices {
                setupHIDDeviceCallback(device)
            }
        }
    }

    func setupHIDDeviceCallback(_ device: IOHIDDevice) {
        hidDevice = device
        detectConnectionType(device: device)

        // DualSense-specific detection
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
        let isDualSenseDevice = (productID == 0x0CE6 || productID == 0x0DF2)

        if isDualSenseDevice {
            detectDualSenseEdge(device: device)
        }

        guard let buffer = hidReportBuffer else { return }

        let ctx = PSHIDCallbackContext(service: self)
        let retainedContext = Unmanaged.passRetained(ctx).toOpaque()
        psHIDCallbackContext = retainedContext
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 100, { context, result, sender, type, reportID, report, reportLength in
            guard let context = context else { return }
            let holder = Unmanaged<PSHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
            guard let service = holder.service else { return }
            service.handleHIDReport(reportID: reportID, report: report, length: Int(reportLength))
        }, retainedContext)

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Enable microphone when connected via USB (DualSense only)
        if isDualSenseDevice {
            storage.lock.lock()
            let isBluetooth = storage.isBluetoothConnection
            storage.lock.unlock()
            if !isBluetooth {
                enableMicrophone(device: device)
            }
        }
    }

    func cleanupHIDMonitoring() {
        if let device = hidDevice {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        hidDevice = nil

        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        hidManager = nil

        if let buffer = hidReportBuffer {
            buffer.deallocate()
        }
        hidReportBuffer = nil

        if let ctx = psHIDCallbackContext {
            Unmanaged<PSHIDCallbackContext>.fromOpaque(ctx).release()
            psHIDCallbackContext = nil
        }
    }

    nonisolated func handleHIDReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        // Determine button byte offset based on controller type and report ID
        //
        // DualSense USB  (0x01): buttons3 at byte 10
        // DualSense BT   (0x31): buttons3 at byte 11 (extra header byte)
        // DualShock 4 USB (0x01): buttons3 at byte 7
        // DualShock 4 BT  (0x11): buttons3 at byte 9 (2 extra header bytes)
        //
        // All share the same bit layout for buttons3:
        //   Bit 0: PS button, Bit 1: Touchpad button, Bit 2: Mic mute (DualSense only)

        storage.lock.lock()
        let isDualShockController = storage.isDualShock
        storage.lock.unlock()

        let buttons3Offset: Int
        if isDualShockController {
            // DualShock 4 reports
            if reportID == 0x11 && length >= 10 {
                buttons3Offset = 9   // Bluetooth extended report
            } else if reportID == 0x01 && length >= 8 {
                buttons3Offset = 7   // USB report
            } else {
                return
            }
        } else {
            // DualSense reports
            if reportID == 0x31 && length >= 12 {
                buttons3Offset = 11  // Bluetooth
            } else if reportID == 0x01 && length >= 11 {
                buttons3Offset = 10  // USB
            } else {
                return
            }
        }

        // buttons3 contains PS/Touch/Mute and Edge paddles
        // Bit 0: PS button, Bit 1: Touchpad button, Bit 2: Mic mute
        // DualSense Edge additional buttons (bits 4-7):
        // Bit 4: Left function (0x10), Bit 5: Right function (0x20)
        // Bit 6: Left paddle (0x40), Bit 7: Right paddle (0x80)
        let buttons3 = report[buttons3Offset]
        let psPressed = (buttons3 & 0x01) != 0
        let micPressed = isDualShockController ? false : (buttons3 & 0x04) != 0

        // DualSense Edge buttons (not applicable to DualShock)
        let leftFnPressed = (buttons3 & 0x10) != 0
        let rightFnPressed = (buttons3 & 0x20) != 0
        let leftPaddlePressed = (buttons3 & 0x40) != 0
        let rightPaddlePressed = (buttons3 & 0x80) != 0

        // Detect state changes (thread-safe)
        storage.lock.lock()
        let psChanged = psPressed != storage.lastPSButtonState
        let micChanged = micPressed != storage.lastMicButtonState
        let isEdge = storage.isDualSenseEdge

        // Edge button state changes
        let leftFnChanged = leftFnPressed != storage.lastLeftFunctionState
        let rightFnChanged = rightFnPressed != storage.lastRightFunctionState
        let leftPaddleChanged = leftPaddlePressed != storage.lastLeftPaddleState
        let rightPaddleChanged = rightPaddlePressed != storage.lastRightPaddleState

        if psChanged {
            storage.lastPSButtonState = psPressed
        }
        if micChanged {
            storage.lastMicButtonState = micPressed
        }
        if leftFnChanged {
            storage.lastLeftFunctionState = leftFnPressed
        }
        if rightFnChanged {
            storage.lastRightFunctionState = rightFnPressed
        }
        if leftPaddleChanged {
            storage.lastLeftPaddleState = leftPaddlePressed
        }
        if rightPaddleChanged {
            storage.lastRightPaddleState = rightPaddlePressed
        }
        storage.lock.unlock()

        if psChanged {
            controllerQueue.async { [weak self] in
                self?.handleButton(.xbox, pressed: psPressed)
            }
        }
        if micChanged {
            controllerQueue.async { [weak self] in
                self?.handleButton(.micMute, pressed: micPressed)
            }
        }

        // Only process Edge buttons if this is actually an Edge controller
        if isEdge {
            if leftFnChanged {
                controllerQueue.async { [weak self] in
                    self?.handleButton(.leftFunction, pressed: leftFnPressed)
                }
            }
            if rightFnChanged {
                controllerQueue.async { [weak self] in
                    self?.handleButton(.rightFunction, pressed: rightFnPressed)
                }
            }
            if leftPaddleChanged {
                controllerQueue.async { [weak self] in
                    self?.handleButton(.leftPaddle, pressed: leftPaddlePressed)
                }
            }
            if rightPaddleChanged {
                controllerQueue.async { [weak self] in
                    self?.handleButton(.rightPaddle, pressed: rightPaddlePressed)
                }
            }
        }
    }
}
