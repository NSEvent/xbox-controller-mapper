import Foundation
import GameController
import IOKit
import IOKit.hid
import SwiftUI

// MARK: - DualSense HID Constants

enum DualSenseHIDConstants {
    // Report IDs
    static let usbOutputReportID: UInt8 = 0x02
    static let bluetoothOutputReportID: UInt8 = 0x31

    // Report sizes
    static let usbReportSize = 64
    static let bluetoothReportSize = 78

    // Common byte offsets (0-indexed within common data section)
    static let validFlag0Offset = 0
    static let validFlag1Offset = 1
    static let rightMotorOffset = 2
    static let leftMotorOffset = 3
    static let muteButtonLEDOffset = 8
    static let powerSaveControlOffset = 9
    static let validFlag2Offset = 38
    static let lightbarSetupOffset = 41
    static let ledBrightnessOffset = 42
    static let playerLEDsOffset = 43
    static let lightbarRedOffset = 44
    static let lightbarGreenOffset = 45
    static let lightbarBlueOffset = 46

    // Valid flag bits
    static let validFlag1MuteLED: UInt8 = 0x01
    static let validFlag1PowerSaveControl: UInt8 = 0x02
    static let validFlag1Lightbar: UInt8 = 0x04
    static let validFlag1PlayerLEDs: UInt8 = 0x10
    static let validFlag2LightbarSetup: UInt8 = 0x02
    static let validFlag2LEDBrightness: UInt8 = 0x01

    // Power save control bits
    static let powerSaveControlMicMute: UInt8 = 0x10

    // Lightbar setup value
    static let lightbarSetupEnable: UInt8 = 0x01
}

// MARK: - Pure BT LED report builders

/// Builds the raw Bluetooth LED output payloads (report ID passed separately
/// to IOHIDDeviceSetReport). Pure functions so unit tests can pin the exact
/// byte layout — these reports became load-bearing on macOS 27, where
/// GCDeviceLight is foreground-scoped and can't be verified on CI hardware.
enum PlayStationLEDReports {

    /// 77-byte DS4 BT payload (report ID 0x11). Layout per Linux hid-playstation.c.
    static func dualShock4Bluetooth(settings: DualSenseLEDSettings) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: DualShock4HIDConstants.btReportSize - 1)

        report[0] = 0xC0  // hw_control: DS4_OUTPUT_HWCTL_HID (0x80) | DS4_OUTPUT_HWCTL_CRC32 (0x40)
        report[2] = 0x03  // valid_flag0: MOTOR | LED (DS4 firmware needs both bits)

        let brightness = UInt16(settings.lightBarBrightness.multiplier)
        if settings.lightBarEnabled {
            report[7] = UInt8(UInt16(settings.lightBarColor.redByte) * brightness / 255)
            report[8] = UInt8(UInt16(settings.lightBarColor.greenByte) * brightness / 255)
            report[9] = UInt8(UInt16(settings.lightBarColor.blueByte) * brightness / 255)
        }
        // else: bytes 7-9 stay 0 (light bar off)

        // CRC32 over: seed (0xA2) + report ID (0x11) + bytes 0-72 of report
        let crcData = Data([0xA2, DualShock4HIDConstants.btOutputReportID] + report[0..<73])
        let crc = crc32(crcData)
        report[73] = UInt8(crc & 0xFF)
        report[74] = UInt8((crc >> 8) & 0xFF)
        report[75] = UInt8((crc >> 16) & 0xFF)
        report[76] = UInt8((crc >> 24) & 0xFF)
        return report
    }

    /// 77-byte DualSense BT payload (report ID 0x31). Layout per Linux hid-playstation.c.
    static func dualSenseBluetooth(settings: DualSenseLEDSettings, sequence: UInt8) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: DualSenseHIDConstants.bluetoothReportSize - 1)

        report[0] = (sequence << 4) | 0x00  // Upper 4 bits = seq number
        report[1] = 0x10  // DS_OUTPUT_TAG

        let dataOffset = 2
        report[dataOffset + 0] = 0xFF  // flag0: enable all
        report[dataOffset + 1] = 0x57  // flag1: 0x01|0x02|0x04|0x10|0x40
        report[dataOffset + DualSenseHIDConstants.validFlag2Offset] =
            DualSenseHIDConstants.validFlag2LEDBrightness | DualSenseHIDConstants.validFlag2LightbarSetup
        report[dataOffset + DualSenseHIDConstants.muteButtonLEDOffset] = settings.muteButtonLED.byteValue
        report[dataOffset + DualSenseHIDConstants.ledBrightnessOffset] = settings.lightBarBrightness.playerLEDBrightness
        report[dataOffset + DualSenseHIDConstants.playerLEDsOffset] = settings.playerLEDs.bitmask

        let brightness = UInt16(settings.lightBarBrightness.multiplier)
        report[dataOffset + DualSenseHIDConstants.lightbarRedOffset] = UInt8(UInt16(settings.lightBarColor.redByte) * brightness / 255)
        report[dataOffset + DualSenseHIDConstants.lightbarGreenOffset] = UInt8(UInt16(settings.lightBarColor.greenByte) * brightness / 255)
        report[dataOffset + DualSenseHIDConstants.lightbarBlueOffset] = UInt8(UInt16(settings.lightBarColor.blueByte) * brightness / 255)

        // CRC32 over: seed (0xA2) + report ID (0x31) + bytes 0-72 of report
        let crcData = Data([0xA2, DualSenseHIDConstants.bluetoothOutputReportID] + report[0..<73])
        let crc = crc32(crcData)
        report[73] = UInt8(crc & 0xFF)
        report[74] = UInt8((crc >> 8) & 0xFF)
        report[75] = UInt8((crc >> 16) & 0xFF)
        report[76] = UInt8((crc >> 24) & 0xFF)
        return report
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB88320 : 0)
            }
        }
        return ~crc
    }
}

// MARK: - DualSense LED Control

@MainActor
extension ControllerService {

    /// macOS 27 scopes GCDeviceLight to the foreground app: the system reverts
    /// the light bar (to white) when the setting app resigns active, while raw
    /// HID output reports still reach the controller from the background
    /// (Discord #bug-reports DP, 2026-09-19). On 27+ we send the raw BT report
    /// too; GCController.light still runs last so pre-27 behavior is unchanged.
    static var rawBluetoothLEDReportsNeeded: Bool {
        if #available(macOS 27.0, *) { return true }
        return false
    }

    /// Re-applies the last LED settings, e.g. when the app returns to the
    /// foreground and macOS 27 may have reverted the light bar.
    func reapplyCurrentLEDSettings() {
        guard let settings = storage.lock.withLock({ storage.currentLEDSettings }) else { return }
        applyLEDSettings(settings)
    }

    /// Fires on every LED settings apply when no PS controller is connected — once per
    /// process is enough signal, and unguarded it floods test logs (~1k lines per CI run).
    private static var didLogNoPlayStationController = false

    func detectConnectionType(device: IOHIDDevice) {
        if let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String {
            let isBluetooth = (transport.lowercased() == "bluetooth")
            #if DEBUG
            print("[LED] Detected connection type: \(transport) (isBluetooth=\(isBluetooth))")
            #endif
            storage.lock.lock()
            storage.isBluetoothConnection = isBluetooth
            storage.lock.unlock()
            // Update published property for UI
            isBluetoothConnection = isBluetooth
        } else {
            #if DEBUG
            print("[LED] Could not detect connection type, defaulting to USB")
            #endif
            isBluetoothConnection = false
        }
    }

    /// Detects if the connected device is a DualSense Edge (Pro) controller
    func detectDualSenseEdge(device: IOHIDDevice) {
        if let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int {
            let isEdge = (productID == 0x0DF2)
            #if DEBUG
            print("[HID] Detected product ID: 0x\(String(productID, radix: 16)) (isEdge=\(isEdge))")
            #endif
			storage.lock.lock()
			storage.applyControllerTypeLocked(isEdge ? .dualSenseEdge : .dualSense)
			storage.lock.unlock()
			UserDefaults.standard.set(isEdge, forKey: Config.lastControllerWasDualSenseEdgeKey)
		}
	}

    /// Applies LED settings to the connected DualSense controller.
    /// Over USB: sends a full HID output report (light bar, player LEDs, mute LED, brightness).
	/// Over Bluetooth: uses GCController.light for light-bar color and applies
	/// brightness by scaling RGB. Player and mute LEDs require USB.
    func applyLEDSettings(_ settings: DualSenseLEDSettings) {
        storage.lock.lock()
        let isDualSense = storage.isDualSense
        let isDualShock = storage.isDualShock
        let isBluetooth = storage.isBluetoothConnection
        storage.currentLEDSettings = settings
        storage.lock.unlock()

        if isDualSense {
            if isBluetooth {
                #if DEBUG
                print("[LED] Applying light bar color via GCController.light (Bluetooth)")
                #endif
                // macOS 27: raw report first so background color survives;
                // GCController.light last keeps foreground behavior identical.
                if Self.rawBluetoothLEDReportsNeeded, let device = hidDevice {
                    sendBluetoothOutputReport(device: device, settings: settings)
                }
                applyLightBarViaBluetooth(settings: settings)
            } else {
                guard let device = hidDevice else {
                    #if DEBUG
                    print("[LED] No HID device available for USB report")
                    #endif
                    return
                }
                #if DEBUG
                print("[LED] Applying settings via USB")
                #endif
                sendUSBOutputReport(device: device, settings: settings)
            }
        } else if isDualShock {
            // For DS4 over Bluetooth on macOS <= 26, IOHIDDeviceSetReport silently fails
            // (returns success but reports never reach the device — same as DualSense BT),
            // so GCController.light is the only working path there. On macOS 27 the raw
            // report does land while GCController.light is foreground-scoped, so send
            // both. Over USB, the HID report works directly.
            if isBluetooth {
                if Self.rawBluetoothLEDReportsNeeded, let device = hidDevice {
                    sendDualShock4BluetoothLEDReport(device: device, settings: settings)
                }
                applyLightBarViaBluetooth(settings: settings)
            } else if let device = hidDevice {
                #if DEBUG
                print("[LED] Applying DS4 light bar via USB HID")
                #endif
                sendDualShock4USBLEDReport(device: device, settings: settings)
            } else {
                applyLightBarViaBluetooth(settings: settings)
            }
        } else {
            #if DEBUG
            if !Self.didLogNoPlayStationController {
                Self.didLogNoPlayStationController = true
                print("[LED] No PlayStation controller available (isDualSense=\(isDualSense), isDualShock=\(isDualShock))")
            }
            #endif
            return
        }
    }

    /// Sets light bar color via GCController.light — works over Bluetooth.
    /// On macOS <= 26 this is the only LED control channel over BT:
    /// IOHIDDeviceSetReport returns success but the kernel silently drops reports for
    /// controllers managed by the GameController framework. On macOS 27 this path is
    /// foreground-scoped (system reverts the bar when the app resigns active), so the
    /// callers above also send the raw BT report there.
    private func applyLightBarViaBluetooth(settings: DualSenseLEDSettings) {
        guard let controller = connectedController,
              let light = controller.light else {
            #if DEBUG
            print("[LED] GCController.light not available")
            #endif
            return
        }

        if settings.lightBarEnabled {
            let brightness = Double(settings.lightBarBrightness.multiplier) / 255.0
            light.color = GCColor(
                red: Float(settings.lightBarColor.red * brightness),
                green: Float(settings.lightBarColor.green * brightness),
                blue: Float(settings.lightBarColor.blue * brightness)
            )
        } else {
            light.color = GCColor(red: 0, green: 0, blue: 0)
        }
    }

    func sendUSBOutputReport(device: IOHIDDevice, settings: DualSenseLEDSettings) {
        var report = [UInt8](repeating: 0, count: DualSenseHIDConstants.usbReportSize)

        // Report ID
        report[0] = DualSenseHIDConstants.usbOutputReportID

        // Valid flags - pydualsense uses 0xFF for flag0 and 0x57 for flag1
        let dataOffset = 1
        report[dataOffset + 0] = 0xFF  // flag0: enable all
        report[dataOffset + 1] = 0x57  // flag1: 0x01|0x02|0x04|0x10|0x40 (LED strips, mic, player LEDs)

        // Set valid_flag2 for LED brightness and lightbar setup control
        report[dataOffset + DualSenseHIDConstants.validFlag2Offset] =
            DualSenseHIDConstants.validFlag2LEDBrightness | DualSenseHIDConstants.validFlag2LightbarSetup

        // Mute button LED (byte 9)
        report[dataOffset + DualSenseHIDConstants.muteButtonLEDOffset] = settings.muteButtonLED.byteValue

        // Player/mute LED brightness (byte 43) - values 0-2
        report[dataOffset + DualSenseHIDConstants.ledBrightnessOffset] = settings.lightBarBrightness.playerLEDBrightness

        // Player LEDs (byte 44)
        report[dataOffset + DualSenseHIDConstants.playerLEDsOffset] = settings.playerLEDs.bitmask

        // Light bar color (bytes 45, 46, 47) - apply brightness multiplier to RGB
        let brightness = UInt16(settings.lightBarBrightness.multiplier)
        report[dataOffset + DualSenseHIDConstants.lightbarRedOffset] = UInt8(UInt16(settings.lightBarColor.redByte) * brightness / 255)
        report[dataOffset + DualSenseHIDConstants.lightbarGreenOffset] = UInt8(UInt16(settings.lightBarColor.greenByte) * brightness / 255)
        report[dataOffset + DualSenseHIDConstants.lightbarBlueOffset] = UInt8(UInt16(settings.lightBarColor.blueByte) * brightness / 255)

        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(DualSenseHIDConstants.usbOutputReportID),
            report,
            report.count
        )

        #if DEBUG
        if result != kIOReturnSuccess {
            print("Failed to send USB LED report: \(result)")
        }
        #endif
    }

    func sendBluetoothOutputReport(device: IOHIDDevice, settings: DualSenseLEDSettings) {
        // Report WITHOUT report ID at position 0 (IOHIDDeviceSetReport takes it
        // separately); layout lives in the pure builder so tests can pin it.
        let report = PlayStationLEDReports.dualSenseBluetooth(settings: settings, sequence: bluetoothOutputSeq)

        // Increment sequence number (wraps at 16)
        bluetoothOutputSeq = (bluetoothOutputSeq + 1) & 0x0F

        #if DEBUG
        // Debug: print first 10 bytes of report
        let headerBytes = report[0..<10].map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[LED] BT Report (no ID): \(headerBytes), seq=\((bluetoothOutputSeq + 15) & 0x0F)")
        #endif

        // Try Output Report first
        var result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(DualSenseHIDConstants.bluetoothOutputReportID),
            report,
            report.count
        )

        #if DEBUG
        if result == kIOReturnSuccess {
            print("[LED] Bluetooth output report sent successfully")
        } else {
            print("[LED] Output report failed (\(String(format: "0x%08X", result))), trying feature report...")
        }
        #endif

        if result != kIOReturnSuccess {
            // Try Feature Report as fallback (some macOS Bluetooth implementations handle these differently)
            result = IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeFeature,
                CFIndex(DualSenseHIDConstants.bluetoothOutputReportID),
                report,
                report.count
            )

            #if DEBUG
            if result == kIOReturnSuccess {
                print("[LED] Bluetooth feature report sent successfully")
            } else {
                print("[LED] Failed to send Bluetooth LED report: \(String(format: "0x%08X", result))")
            }
            #endif
        }
    }

    // MARK: - DualShock 4 LED Control

    /// Sends a USB output report to set the DS4 light bar color.
    /// Per Linux hid-playstation.c, layout is:
    ///   byte 0: report ID (0x05)
    ///   byte 1: valid_flag0 (0x01=motor, 0x02=led, 0x04=blink) — DS4 firmware requires
    ///           motor+led together (0x03), or it ignores both.
    ///   byte 2: valid_flag1 (0)
    ///   byte 3: reserved (0)
    ///   byte 4: motor_right (0 = no rumble)
    ///   byte 5: motor_left  (0 = no rumble)
    ///   byte 6: lightbar_red
    ///   byte 7: lightbar_green
    ///   byte 8: lightbar_blue
    /// Total 32 bytes.
    func sendDualShock4USBLEDReport(device: IOHIDDevice, settings: DualSenseLEDSettings) {
        var report = [UInt8](repeating: 0, count: DualShock4HIDConstants.usbReportSize)

        report[0] = DualShock4HIDConstants.usbOutputReportID
        report[1] = 0x03  // valid_flag0: MOTOR | LED (DS4 firmware needs both bits to update lightbar)

        // Light bar RGB — apply brightness multiplier
        let brightness = UInt16(settings.lightBarBrightness.multiplier)
        if settings.lightBarEnabled {
            report[6] = UInt8(UInt16(settings.lightBarColor.redByte) * brightness / 255)
            report[7] = UInt8(UInt16(settings.lightBarColor.greenByte) * brightness / 255)
            report[8] = UInt8(UInt16(settings.lightBarColor.blueByte) * brightness / 255)
        }
        // else: bytes 6-8 stay 0 (light bar off)

        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(DualShock4HIDConstants.usbOutputReportID),
            report,
            report.count
        )

        #if DEBUG
        if result != kIOReturnSuccess {
            print("[LED] DS4 USB LED report failed: \(String(format: "0x%08X", result))")
        }
        #endif
    }

    /// Sends a Bluetooth output report to set the DS4 light bar color.
    /// Per Linux hid-playstation.c, layout (with report ID stripped by IOHIDDeviceSetReport):
    ///   byte 0: hw_control (0xC0 = HID | CRC32 enable)
    ///   byte 1: audio_control (0)
    ///   byte 2: valid_flag0 (0x03 = MOTOR | LED — both bits required for DS4 firmware)
    ///   byte 3: valid_flag1 (0)
    ///   byte 4: reserved (0)
    ///   byte 5: motor_right (0 = no rumble)
    ///   byte 6: motor_left  (0 = no rumble)
    ///   byte 7: lightbar_red
    ///   byte 8: lightbar_green
    ///   byte 9: lightbar_blue
    ///   bytes 10-72: padding
    ///   bytes 73-76: CRC32 (last 4 bytes of 77)
    /// Total payload: 77 bytes (78-byte report minus the 1-byte report ID).
    /// CRC32 covers: seed byte (0xA2) + report ID (0x11) + report bytes 0-72.
    func sendDualShock4BluetoothLEDReport(device: IOHIDDevice, settings: DualSenseLEDSettings) {
        // Layout lives in the pure builder so tests can pin it.
        let report = PlayStationLEDReports.dualShock4Bluetooth(settings: settings)

        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(DualShock4HIDConstants.btOutputReportID),
            report,
            report.count
        )

        #if DEBUG
        if result != kIOReturnSuccess {
            print("[LED] DS4 BT LED report failed: \(String(format: "0x%08X", result))")
        }
        #endif
    }

    // MARK: - Party Mode

    func setPartyMode(_ enabled: Bool, savedSettings: DualSenseLEDSettings) {
        if enabled {
            startPartyMode()
        } else {
            stopPartyMode(restoreSettings: savedSettings)
        }
        partyModeEnabled = enabled
    }

    func startPartyMode() {
        partyHue = 0.0
        partyLEDIndex = 0
        partyLEDDirection = 1

        partyModeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePartyMode()
            }
        }
    }

    func stopPartyMode(restoreSettings: DualSenseLEDSettings) {
        partyModeTimer?.invalidate()
        partyModeTimer = nil
        applyLEDSettings(restoreSettings)
    }

    func updatePartyMode() {
        guard partyModeEnabled else { return }

        partyHue += 0.005
        if partyHue >= 1.0 {
            partyHue = 0.0
        }

        let frameCount = Int(partyHue * 200) % 15
        if frameCount == 0 {
            partyLEDIndex += partyLEDDirection
            if partyLEDIndex >= partyLEDPatterns.count - 1 {
                partyLEDDirection = -1
            } else if partyLEDIndex <= 0 {
                partyLEDDirection = 1
            }
        }

        let rainbowColor = Color(hue: partyHue, saturation: 1.0, brightness: 1.0)
        var partySettings = DualSenseLEDSettings()
        partySettings.lightBarEnabled = true
        partySettings.lightBarColor = CodableColor(color: rainbowColor)
        partySettings.lightBarBrightness = .bright
        partySettings.muteButtonLED = .breathing
        partySettings.playerLEDs = partyLEDPatterns[max(0, min(partyLEDIndex, partyLEDPatterns.count - 1))]

        applyLEDSettings(partySettings)
    }
}
