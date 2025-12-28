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

    init(
        id: UUID = UUID(),
        buttons: Set<ControllerButton>,
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags()
    ) {
        self.id = id
        self.buttons = buttons
        self.keyCode = keyCode
        self.modifiers = modifiers
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

    /// Whether this chord has a valid configuration
    var isValid: Bool {
        buttons.count >= 2 && (keyCode != nil || modifiers.hasAny)
    }
}
