import Foundation
import CoreGraphics

/// Represents an ordered button sequence mapping (e.g., Down → Down → A)
struct SequenceMapping: Codable, Identifiable, Equatable, ExecutableAction {
    var id: UUID

	/// Authoritative ordered steps. Members of each step are simultaneous.
	var inputSteps: [SequenceStep]
	var usesReleaseSteps: Bool

	/// Legacy press-order API. Assigning it deliberately restores press timing.
	var steps: [ControllerButton] {
		get { inputSteps.flatMap(\.buttons) }
		set { inputSteps = newValue.map { SequenceStep([$0]) }; usesReleaseSteps = false }
	}
	var allButtons: Set<ControllerButton> { Set(inputSteps.flatMap(\.buttons)) }

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

    /// Optional MIDI Control Change message to emit
    var midiControlChange: MIDIControlChange?

    /// Optional user-provided description of what this sequence does
    var hint: String?

    /// Optional haptic feedback style to play when this sequence fires
    var hapticStyle: HapticStyle?

    init(
        id: UUID = UUID(),
        steps: [ControllerButton] = [],
		chordSteps: [SequenceStep]? = nil,
        stepTimeout: TimeInterval = Config.defaultSequenceStepTimeout,
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags(),
        macroId: UUID? = nil,
        scriptId: UUID? = nil,
        systemCommand: SystemCommand? = nil,
		midiControlChange: MIDIControlChange? = nil,
        hint: String? = nil,
        hapticStyle: HapticStyle? = nil
    ) {
        self.id = id
		self.inputSteps = chordSteps ?? steps.map { SequenceStep([$0]) }
		self.usesReleaseSteps = chordSteps != nil
        self.stepTimeout = Self.sanitizedStepTimeout(stepTimeout)
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.macroId = macroId
        self.scriptId = scriptId
        self.systemCommand = systemCommand
		self.midiControlChange = midiControlChange
        self.hint = hint
        self.hapticStyle = hapticStyle
    }

    private enum CodingKeys: String, CodingKey {
		case id, steps, stepFormat, stepTimeout, keyCode, modifiers, macroId, scriptId, systemCommand, midiControlChange, hint, hapticStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(.id, default: UUID())
		let format = try container.decodeIfPresent(Int.self, forKey: .stepFormat) ?? 1
		switch format {
		case 1:
			let legacy = try container.decodeIfPresent([ControllerButton].self, forKey: .steps) ?? []
			inputSteps = legacy.map { SequenceStep([$0]) }
			usesReleaseSteps = false
		case 2:
			inputSteps = try container.decode([SequenceStep].self, forKey: .steps)
			guard (2...Config.maxSequenceSteps).contains(inputSteps.count) else {
				throw DecodingError.dataCorruptedError(forKey: .steps, in: container, debugDescription: "Invalid sequence length")
			}
			usesReleaseSteps = true
		default:
			throw DecodingError.dataCorruptedError(forKey: .stepFormat, in: container, debugDescription: "Unsupported sequence format")
		}
        stepTimeout = Self.sanitizedStepTimeout(try container.decode(.stepTimeout, default: Config.defaultSequenceStepTimeout))
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decode(.modifiers, default: ModifierFlags())
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        scriptId = try container.decodeIfPresent(UUID.self, forKey: .scriptId)
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
		midiControlChange = try container.decodeIfPresent(MIDIControlChange.self, forKey: .midiControlChange)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
        hapticStyle = try container.decodeIfPresent(HapticStyle.self, forKey: .hapticStyle)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
		guard inputSteps.allSatisfy({ $0.validationMessage == nil }),
			usesReleaseSteps || inputSteps.allSatisfy({ $0.buttons.count == 1 }),
			!usesReleaseSteps || (2...Config.maxSequenceSteps).contains(inputSteps.count) else {
			throw EncodingError.invalidValue(inputSteps, .init(codingPath: encoder.codingPath,
				debugDescription: "Invalid sequence steps or timing format"))
		}
		if usesReleaseSteps {
			// Reuse the old key with a different shape: older apps reject this
			// mapping instead of silently flattening a chord into presses.
			try container.encode(2, forKey: .stepFormat)
			try container.encode(inputSteps, forKey: .steps)
		} else {
			try container.encode(steps, forKey: .steps)
		}
        try container.encode(stepTimeout, forKey: .stepTimeout)
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encodeIfPresent(macroId, forKey: .macroId)
        try container.encodeIfPresent(scriptId, forKey: .scriptId)
        try container.encodeIfPresent(systemCommand, forKey: .systemCommand)
		try container.encodeIfPresent(midiControlChange, forKey: .midiControlChange)
        try container.encodeIfPresent(hint, forKey: .hint)
        try container.encodeIfPresent(hapticStyle, forKey: .hapticStyle)
    }

    /// Human-readable description of the sequence steps
    var stepsDisplayString: String {
		inputSteps.map { $0.label { $0.shortLabel } }.joined(separator: " → ")
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
		if let midiControlChange {
			return midiControlChange.displayString
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

    /// Whether this sequence mapping has any action configured
    var hasAction: Bool {
		keyCode != nil || macroId != nil || scriptId != nil || systemCommand != nil
			|| midiControlChange != nil || modifiers.hasAny
    }

    /// Returns a copy with all action fields cleared (steps, timing, and id preserved)
    func clearingAllActions() -> SequenceMapping {
        var copy = self
        copy.keyCode = nil
        copy.modifiers = ModifierFlags()
        copy.macroId = nil
        copy.scriptId = nil
        copy.systemCommand = nil
		copy.midiControlChange = nil
        copy.hint = nil
        copy.hapticStyle = nil
        return copy
    }

    /// Whether this sequence has enough steps to be valid
	var isValid: Bool {
		inputSteps.count >= 2 && inputSteps.allSatisfy { $0.validationMessage == nil }
			&& (usesReleaseSteps ? inputSteps.count <= Config.maxSequenceSteps : inputSteps.allSatisfy { $0.buttons.count == 1 })
	}

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
		if actionType != .midiControlChange { copy.midiControlChange = nil }
        return copy
    }
}
