import Foundation

/// Represents a mapping layer that can be activated by holding a button.
/// When the activator button is held, the layer's buttonMappings override the base layer.
/// Buttons not mapped in the layer fall through to the base layer mapping.
struct Layer: Codable, Identifiable, Equatable {
    var id: UUID

    /// User-defined name for the layer (e.g., "Combat Mode", "Navigation")
    var name: String

    /// The button that activates this layer when held
    var activatorButton: ControllerButton

    /// Layer-specific button mappings (overrides base layer when active)
    var buttonMappings: [ControllerButton: KeyMapping]

    init(
        id: UUID = UUID(),
        name: String,
        activatorButton: ControllerButton,
        buttonMappings: [ControllerButton: KeyMapping] = [:]
    ) {
        self.id = id
        self.name = name
        self.activatorButton = activatorButton
        self.buttonMappings = buttonMappings
    }

    // MARK: - Custom Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, activatorButton, buttonMappings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // id is required for identity
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Layer"
        activatorButton = try container.decodeIfPresent(ControllerButton.self, forKey: .activatorButton) ?? .leftBumper

        // Decode button mappings from string-keyed dictionary (same pattern as Profile)
        let stringKeyedMappings = try container.decodeIfPresent([String: KeyMapping].self, forKey: .buttonMappings) ?? [:]
        buttonMappings = Dictionary(uniqueKeysWithValues: stringKeyedMappings.compactMap { key, value in
            guard let button = ControllerButton(rawValue: key) else { return nil }
            return (button, value)
        })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(activatorButton, forKey: .activatorButton)

        // Encode button mappings as string-keyed dictionary
        let stringKeyedMappings = Dictionary(uniqueKeysWithValues: buttonMappings.map { ($0.key.rawValue, $0.value) })
        try container.encode(stringKeyedMappings, forKey: .buttonMappings)
    }
}
