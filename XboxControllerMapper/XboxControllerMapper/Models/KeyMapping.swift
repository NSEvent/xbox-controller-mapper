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
    
    /// Optional ID of a macro to execute instead of key press
    var macroId: UUID?

    /// Optional user-provided description of what this mapping does
    var hint: String?

    init(
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags(),
        longHoldMapping: LongHoldMapping? = nil,
        doubleTapMapping: DoubleTapMapping? = nil,
        repeatMapping: RepeatMapping? = nil,
        isHoldModifier: Bool = false,
        macroId: UUID? = nil,
        hint: String? = nil
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.longHoldMapping = longHoldMapping
        self.doubleTapMapping = doubleTapMapping
        self.repeatMapping = repeatMapping
        self.isHoldModifier = isHoldModifier
        self.macroId = macroId
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, longHoldMapping, doubleTapMapping, repeatMapping, isHoldModifier, macroId, hint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
        longHoldMapping = try container.decodeIfPresent(LongHoldMapping.self, forKey: .longHoldMapping)
        doubleTapMapping = try container.decodeIfPresent(DoubleTapMapping.self, forKey: .doubleTapMapping)
        repeatMapping = try container.decodeIfPresent(RepeatMapping.self, forKey: .repeatMapping)
        isHoldModifier = try container.decodeIfPresent(Bool.self, forKey: .isHoldModifier) ?? false
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
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
    var hint: String?

    init(keyCode: CGKeyCode? = nil, modifiers: ModifierFlags = ModifierFlags(), threshold: TimeInterval = 0.5, hint: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.threshold = threshold
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, threshold, hint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
        threshold = try container.decodeIfPresent(TimeInterval.self, forKey: .threshold) ?? 0.5
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
    }
}

/// Wraps double tap configuration
struct DoubleTapMapping: Codable, Equatable, KeyBindingRepresentable {
    var keyCode: CGKeyCode?
    var modifiers: ModifierFlags
    /// Time window within which two taps must occur to count as double-tap (default 0.3s)
    var threshold: TimeInterval
    var hint: String?

    init(keyCode: CGKeyCode? = nil, modifiers: ModifierFlags = ModifierFlags(), threshold: TimeInterval = 0.3, hint: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.threshold = threshold
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, threshold, hint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
        threshold = try container.decodeIfPresent(TimeInterval.self, forKey: .threshold) ?? 0.3
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
    }
}

/// Wraps repeat-while-held configuration
struct RepeatMapping: Codable, Equatable {
    /// Whether repeat is enabled
    var enabled: Bool
    /// Interval between repeats in seconds (default 0.2s = 5 per second)
    var interval: TimeInterval

    init(enabled: Bool = false, interval: TimeInterval = 0.2) {
        self.enabled = enabled
        self.interval = interval
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        interval = try container.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? 0.2
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

    private enum CodingKeys: String, CodingKey {
        case command, option, shift, control
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decodeIfPresent(Bool.self, forKey: .command) ?? false
        option = try container.decodeIfPresent(Bool.self, forKey: .option) ?? false
        shift = try container.decodeIfPresent(Bool.self, forKey: .shift) ?? false
        control = try container.decodeIfPresent(Bool.self, forKey: .control) ?? false
    }

    init(command: Bool = false, option: Bool = false, shift: Bool = false, control: Bool = false) {
        self.command = command
        self.option = option
        self.shift = shift
        self.control = control
    }

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
