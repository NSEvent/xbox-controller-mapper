import Foundation
import CoreGraphics

// MARK: - KeyBindingRepresentable Protocol

/// Protocol for types that represent a key binding with modifiers
protocol KeyBindingRepresentable {
    var keyCode: CGKeyCode? { get }
    var modifiers: ModifierFlags { get }
}

// MARK: - ExecutableAction Protocol

/// Protocol for mapping types that can be executed (key press, macro, or system command)
protocol ExecutableAction: KeyBindingRepresentable {
    var macroId: UUID? { get }
    var systemCommand: SystemCommand? { get }
    var hint: String? { get }
    var displayString: String { get }
}

extension ExecutableAction {
    /// Returns hint if available, otherwise displayString
    var feedbackString: String {
        if let hint = hint, !hint.isEmpty {
            return hint
        }
        return displayString
    }
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
struct KeyMapping: Codable, Equatable, ExecutableAction {
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

    /// Optional system command to execute instead of key press
    var systemCommand: SystemCommand?

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
        systemCommand: SystemCommand? = nil,
        hint: String? = nil
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.longHoldMapping = longHoldMapping
        self.doubleTapMapping = doubleTapMapping
        self.repeatMapping = repeatMapping
        self.isHoldModifier = isHoldModifier
        self.macroId = macroId
        self.systemCommand = systemCommand
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, longHoldMapping, doubleTapMapping, repeatMapping, isHoldModifier, macroId, systemCommand, hint
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
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
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

    /// Human-readable description of the mapping
    var displayString: String {
        if let systemCommand = systemCommand {
            return systemCommand.displayName
        }
        if macroId != nil {
            return "Macro"
        }
        
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

        return parts.joined(separator: " + ")
    }
    
    /// Whether this binding has any action
    var isEmpty: Bool {
        return keyCode == nil && !modifiers.hasAny && macroId == nil && systemCommand == nil
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
struct LongHoldMapping: Codable, Equatable, ExecutableAction {
    private static let defaultThreshold: TimeInterval = 0.5

    var keyCode: CGKeyCode?
    var modifiers: ModifierFlags
    var threshold: TimeInterval
    var macroId: UUID?
    var systemCommand: SystemCommand?
    var hint: String?

    private static func sanitizedThreshold(_ threshold: TimeInterval) -> TimeInterval {
        guard threshold.isFinite, threshold > 0 else { return defaultThreshold }
        return threshold
    }

    init(keyCode: CGKeyCode? = nil, modifiers: ModifierFlags = ModifierFlags(), threshold: TimeInterval = 0.5, macroId: UUID? = nil, systemCommand: SystemCommand? = nil, hint: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.threshold = Self.sanitizedThreshold(threshold)
        self.macroId = macroId
        self.systemCommand = systemCommand
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, threshold, macroId, systemCommand, hint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
        let decodedThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .threshold) ?? Self.defaultThreshold
        threshold = Self.sanitizedThreshold(decodedThreshold)
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
    }

    var displayString: String {
        if let systemCommand = systemCommand {
            return systemCommand.displayName
        }
        if macroId != nil {
            return "Macro"
        }
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
        return parts.joined(separator: " + ")
    }

    var isEmpty: Bool {
        keyCode == nil && !modifiers.hasAny && macroId == nil && systemCommand == nil
    }
}

/// Wraps double tap configuration
struct DoubleTapMapping: Codable, Equatable, ExecutableAction {
    private static let defaultThreshold: TimeInterval = 0.3

    var keyCode: CGKeyCode?
    var modifiers: ModifierFlags
    /// Time window within which two taps must occur to count as double-tap (default 0.3s)
    var threshold: TimeInterval
    var macroId: UUID?
    var systemCommand: SystemCommand?
    var hint: String?

    private static func sanitizedThreshold(_ threshold: TimeInterval) -> TimeInterval {
        guard threshold.isFinite, threshold > 0 else { return defaultThreshold }
        return threshold
    }

    init(keyCode: CGKeyCode? = nil, modifiers: ModifierFlags = ModifierFlags(), threshold: TimeInterval = 0.3, macroId: UUID? = nil, systemCommand: SystemCommand? = nil, hint: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.threshold = Self.sanitizedThreshold(threshold)
        self.macroId = macroId
        self.systemCommand = systemCommand
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, threshold, macroId, systemCommand, hint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
        let decodedThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .threshold) ?? Self.defaultThreshold
        threshold = Self.sanitizedThreshold(decodedThreshold)
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
    }

    var displayString: String {
        if let systemCommand = systemCommand {
            return systemCommand.displayName
        }
        if macroId != nil {
            return "Macro"
        }
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
        return parts.joined(separator: " + ")
    }

    var isEmpty: Bool {
        keyCode == nil && !modifiers.hasAny && macroId == nil && systemCommand == nil
    }
}

/// Wraps repeat-while-held configuration
struct RepeatMapping: Codable, Equatable {
    private static let defaultInterval: TimeInterval = 0.2

    /// Whether repeat is enabled
    var enabled: Bool
    /// Interval between repeats in seconds (default 0.2s = 5 per second)
    var interval: TimeInterval

    private static func sanitizedInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite, interval > 0 else { return defaultInterval }
        return interval
    }

    init(enabled: Bool = false, interval: TimeInterval = 0.2) {
        self.enabled = enabled
        self.interval = Self.sanitizedInterval(interval)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let decodedInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? Self.defaultInterval
        interval = Self.sanitizedInterval(decodedInterval)
    }

    /// Repeat rate in actions per second
    var ratePerSecond: Double {
        get { 1.0 / Self.sanitizedInterval(interval) }
        set {
            interval = newValue.isFinite && newValue > 0 ? (1.0 / newValue) : Self.defaultInterval
        }
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
        return flags
    }

    static let command = ModifierFlags(command: true)
    static let option = ModifierFlags(option: true)
    static let shift = ModifierFlags(shift: true)
    static let control = ModifierFlags(control: true)
}
