import Foundation
import CoreGraphics
import Carbon.HIToolbox

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
    var scriptId: UUID? { get }
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

// MARK: - Action Type Classification

/// Identifies which kind of action a mapping performs.
enum ActionType: String, Equatable, CaseIterable {
    /// A keyboard key press (with optional modifiers)
    case keyPress
    /// A recorded macro sequence
    case macro
    /// A JavaScript script
    case script
    /// A system command (shell, launch app, open link, webhook, OBS)
    case systemCommand
    /// No action configured
    case none
}

// MARK: - Scroll Action Settings

/// Per-action tuning for scroll marker mappings.
struct ScrollActionSettings: Codable, Equatable {
    private static let unitRange = 0.0...1.0

    /// 0...1 speed slider value.
    var speed: Double

    /// 0...1 acceleration slider value.
    var acceleration: Double

    init(speed: Double = 0.5, acceleration: Double = 0.5) {
		self.speed = Self.clampedUnit(speed)
		self.acceleration = Self.clampedUnit(acceleration)
    }

    private enum CodingKeys: String, CodingKey {
		case speed, acceleration
    }

    init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		speed = try container.decode(.speed, default: 0.5, clampedTo: Self.unitRange)
		acceleration = try container.decode(.acceleration, default: 0.5, clampedTo: Self.unitRange)
    }

    /// Matches the global joystick scroll sensitivity curve.
    var scrollMultiplier: Double {
		1.0 + pow(speed, 1.5) * 29.0
    }

    /// Matches the global joystick scroll acceleration curve.
    var accelerationExponent: Double {
		1.0 + acceleration * 1.5
    }

    private static func clampedUnit(_ value: Double) -> Double {
		guard value.isFinite else { return 0.5 }
		return min(1.0, max(0.0, value))
    }
}

// MARK: - Action Conflict Validation

extension ExecutableAction {

    /// The number of distinct action types currently set on this mapping.
    ///
    /// A well-formed mapping should have exactly 0 or 1 active actions.
    /// Values greater than 1 indicate conflicting fields.
    var activeActionCount: Int {
        var count = 0
        if keyCode != nil || modifiers.hasAny { count += 1 }
        if macroId != nil { count += 1 }
        if scriptId != nil { count += 1 }
        if systemCommand != nil { count += 1 }
        return count
    }

    /// Whether this mapping has more than one action type set simultaneously.
    ///
    /// When `true`, the execution layer will silently pick one action based on
    /// priority (systemCommand > macro > script > keyPress) and ignore the rest.
    /// This property lets callers detect that ambiguous state.
    var hasConflictingActions: Bool {
        activeActionCount > 1
    }

    /// The action type that the execution layer would actually run.
    ///
    /// Priority matches `MappingActionExecutor.executeAction`:
    ///   1. systemCommand
    ///   2. macroId
    ///   3. scriptId
    ///   4. keyCode / modifiers (key press)
    ///
    /// Returns `.none` when no action is configured.
    var effectiveActionType: ActionType {
        if systemCommand != nil { return .systemCommand }
        if macroId != nil { return .macro }
        if scriptId != nil { return .script }
        if keyCode != nil || modifiers.hasAny { return .keyPress }
        return .none
    }

    /// Returns all action types that are currently set on this mapping.
    var activeActionTypes: Set<ActionType> {
        var types = Set<ActionType>()
        if keyCode != nil || modifiers.hasAny { types.insert(.keyPress) }
        if macroId != nil { types.insert(.macro) }
        if scriptId != nil { types.insert(.script) }
        if systemCommand != nil { types.insert(.systemCommand) }
        return types
    }

    /// Logs a warning via `NSLog` if multiple action types are set simultaneously.
    ///
    /// Call this at load-time or before execution to surface data-model issues.
    func validateActions(context: String = "") {
        guard hasConflictingActions else { return }
        let types = activeActionTypes.map(\.rawValue).sorted().joined(separator: ", ")
        let prefix = context.isEmpty ? "" : "[\(context)] "
        NSLog("[ActionConflict] %@Mapping has %d conflicting actions: %@. Effective action: %@",
              prefix, activeActionCount, types, effectiveActionType.rawValue)
    }
}

extension KeyBindingRepresentable {
    /// Human-readable description of the key binding
    var displayString: String {
        var parts: [String] = []

        if modifiers.command { parts.append(ModifierFlags.label(for: modifiers.commandSide) + "⌘") }
        if modifiers.option { parts.append(ModifierFlags.label(for: modifiers.optionSide) + "⌥") }
        if modifiers.shift { parts.append(ModifierFlags.label(for: modifiers.shiftSide) + "⇧") }
        if modifiers.control { parts.append(ModifierFlags.label(for: modifiers.controlSide) + "⌃") }

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

    /// Optional per-action tuning for scroll marker mappings.
    var scrollActionSettings: ScrollActionSettings?

    /// Whether this mapping acts as a held modifier (released when button released)
    var isHoldModifier: Bool

    /// Whether to re-post keyDown events periodically while held (simulates OS key repeat)
    var holdRepeatEnabled: Bool

    /// Interval between re-posted keyDown events when holdRepeatEnabled is true (default ~30/s)
    var holdRepeatInterval: TimeInterval
    
    /// Optional ID of a macro to execute instead of key press
    var macroId: UUID?

    /// Optional ID of a script to execute instead of key press
    var scriptId: UUID?

    /// Optional system command to execute instead of key press
    var systemCommand: SystemCommand?

    /// Optional user-provided description of what this mapping does
    var hint: String?

    /// Optional haptic feedback style to play when this action fires
    var hapticStyle: HapticStyle?

    init(
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags(),
        longHoldMapping: LongHoldMapping? = nil,
        doubleTapMapping: DoubleTapMapping? = nil,
        repeatMapping: RepeatMapping? = nil,
		scrollActionSettings: ScrollActionSettings? = nil,
        isHoldModifier: Bool = false,
        holdRepeatEnabled: Bool = false,
        holdRepeatInterval: TimeInterval = 0.033,
        macroId: UUID? = nil,
        scriptId: UUID? = nil,
        systemCommand: SystemCommand? = nil,
        hint: String? = nil,
        hapticStyle: HapticStyle? = nil
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.longHoldMapping = longHoldMapping
        self.doubleTapMapping = doubleTapMapping
        self.repeatMapping = repeatMapping
		self.scrollActionSettings = scrollActionSettings
        self.isHoldModifier = isHoldModifier
        self.holdRepeatEnabled = holdRepeatEnabled
        self.holdRepeatInterval = holdRepeatInterval
        self.macroId = macroId
        self.scriptId = scriptId
        self.systemCommand = systemCommand
        self.hint = hint
        self.hapticStyle = hapticStyle
    }

    private enum CodingKeys: String, CodingKey {
		case keyCode, modifiers, longHoldMapping, doubleTapMapping, repeatMapping, scrollActionSettings, isHoldModifier, holdRepeatEnabled, holdRepeatInterval, macroId, scriptId, systemCommand, hint, hapticStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decode(.modifiers, default: ModifierFlags())
        longHoldMapping = try container.decodeIfPresent(LongHoldMapping.self, forKey: .longHoldMapping)
        doubleTapMapping = try container.decodeIfPresent(DoubleTapMapping.self, forKey: .doubleTapMapping)
        repeatMapping = try container.decodeIfPresent(RepeatMapping.self, forKey: .repeatMapping)
		scrollActionSettings = try container.decodeIfPresent(ScrollActionSettings.self, forKey: .scrollActionSettings)
        isHoldModifier = try container.decode(.isHoldModifier, default: false)
        holdRepeatEnabled = try container.decode(.holdRepeatEnabled, default: false)
        holdRepeatInterval = try container.decode(.holdRepeatInterval, default: 0.033)
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        scriptId = try container.decodeIfPresent(UUID.self, forKey: .scriptId)
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
        hapticStyle = try container.decodeIfPresent(HapticStyle.self, forKey: .hapticStyle)
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
        if scriptId != nil {
            return "Script"
        }

        var parts: [String] = []

        if modifiers.command { parts.append(ModifierFlags.label(for: modifiers.commandSide) + "⌘") }
        if modifiers.option { parts.append(ModifierFlags.label(for: modifiers.optionSide) + "⌥") }
        if modifiers.shift { parts.append(ModifierFlags.label(for: modifiers.shiftSide) + "⇧") }
        if modifiers.control { parts.append(ModifierFlags.label(for: modifiers.controlSide) + "⌃") }

        if let keyCode = keyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        } else if parts.isEmpty {
            return "None"
        }

        return parts.joined(separator: " + ")
    }

    /// Whether this binding has any action
    var isEmpty: Bool {
        return keyCode == nil && !modifiers.hasAny && macroId == nil && scriptId == nil && systemCommand == nil
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

		if isSmoothScrollAction {
			parts.append("Scroll \(Int((scrollActionSettings?.speed ?? 0.5) * 100))%")
		}

        return parts.joined(separator: "\n")
    }

    // Note: isEmpty is provided by KeyBindingRepresentable protocol extension

    var isSmoothScrollAction: Bool {
		guard let keyCode, KeyCodeMapping.isScrollAction(keyCode) else { return false }
		return scrollActionSettings != nil
    }

    // MARK: - Conflict Resolution

    /// Returns a copy of this mapping with all action fields cleared except the specified type.
    ///
    /// Use this when assigning a new action to ensure only one action type is set.
    /// For `.keyPress`, the existing `keyCode` and `modifiers` are preserved; all others are nil'd.
    /// For `.none`, all action fields are cleared.
    func clearingConflicts(keeping actionType: ActionType) -> KeyMapping {
        var copy = self
        if actionType != .keyPress {
            copy.keyCode = nil
            copy.modifiers = ModifierFlags()
			copy.scrollActionSettings = nil
        }
        if actionType != .macro {
            copy.macroId = nil
        }
        if actionType != .script {
            copy.scriptId = nil
        }
        if actionType != .systemCommand {
            copy.systemCommand = nil
        }
        return copy
    }
}

/// Wraps long hold configuration to avoid recursive struct issues
struct LongHoldMapping: Codable, Equatable, ExecutableAction {
    private static let defaultThreshold: TimeInterval = 0.5

    var keyCode: CGKeyCode?
    var modifiers: ModifierFlags
    var threshold: TimeInterval
    var macroId: UUID?
    var scriptId: UUID?
    var systemCommand: SystemCommand?
    var hint: String?
    var hapticStyle: HapticStyle?

    private static func sanitizedThreshold(_ threshold: TimeInterval) -> TimeInterval {
        guard threshold.isFinite, threshold > 0 else { return defaultThreshold }
        return threshold
    }

    init(keyCode: CGKeyCode? = nil, modifiers: ModifierFlags = ModifierFlags(), threshold: TimeInterval = 0.5, macroId: UUID? = nil, scriptId: UUID? = nil, systemCommand: SystemCommand? = nil, hint: String? = nil, hapticStyle: HapticStyle? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.threshold = Self.sanitizedThreshold(threshold)
        self.macroId = macroId
        self.scriptId = scriptId
        self.systemCommand = systemCommand
        self.hint = hint
        self.hapticStyle = hapticStyle
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, threshold, macroId, scriptId, systemCommand, hint, hapticStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decode(.modifiers, default: ModifierFlags())
        threshold = Self.sanitizedThreshold(try container.decode(.threshold, default: Self.defaultThreshold))
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        scriptId = try container.decodeIfPresent(UUID.self, forKey: .scriptId)
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
        hapticStyle = try container.decodeIfPresent(HapticStyle.self, forKey: .hapticStyle)
    }

    var displayString: String {
        if let systemCommand = systemCommand {
            return systemCommand.displayName
        }
        if macroId != nil {
            return "Macro"
        }
        if scriptId != nil {
            return "Script"
        }
        var parts: [String] = []
        if modifiers.command { parts.append(ModifierFlags.label(for: modifiers.commandSide) + "⌘") }
        if modifiers.option { parts.append(ModifierFlags.label(for: modifiers.optionSide) + "⌥") }
        if modifiers.shift { parts.append(ModifierFlags.label(for: modifiers.shiftSide) + "⇧") }
        if modifiers.control { parts.append(ModifierFlags.label(for: modifiers.controlSide) + "⌃") }
        if let keyCode = keyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        } else if parts.isEmpty {
            return "None"
        }
        return parts.joined(separator: " + ")
    }

    var isEmpty: Bool {
        keyCode == nil && !modifiers.hasAny && macroId == nil && scriptId == nil && systemCommand == nil
    }

    /// Returns a copy with all action fields cleared except the specified type.
    func clearingConflicts(keeping actionType: ActionType) -> LongHoldMapping {
        var copy = self
        if actionType != .keyPress {
            copy.keyCode = nil
            copy.modifiers = ModifierFlags()
        }
        if actionType != .macro { copy.macroId = nil }
        if actionType != .script { copy.scriptId = nil }
        if actionType != .systemCommand { copy.systemCommand = nil }
        return copy
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
    var scriptId: UUID?
    var systemCommand: SystemCommand?
    var hint: String?
    var hapticStyle: HapticStyle?

    private static func sanitizedThreshold(_ threshold: TimeInterval) -> TimeInterval {
        guard threshold.isFinite, threshold > 0 else { return defaultThreshold }
        return threshold
    }

    init(keyCode: CGKeyCode? = nil, modifiers: ModifierFlags = ModifierFlags(), threshold: TimeInterval = 0.3, macroId: UUID? = nil, scriptId: UUID? = nil, systemCommand: SystemCommand? = nil, hint: String? = nil, hapticStyle: HapticStyle? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.threshold = Self.sanitizedThreshold(threshold)
        self.macroId = macroId
        self.scriptId = scriptId
        self.systemCommand = systemCommand
        self.hint = hint
        self.hapticStyle = hapticStyle
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, threshold, macroId, scriptId, systemCommand, hint, hapticStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decode(.modifiers, default: ModifierFlags())
        threshold = Self.sanitizedThreshold(try container.decode(.threshold, default: Self.defaultThreshold))
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        scriptId = try container.decodeIfPresent(UUID.self, forKey: .scriptId)
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
        hapticStyle = try container.decodeIfPresent(HapticStyle.self, forKey: .hapticStyle)
    }

    var displayString: String {
        if let systemCommand = systemCommand {
            return systemCommand.displayName
        }
        if macroId != nil {
            return "Macro"
        }
        if scriptId != nil {
            return "Script"
        }
        var parts: [String] = []
        if modifiers.command { parts.append(ModifierFlags.label(for: modifiers.commandSide) + "⌘") }
        if modifiers.option { parts.append(ModifierFlags.label(for: modifiers.optionSide) + "⌥") }
        if modifiers.shift { parts.append(ModifierFlags.label(for: modifiers.shiftSide) + "⇧") }
        if modifiers.control { parts.append(ModifierFlags.label(for: modifiers.controlSide) + "⌃") }
        if let keyCode = keyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        } else if parts.isEmpty {
            return "None"
        }
        return parts.joined(separator: " + ")
    }

    var isEmpty: Bool {
        keyCode == nil && !modifiers.hasAny && macroId == nil && scriptId == nil && systemCommand == nil
    }

    /// Returns a copy with all action fields cleared except the specified type.
    func clearingConflicts(keeping actionType: ActionType) -> DoubleTapMapping {
        var copy = self
        if actionType != .keyPress {
            copy.keyCode = nil
            copy.modifiers = ModifierFlags()
        }
        if actionType != .macro { copy.macroId = nil }
        if actionType != .script { copy.scriptId = nil }
        if actionType != .systemCommand { copy.systemCommand = nil }
        return copy
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
        enabled = try container.decode(.enabled, default: false)
        interval = Self.sanitizedInterval(try container.decode(.interval, default: Self.defaultInterval))
    }

    /// Repeat rate in actions per second
    var ratePerSecond: Double {
        get { 1.0 / Self.sanitizedInterval(interval) }
        set {
            interval = newValue.isFinite && newValue > 0 ? (1.0 / newValue) : Self.defaultInterval
        }
    }
}

/// Identifies which physical side of a modifier key to press.
/// When nil on `ModifierFlags`, the modifier is treated generically (the OS sees
/// `.maskCommand` regardless and the simulator pre-presses the Left keycode).
enum ModifierSide: String, Codable, Equatable {
    case left
    case right
}

/// Represents modifier key flags in a Codable-friendly way
struct ModifierFlags: Codable, Equatable {
    var command: Bool = false
    var option: Bool = false
    var shift: Bool = false
    var control: Bool = false

    /// Optional left/right side for each modifier. nil means "either side" —
    /// the simulator presses the Left keycode by default. Only meaningful when
    /// the corresponding modifier flag is true.
    var commandSide: ModifierSide?
    var optionSide: ModifierSide?
    var shiftSide: ModifierSide?
    var controlSide: ModifierSide?

    private enum CodingKeys: String, CodingKey {
        case command, option, shift, control
        case commandSide, optionSide, shiftSide, controlSide
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(.command, default: false)
        option = try container.decode(.option, default: false)
        shift = try container.decode(.shift, default: false)
        control = try container.decode(.control, default: false)
        commandSide = try container.decodeIfPresent(ModifierSide.self, forKey: .commandSide)
        optionSide = try container.decodeIfPresent(ModifierSide.self, forKey: .optionSide)
        shiftSide = try container.decodeIfPresent(ModifierSide.self, forKey: .shiftSide)
        controlSide = try container.decodeIfPresent(ModifierSide.self, forKey: .controlSide)
    }

    init(
        command: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        control: Bool = false,
        commandSide: ModifierSide? = nil,
        optionSide: ModifierSide? = nil,
        shiftSide: ModifierSide? = nil,
        controlSide: ModifierSide? = nil
    ) {
        self.command = command
        self.option = option
        self.shift = shift
        self.control = control
        self.commandSide = commandSide
        self.optionSide = optionSide
        self.shiftSide = shiftSide
        self.controlSide = controlSide
    }

    var hasAny: Bool {
        command || option || shift || control
    }

    /// Convert to CGEventFlags. The mask is the same regardless of side — at the OS
    /// flag level, Left and Right ⌘ both set `.maskCommand`. Side only affects which
    /// virtualKey the simulator pre-presses (see `virtualKey(forMask:)`).
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if option { flags.insert(.maskAlternate) }
        if shift { flags.insert(.maskShift) }
        if control { flags.insert(.maskControl) }
        return flags
    }

    /// Returns the side-specific virtual keycode for a modifier mask. Defaults to the
    /// Left variant when no side was selected. Returns nil for non-modifier masks.
    func virtualKey(forMask mask: CGEventFlags) -> CGKeyCode? {
        switch mask {
        case .maskCommand:
            return CGKeyCode(commandSide == .right ? kVK_RightCommand : kVK_Command)
        case .maskAlternate:
            return CGKeyCode(optionSide == .right ? kVK_RightOption : kVK_Option)
        case .maskShift:
            return CGKeyCode(shiftSide == .right ? kVK_RightShift : kVK_Shift)
        case .maskControl:
            return CGKeyCode(controlSide == .right ? kVK_RightControl : kVK_Control)
        default:
            return nil
        }
    }

    static let command = ModifierFlags(command: true)
    static let option = ModifierFlags(option: true)
    static let shift = ModifierFlags(shift: true)
    static let control = ModifierFlags(control: true)

    /// "L" / "R" prefix string for modifier display, or empty when no side is set.
    static func label(for side: ModifierSide?) -> String {
        switch side {
        case .left: return "L"
        case .right: return "R"
        case .none: return ""
        }
    }
}
