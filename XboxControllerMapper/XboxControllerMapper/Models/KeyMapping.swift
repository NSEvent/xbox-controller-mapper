import Foundation
import CoreGraphics

/// Represents a keyboard shortcut mapping
struct KeyMapping: Codable, Equatable {
    /// The key code to simulate (nil for modifier-only mappings)
    var keyCode: CGKeyCode?

    /// Modifier flags to apply
    var modifiers: ModifierFlags

    /// Optional alternate mapping for long hold
    var longHoldMapping: LongHoldMapping?

    /// Whether this mapping acts as a held modifier (released when button released)
    var isHoldModifier: Bool

    init(
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags(),
        longHoldMapping: LongHoldMapping? = nil,
        isHoldModifier: Bool = false
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.longHoldMapping = longHoldMapping
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

    /// Human-readable description of the mapping
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

        if isHoldModifier && keyCode == nil {
            return parts.joined() + " (hold)"
        }

        return parts.joined(separator: " + ")
    }

    /// Whether this mapping has any action
    var isEmpty: Bool {
        keyCode == nil && !modifiers.hasAny
    }
}

/// Wraps long hold configuration to avoid recursive struct issues
struct LongHoldMapping: Codable, Equatable {
    var keyCode: CGKeyCode?
    var modifiers: ModifierFlags
    var threshold: TimeInterval

    init(keyCode: CGKeyCode? = nil, modifiers: ModifierFlags = ModifierFlags(), threshold: TimeInterval = 0.5) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.threshold = threshold
    }

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

    var isEmpty: Bool {
        keyCode == nil && !modifiers.hasAny
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
        return flags
    }

    static let command = ModifierFlags(command: true)
    static let option = ModifierFlags(option: true)
    static let shift = ModifierFlags(shift: true)
    static let control = ModifierFlags(control: true)
}
