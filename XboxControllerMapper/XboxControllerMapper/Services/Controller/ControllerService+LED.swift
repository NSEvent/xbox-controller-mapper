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

// MARK: - DualSense LED Control

@MainActor
extension ControllerService {

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
            storage.isDualSenseEdge = isEdge
            storage.lock.unlock()
            UserDefaults.standard.set(isEdge, forKey: Config.lastControllerWasDualSenseEdgeKey)
        }
    }

    /// Applies LED settings to the connected DualSense controller.
    /// Over USB: sends a full HID output report (light bar, player LEDs, mute LED, brightness).
    /// Over Bluetooth: uses GCController.light for the light bar color (only channel macOS allows).
    ///   Player LEDs, mute button LED, and brightness require USB.
    func applyLEDSettings(_ settings: DualSenseLEDSettings) {
        storage.lock.lock()
        let isDualSense = storage.isDualSense
        let isBluetooth = storage.isBluetoothConnection
        storage.currentLEDSettings = settings
        storage.lock.unlock()

        guard isDualSense else {
            #if DEBUG
            print("[LED] No DualSense device available (isDualSense=\(isDualSense))")
            #endif
            return
        }

        if isBluetooth {
            #if DEBUG
            print("[LED] Applying light bar color via GCController.light (Bluetooth)")
            #endif
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
    }

    /// Sets light bar color via GCController.light — works over Bluetooth.
    /// This is the only LED control channel macOS exposes over BT.
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
        // Build report WITHOUT report ID at position 0 (IOHIDDeviceSetReport takes it separately)
        // Total size is 77 bytes (78 - 1 for report ID)
        var report = [UInt8](repeating: 0, count: DualSenseHIDConstants.bluetoothReportSize - 1)

        // Bluetooth header per Linux kernel hid-playstation.c:
        // - Byte 0: seq_tag = (sequence_number << 4) | tag_field
        // - Byte 1: tag = 0x10 (DS_OUTPUT_TAG)
        report[0] = (bluetoothOutputSeq << 4) | 0x00  // Upper 4 bits = seq number, lower 4 bits = 0
        report[1] = 0x10  // DS_OUTPUT_TAG

        // Increment sequence number (wraps at 16)
        bluetoothOutputSeq = (bluetoothOutputSeq + 1) & 0x0F

        // Data starts at byte 2 (after seq_tag, tag)
        let dataOffset = 2

        // Valid flags - same as USB
        report[dataOffset + 0] = 0xFF  // flag0: enable all
        report[dataOffset + 1] = 0x57  // flag1: 0x01|0x02|0x04|0x10|0x40

        // Set valid_flag2 for LED brightness and lightbar setup control
        report[dataOffset + DualSenseHIDConstants.validFlag2Offset] =
            DualSenseHIDConstants.validFlag2LEDBrightness | DualSenseHIDConstants.validFlag2LightbarSetup

        // Mute button LED (byte 9 from data start)
        report[dataOffset + DualSenseHIDConstants.muteButtonLEDOffset] = settings.muteButtonLED.byteValue

        // Player/mute LED brightness (byte 43 from data start) - values 0-2
        report[dataOffset + DualSenseHIDConstants.ledBrightnessOffset] = settings.lightBarBrightness.playerLEDBrightness

        // Player LEDs (byte 44 from data start)
        report[dataOffset + DualSenseHIDConstants.playerLEDsOffset] = settings.playerLEDs.bitmask

        // Light bar color (bytes 45, 46, 47 from data start) - apply brightness multiplier to RGB
        let brightness = UInt16(settings.lightBarBrightness.multiplier)
        report[dataOffset + DualSenseHIDConstants.lightbarRedOffset] = UInt8(UInt16(settings.lightBarColor.redByte) * brightness / 255)
        report[dataOffset + DualSenseHIDConstants.lightbarGreenOffset] = UInt8(UInt16(settings.lightBarColor.greenByte) * brightness / 255)
        report[dataOffset + DualSenseHIDConstants.lightbarBlueOffset] = UInt8(UInt16(settings.lightBarColor.blueByte) * brightness / 255)

        // Calculate CRC32 for Bluetooth (last 4 bytes)
        // CRC is computed over: seed byte (0xA2) + report ID (0x31) + bytes 0-72 of report
        let crcData = Data([0xA2, DualSenseHIDConstants.bluetoothOutputReportID] + report[0..<73])
        let crc = crc32(crcData)
        report[73] = UInt8(crc & 0xFF)
        report[74] = UInt8((crc >> 8) & 0xFF)
        report[75] = UInt8((crc >> 16) & 0xFF)
        report[76] = UInt8((crc >> 24) & 0xFF)

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

    func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB88320 : 0)
            }
        }
        return ~crc
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
