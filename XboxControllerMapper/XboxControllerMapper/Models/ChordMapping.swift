import Foundation
import CoreGraphics

/// Represents a chord (multiple buttons pressed simultaneously) mapping
struct ChordMapping: Codable, Identifiable, Equatable {
    var id: UUID

    /// The buttons that must all be pressed to trigger this chord
    var buttons: Set<ControllerButton>

    /// The key code to simulate when chord is activated
    var keyCode: CGKeyCode?

    /// Modifier flags to apply
    var modifiers: ModifierFlags
    
    /// Optional ID of a macro to execute instead of key press
    var macroId: UUID?

    /// Optional system command to execute instead of key press
    var systemCommand: SystemCommand?

    /// Optional user-provided description of what this chord does
    var hint: String?

    init(
        id: UUID = UUID(),
        buttons: Set<ControllerButton>,
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags(),
        macroId: UUID? = nil,
        systemCommand: SystemCommand? = nil,
        hint: String? = nil
    ) {
        self.id = id
        self.buttons = buttons
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.macroId = macroId
        self.systemCommand = systemCommand
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey {
        case id, buttons, keyCode, modifiers, macroId, systemCommand, hint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        buttons = try container.decodeIfPresent(Set<ControllerButton>.self, forKey: .buttons) ?? []
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        // Sort buttons by rawValue for deterministic JSON output
        try container.encode(buttons.sorted { $0.rawValue < $1.rawValue }, forKey: .buttons)
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encodeIfPresent(macroId, forKey: .macroId)
        try container.encodeIfPresent(systemCommand, forKey: .systemCommand)
        try container.encodeIfPresent(hint, forKey: .hint)
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
            return "Macro" // UI should enhance this with actual name if possible
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
        var conflicted = Set<ControllerButton>()

        for chord in existingChords {
            // Skip the chord being edited
            if chord.id == editingChordId { continue }

            // If selected buttons are a subset of this chord's buttons,
            // the remaining buttons would complete the conflict
            if selectedButtons.isSubset(of: chord.buttons) {
                let remaining = chord.buttons.subtracting(selectedButtons)
                // Only conflict if exactly one button remains
                // (adding that one button would create an exact duplicate)
                if remaining.count == 1 {
                    conflicted.formUnion(remaining)
                }
            }
        }

        return conflicted
    }
}
