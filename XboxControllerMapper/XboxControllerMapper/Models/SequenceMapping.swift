import Foundation
import CoreGraphics

/// Represents an ordered button sequence mapping (e.g., Down → Down → A)
struct SequenceMapping: Codable, Identifiable, Equatable, ExecutableAction {
    var id: UUID

    /// The ordered list of buttons that must be pressed in sequence
    var steps: [ControllerButton]

    /// Maximum time allowed between consecutive button presses (seconds)
    var stepTimeout: TimeInterval

    private static func sanitizedStepTimeout(_ stepTimeout: TimeInterval) -> TimeInterval {
        guard stepTimeout.isFinite, stepTimeout > 0 else { return Config.defaultSequenceStepTimeout }
        return stepTimeout
    }

    /// The key code to simulate when sequence is completed
    var keyCode: CGKeyCode?

    /// Modifier flags to apply
    var modifiers: ModifierFlags

    /// Optional ID of a macro to execute instead of key press
    var macroId: UUID?

    /// Optional ID of a script to execute instead of key press
    var scriptId: UUID?

    /// Optional system command to execute instead of key press
    var systemCommand: SystemCommand?

    /// Optional user-provided description of what this sequence does
    var hint: String?

    init(
        id: UUID = UUID(),
        steps: [ControllerButton] = [],
        stepTimeout: TimeInterval = Config.defaultSequenceStepTimeout,
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags(),
        macroId: UUID? = nil,
        scriptId: UUID? = nil,
        systemCommand: SystemCommand? = nil,
        hint: String? = nil
    ) {
        self.id = id
        self.steps = steps
        self.stepTimeout = Self.sanitizedStepTimeout(stepTimeout)
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.macroId = macroId
        self.scriptId = scriptId
        self.systemCommand = systemCommand
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey {
        case id, steps, stepTimeout, keyCode, modifiers, macroId, scriptId, systemCommand, hint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        steps = try container.decodeIfPresent([ControllerButton].self, forKey: .steps) ?? []
        let decodedStepTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .stepTimeout) ?? Config.defaultSequenceStepTimeout
        stepTimeout = Self.sanitizedStepTimeout(decodedStepTimeout)
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        scriptId = try container.decodeIfPresent(UUID.self, forKey: .scriptId)
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(steps, forKey: .steps)
        try container.encode(stepTimeout, forKey: .stepTimeout)
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encodeIfPresent(macroId, forKey: .macroId)
        try container.encodeIfPresent(scriptId, forKey: .scriptId)
        try container.encodeIfPresent(systemCommand, forKey: .systemCommand)
        try container.encodeIfPresent(hint, forKey: .hint)
    }

    /// Human-readable description of the sequence steps
    var stepsDisplayString: String {
        steps.map { $0.shortLabel }.joined(separator: " \u{2192} ")
    }

    /// Human-readable description of the mapping action
    var actionDisplayString: String {
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

        if modifiers.command { parts.append("\u{2318}") }
        if modifiers.option { parts.append("\u{2325}") }
        if modifiers.shift { parts.append("\u{21E7}") }
        if modifiers.control { parts.append("\u{2303}") }

        if let keyCode = keyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        }

        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    /// ExecutableAction protocol conformance
    var displayString: String { actionDisplayString }

    /// Whether this sequence has enough steps to be valid
    var isValid: Bool { steps.count >= 2 }

    // MARK: - Action Conflict Resolution

    /// Returns a copy with all action fields cleared except the specified type.
    func clearingConflicts(keeping actionType: ActionType) -> SequenceMapping {
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
