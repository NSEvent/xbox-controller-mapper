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

    /// Optional user-provided description of what this chord does
    var hint: String?

    init(
        id: UUID = UUID(),
        buttons: Set<ControllerButton>,
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags(),
        hint: String? = nil
    ) {
        self.id = id
        self.buttons = buttons
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey {
        case id, buttons, keyCode, modifiers, hint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        buttons = try container.decodeIfPresent(Set<ControllerButton>.self, forKey: .buttons) ?? []
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
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
}
