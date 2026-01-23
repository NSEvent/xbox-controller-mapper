import Foundation
import CoreGraphics

// MARK: - KeyBindingRepresentable Protocol

/// Protocol for types that represent a key binding with modifiers
protocol KeyBindingRepresentable {
    var keyCode: CGKeyCode? { get }
    var modifiers: ModifierFlags { get }
}

extension KeyBindingRepresentable {
    /// Human-readable description of the key binding
    var displayString: String {
        var parts: [String] = []

        if modifiers.command { parts.append("⌘") }
        if modifiers.option { parts.append("⌥") }
        if modifiers.shift { parts.append("⇧") }
        if modifiers.control { parts.append("⌃") }

        if let keyCode = keyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        }

        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    /// Whether this binding has any action
    var isEmpty: Bool {
        keyCode == nil && !modifiers.hasAny
    }
}

// MARK: - KeyMapping

/// Represents a keyboard shortcut mapping
struct KeyMapping: Codable, Equatable, KeyBindingRepresentable {
    /// The key code to simulate (nil for modifier-only mappings)
    var keyCode: CGKeyCode?

    /// Modifier flags to apply
    var modifiers: ModifierFlags

    /// Optional alternate mapping for long hold
    var longHoldMapping: LongHoldMapping?

    /// Optional alternate mapping for double tap
    var doubleTapMapping: DoubleTapMapping?

    /// Optional repeat configuration for holding the button
    var repeatMapping: RepeatMapping?

    /// Whether this mapping acts as a held modifier (released when button released)
    var isHoldModifier: Bool

    init(
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags(),
        longHoldMapping: LongHoldMapping? = nil,
        doubleTapMapping: DoubleTapMapping? = nil,
        repeatMapping: RepeatMapping? = nil,
        isHoldModifier: Bool = false
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.longHoldMapping = longHoldMapping
        self.doubleTapMapping = doubleTapMapping
        self.repeatMapping = repeatMapping
        self.isHoldModifier = isHoldModifier
    }

    /// Creates a simple key mapping
    static func key(_ keyCode: CGKeyCode) -> KeyMapping {
        KeyMapping(keyCode: keyCode)
    }

    /// Creates a modifier-only mapping that is held
    static func holdModifier(_ modifiers: ModifierFlags) -> KeyMapping {
        KeyMapping(modifiers: modifiers, isHoldModifier: true)
    }

    /// Creates a key + modifier combination
    static func combo(_ keyCode: CGKeyCode, modifiers: ModifierFlags) -> KeyMapping {
        KeyMapping(keyCode: keyCode, modifiers: modifiers)
    }

    /// Human-readable description of the mapping (overrides protocol to add hold indicator)
    var displayString: String {
        var parts: [String] = []

        if modifiers.command { parts.append("⌘") }
        if modifiers.option { parts.append("⌥") }
        if modifiers.shift { parts.append("⇧") }
        if modifiers.control { parts.append("⌃") }

        if let keyCode = keyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        } else if parts.isEmpty {
            return "None"
        }

        // Special handling for hold modifier mappings
        if isHoldModifier && keyCode == nil {
            return parts.joined() + " (hold)"
        }

        return parts.joined(separator: " + ")
    }

    /// Compact description including alternate mappings (for UI)
    var compactDescription: String {
        var parts: [String] = []

        if !isEmpty {
            parts.append(displayString)
        }

        if let longHold = longHoldMapping, !longHold.isEmpty {
            parts.append("⏱ " + longHold.displayString)
        }

        if let doubleTap = doubleTapMapping, !doubleTap.isEmpty {
            parts.append("×2 " + doubleTap.displayString)
        }

        if let repeatConfig = repeatMapping, repeatConfig.enabled {
            parts.append("↻ \(Int(repeatConfig.ratePerSecond))/s")
        }

        return parts.joined(separator: "\n")
    }

    // Note: isEmpty is provided by KeyBindingRepresentable protocol extension
}

/// Wraps long hold configuration to avoid recursive struct issues
struct LongHoldMapping: Codable, Equatable, KeyBindingRepresentable {
    var keyCode: CGKeyCode?
    var modifiers: ModifierFlags
    var threshold: TimeInterval

    init(keyCode: CGKeyCode? = nil, modifiers: ModifierFlags = ModifierFlags(), threshold: TimeInterval = 0.5) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.threshold = threshold
    }

    // Note: displayString and isEmpty are provided by KeyBindingRepresentable protocol extension
}

/// Wraps double tap configuration
struct DoubleTapMapping: Codable, Equatable, KeyBindingRepresentable {
    var keyCode: CGKeyCode?
    var modifiers: ModifierFlags
    /// Time window within which two taps must occur to count as double-tap (default 0.3s)
    var threshold: TimeInterval

    init(keyCode: CGKeyCode? = nil, modifiers: ModifierFlags = ModifierFlags(), threshold: TimeInterval = 0.3) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.threshold = threshold
    }

    // Note: displayString and isEmpty are provided by KeyBindingRepresentable protocol extension
}

/// Wraps repeat-while-held configuration
struct RepeatMapping: Codable, Equatable {
    /// Whether repeat is enabled
    var enabled: Bool
    /// Interval between repeats in seconds (default 0.1s = 10 per second)
    var interval: TimeInterval

    init(enabled: Bool = false, interval: TimeInterval = 0.1) {
        self.enabled = enabled
        self.interval = interval
    }

    /// Repeat rate in actions per second
    var ratePerSecond: Double {
        get { 1.0 / interval }
        set { interval = 1.0 / newValue }
    }
}

/// Represents modifier key flags in a Codable-friendly way
struct ModifierFlags: Codable, Equatable {
    var command: Bool = false
    var option: Bool = false
    var shift: Bool = false
    var control: Bool = false

    var hasAny: Bool {
        command || option || shift || control
    }

    /// Convert to CGEventFlags
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if option { flags.insert(.maskAlternate) }
        if shift { flags.insert(.maskShift) }
        if control { flags.insert(.maskControl) }
        #if DEBUG
        print("🏳️ cgEventFlags: cmd=\(command) opt=\(option) shift=\(shift) ctrl=\(control) -> rawValue=\(flags.rawValue)")
        #endif
        return flags
    }

    static let command = ModifierFlags(command: true)
    static let option = ModifierFlags(option: true)
    static let shift = ModifierFlags(shift: true)
    static let control = ModifierFlags(control: true)
}
