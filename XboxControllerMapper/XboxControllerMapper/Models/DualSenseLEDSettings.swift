import Foundation
import SwiftUI

/// LED brightness levels for DualSense light bar
enum LightBarBrightness: String, Codable, CaseIterable {
    case bright = "bright"
    case mid = "mid"
    case dim = "dim"

    /// Multiplier for RGB values (0-255 scale)
    var multiplier: UInt8 {
        switch self {
        case .bright: return 255
        case .mid: return 128
        case .dim: return 64
        }
    }

    /// Value for player LED brightness byte (0-2)
    var playerLEDBrightness: UInt8 {
        switch self {
        case .bright: return 0x00
        case .mid: return 0x01
        case .dim: return 0x02
        }
    }

    var displayName: String {
        switch self {
        case .bright: return "Bright"
        case .mid: return "Medium"
        case .dim: return "Dim"
        }
    }
}

/// Mute button LED modes
enum MuteButtonLEDMode: String, Codable, CaseIterable {
    case off = "off"
    case on = "on"
    case breathing = "breathing"

    var byteValue: UInt8 {
        switch self {
        case .off: return 0x00
        case .on: return 0x01
        case .breathing: return 0x02
        }
    }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .breathing: return "Breathing"
        }
    }
}

/// Player LED configuration (5 LEDs in center strip)
struct PlayerLEDs: Codable, Equatable {
    var led1: Bool = false
    var led2: Bool = false
    var led3: Bool = false
    var led4: Bool = false
    var led5: Bool = false

    var bitmask: UInt8 {
        var mask: UInt8 = 0
        if led1 { mask |= 0x01 }
        if led2 { mask |= 0x02 }
        if led3 { mask |= 0x04 }
        if led4 { mask |= 0x08 }
        if led5 { mask |= 0x10 }
        return mask
    }

    static let `default` = PlayerLEDs()

    /// Preset: Player 1 (center LED)
    static let player1 = PlayerLEDs(led1: false, led2: false, led3: true, led4: false, led5: false)
    /// Preset: Player 2 (two adjacent)
    static let player2 = PlayerLEDs(led1: false, led2: true, led3: false, led4: true, led5: false)
    /// Preset: Player 3 (three)
    static let player3 = PlayerLEDs(led1: true, led2: false, led3: true, led4: false, led5: true)
    /// Preset: Player 4 (four)
    static let player4 = PlayerLEDs(led1: true, led2: true, led3: false, led4: true, led5: true)
    /// Preset: All on
    static let allOn = PlayerLEDs(led1: true, led2: true, led3: true, led4: true, led5: true)
}

/// Wrapper for Color to make it Codable
struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(color: Color) {
        let nsColor = NSColor(color)
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Double(converted.redComponent)
        self.green = Double(converted.greenComponent)
        self.blue = Double(converted.blueComponent)
    }

    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Double(converted.redComponent)
        self.green = Double(converted.greenComponent)
        self.blue = Double(converted.blueComponent)
    }

    /// Convert to 0-255 byte values for HID report
    var redByte: UInt8 { UInt8(min(255, max(0, red * 255))) }
    var greenByte: UInt8 { UInt8(min(255, max(0, green * 255))) }
    var blueByte: UInt8 { UInt8(min(255, max(0, blue * 255))) }
}

/// Settings for DualSense LED control
struct DualSenseLEDSettings: Codable, Equatable {
    /// Light bar RGB color
    var lightBarColor: CodableColor = CodableColor(red: 0.0, green: 0.4, blue: 1.0)

    /// Light bar brightness
    var lightBarBrightness: LightBarBrightness = .bright

    /// Whether the light bar is enabled
    var lightBarEnabled: Bool = true

    /// Mute button LED mode
    var muteButtonLED: MuteButtonLEDMode = .off

    /// Player LEDs configuration
    var playerLEDs: PlayerLEDs = .default

    static let `default` = DualSenseLEDSettings()

    func isValid() -> Bool {
        return lightBarColor.red >= 0 && lightBarColor.red <= 1 &&
               lightBarColor.green >= 0 && lightBarColor.green <= 1 &&
               lightBarColor.blue >= 0 && lightBarColor.blue <= 1
    }
}
