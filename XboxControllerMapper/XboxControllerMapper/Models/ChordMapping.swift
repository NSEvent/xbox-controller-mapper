import Foundation
import CoreGraphics

/// Represents a chord (multiple buttons pressed simultaneously) mapping
struct ChordMapping: Codable, Identifiable, Equatable, ExecutableAction {
    var id: UUID

    /// The buttons that must all be pressed to trigger this chord
    var buttons: Set<ControllerButton>

    /// The key code to simulate when chord is activated
    var keyCode: CGKeyCode?

    /// Modifier flags to apply
    var modifiers: ModifierFlags
    
    /// Optional ID of a macro to execute instead of key press
    var macroId: UUID?

    /// Optional ID of a script to execute instead of key press
    var scriptId: UUID?

    /// Optional system command to execute instead of key press
    var systemCommand: SystemCommand?

    /// Optional user-provided description of what this chord does
    var hint: String?

    /// Optional haptic feedback style to play when this chord fires
    var hapticStyle: HapticStyle?

    init(
        id: UUID = UUID(),
        buttons: Set<ControllerButton>,
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags(),
        macroId: UUID? = nil,
        scriptId: UUID? = nil,
        systemCommand: SystemCommand? = nil,
        hint: String? = nil,
        hapticStyle: HapticStyle? = nil
    ) {
        self.id = id
        self.buttons = buttons
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.macroId = macroId
        self.scriptId = scriptId
        self.systemCommand = systemCommand
        self.hint = hint
        self.hapticStyle = hapticStyle
    }

    private enum CodingKeys: String, CodingKey {
        case id, buttons, keyCode, modifiers, macroId, scriptId, systemCommand, hint, hapticStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        buttons = try container.decodeIfPresent(Set<ControllerButton>.self, forKey: .buttons) ?? []
        if buttons.count < 2 {
            NSLog("[ChordMapping] Warning: chord %@ has %d button(s) — a chord requires at least 2", id.uuidString, buttons.count)
        }
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        scriptId = try container.decodeIfPresent(UUID.self, forKey: .scriptId)
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
        hapticStyle = try container.decodeIfPresent(HapticStyle.self, forKey: .hapticStyle)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        // Sort buttons by rawValue for deterministic JSON output
        try container.encode(buttons.sorted { $0.rawValue < $1.rawValue }, forKey: .buttons)
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encodeIfPresent(macroId, forKey: .macroId)
        try container.encodeIfPresent(scriptId, forKey: .scriptId)
        try container.encodeIfPresent(systemCommand, forKey: .systemCommand)
        try container.encodeIfPresent(hint, forKey: .hint)
        try container.encodeIfPresent(hapticStyle, forKey: .hapticStyle)
    }

    /// Human-readable description of the chord trigger
    var buttonsDisplayString: String {
        buttons
            .sorted { $0.rawValue < $1.rawValue }
            .map { $0.shortLabel }
            .joined(separator: " + ")
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

        if modifiers.command { parts.append("⌘") }
        if modifiers.option { parts.append("⌥") }
        if modifiers.shift { parts.append("⇧") }
        if modifiers.control { parts.append("⌃") }

        if let keyCode = keyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        }

        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    /// ExecutableAction protocol conformance
    var displayString: String { actionDisplayString }

    /// A chord is valid only if it has at least 2 buttons (otherwise it's just a regular button press).
    var isValid: Bool { buttons.count >= 2 }

    // MARK: - Action Conflict Resolution

    /// Returns a copy with all action fields cleared except the specified type.
    func clearingConflicts(keeping actionType: ActionType) -> ChordMapping {
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

    // MARK: - Chord Conflict Detection

    /// Returns the set of buttons that would create a duplicate chord if selected.
    ///
    /// A button is "conflicted" if adding it to the current selection would exactly match
    /// an existing chord's button combination.
    ///
    /// - Parameters:
    ///   - selectedButtons: The currently selected buttons in the chord editor
    ///   - existingChords: All chord mappings in the current profile
    ///   - editingChordId: If editing an existing chord, its ID (to exclude from conflict check)
    /// - Returns: Set of buttons that should be grayed out / disabled
    static func conflictedButtons(
        selectedButtons: Set<ControllerButton>,
        existingChords: [ChordMapping],
        editingChordId: UUID? = nil
    ) -> Set<ControllerButton> {
        Set(conflictedButtonsWithChords(
            selectedButtons: selectedButtons,
            existingChords: existingChords,
            editingChordId: editingChordId
        ).keys)
    }

    /// Returns a mapping of conflicted buttons to the chord that would be duplicated.
    ///
    /// A button is "conflicted" if adding it to the current selection would exactly match
    /// an existing chord's button combination.
    ///
    /// - Parameters:
    ///   - selectedButtons: The currently selected buttons in the chord editor
    ///   - existingChords: All chord mappings in the current profile
    ///   - editingChordId: If editing an existing chord, its ID (to exclude from conflict check)
    /// - Returns: Dictionary mapping each conflicted button to the chord it would duplicate
    static func conflictedButtonsWithChords(
        selectedButtons: Set<ControllerButton>,
        existingChords: [ChordMapping],
        editingChordId: UUID? = nil
    ) -> [ControllerButton: ChordMapping] {
        var conflicts: [ControllerButton: ChordMapping] = [:]

        for chord in existingChords {
            // Skip the chord being edited
            if chord.id == editingChordId { continue }

            // If selected buttons are a subset of this chord's buttons,
            // the remaining buttons would complete the conflict
            if selectedButtons.isSubset(of: chord.buttons) {
                let remaining = chord.buttons.subtracting(selectedButtons)
                // Only conflict if exactly one button remains
                // (adding that one button would create an exact duplicate)
                if remaining.count == 1, let button = remaining.first {
                    conflicts[button] = chord
                }
            }
        }

        return conflicts
    }
}
