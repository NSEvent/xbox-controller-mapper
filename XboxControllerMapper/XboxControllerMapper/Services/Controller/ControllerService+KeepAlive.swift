import Foundation
import GameController
import IOKit
import IOKit.hid

// MARK: - DualShock 4 HID Constants

enum DualShock4HIDConstants {
    static let btOutputReportID: UInt8 = 0x11
    static let btReportSize = 78
    static let usbOutputReportID: UInt8 = 0x05
    static let usbReportSize = 32
}

// MARK: - Bluetooth Keep-Alive

@MainActor
extension ControllerService {

    /// UserDefaults-backed toggle; defaults to `true` on first launch.
    static var isKeepAliveEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: Config.keepAliveEnabledKey) == nil {
                return true  // default on first launch
            }
            return defaults.bool(forKey: Config.keepAliveEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Config.keepAliveEnabledKey)
        }
    }

    func startKeepAliveTimer() {
        stopKeepAliveTimer()

        guard threadSafeIsBluetoothConnection,
              threadSafeIsPlayStation,
              Self.isKeepAliveEnabled else { return }

        // Seed lastInputTime so we don't tickle immediately
        writeStorage(\.lastInputTime, CFAbsoluteTimeGetCurrent())

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + Config.keepAliveCheckInterval,
            repeating: Config.keepAliveCheckInterval,
            leeway: .seconds(2)
        )
        timer.setEventHandler { [weak self] in
            self?.keepAliveCheck()
        }
        timer.resume()
        keepAliveTimer = timer

        #if DEBUG
        print("[KeepAlive] Timer started (interval=\(Config.keepAliveCheckInterval)s, threshold=\(Config.keepAliveIdleThreshold)s)")
        #endif
    }

    func stopKeepAliveTimer() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
    }

    // MARK: - Idle Check

    private func keepAliveCheck() {
        guard Self.isKeepAliveEnabled,
              threadSafeIsBluetoothConnection,
              threadSafeIsPlayStation else { return }

        let lastInput = readStorage(\.lastInputTime)
        let idle = CFAbsoluteTimeGetCurrent() - lastInput

        guard idle >= Config.keepAliveIdleThreshold else { return }

        // Idle long enough — send a tickle
        if threadSafeIsDualSense {
            sendDualSenseTickle()
        } else if threadSafeIsDualShock {
            sendDualShock4TickleReport()
        }
    }

    // MARK: - DualSense Tickle

    /// Uses GCController.light to re-set the current light color. This works over
    /// Bluetooth because Apple's GameController framework has a privileged transport
    /// that bypasses the IOKit HID output report block on macOS.
    /// IOKit HID SetReport returns kIOReturnUnsupported for DualSense over BT,
    /// but GCController.light uses a private path that succeeds.
    private func sendDualSenseTickle() {
        guard let controller = connectedController,
              let light = controller.light else { return }

        // Re-set the current color — visually a no-op, but the controller
        // treats it as host activity and resets its sleep timer.
        let current = light.color
        light.color = GCColor(red: current.red, green: current.green, blue: current.blue)

        #if DEBUG
        print("[KeepAlive] Sent tickle (DualSense GCController.light)")
        #endif
    }

    // MARK: - DualShock 4 Tickle

    private func sendDualShock4TickleReport() {
        guard let device = hidDevice else { return }

        let isBluetooth = threadSafeIsBluetoothConnection

        if isBluetooth {
            sendDualShock4BluetoothTickle(device: device)
        } else {
            sendDualShock4USBTickle(device: device)
        }
    }

    private func sendDualShock4BluetoothTickle(device: IOHIDDevice) {
        // DS4 Bluetooth output report (report ID 0x11, 78 bytes total).
        // Report is sent WITHOUT the report ID byte (IOKit takes it separately).
        var report = [UInt8](repeating: 0, count: DualShock4HIDConstants.btReportSize - 1)

        // Header bytes (transaction type + poll interval flags)
        report[0] = 0x80  // HID transaction header
        report[1] = 0x00
        report[2] = 0xFF  // poll interval hint

        // Valid flags — enable rumble + LED section
        report[3] = 0xF7  // motor enable + LED flags
        report[4] = 0x04  // LED flag

        // Light bar RGB — dim blue (non-zero so controller knows it's a real report)
        report[8] = 0x00   // Red
        report[9] = 0x00   // Green
        report[10] = 0x40  // Blue

        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(DualShock4HIDConstants.btOutputReportID),
            report,
            report.count
        )

        #if DEBUG
        if result == kIOReturnSuccess {
            print("[KeepAlive] Sent tickle (DualShock 4 BT)")
        } else {
            print("[KeepAlive] DualShock 4 BT tickle failed: \(String(format: "0x%08X", result))")
        }
        #endif
    }

    private func sendDualShock4USBTickle(device: IOHIDDevice) {
        // DS4 USB output report (report ID 0x05, 32 bytes total).
        var report = [UInt8](repeating: 0, count: DualShock4HIDConstants.usbReportSize)

        // Report ID
        report[0] = DualShock4HIDConstants.usbOutputReportID

        // Valid flags — enable LED section
        report[1] = 0xFF

        // Light bar RGB — dim blue
        report[6] = 0x00   // Red
        report[7] = 0x00   // Green
        report[8] = 0x40   // Blue

        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(DualShock4HIDConstants.usbOutputReportID),
            report,
            report.count
        )

        #if DEBUG
        if result == kIOReturnSuccess {
            print("[KeepAlive] Sent tickle (DualShock 4 USB)")
        } else {
            print("[KeepAlive] DualShock 4 USB tickle failed: \(String(format: "0x%08X", result))")
        }
        #endif
    }
}
