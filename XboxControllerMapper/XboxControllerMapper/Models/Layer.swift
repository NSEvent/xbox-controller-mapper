import Foundation

/// Distinct, visually-different colors auto-assigned to layers in order of creation.
/// Hand-picked for high mutual contrast on a DualSense/DS4 lightbar.
enum LayerColorPalette {
    static let colors: [CodableColor] = [
        CodableColor(red: 0.0, green: 0.55, blue: 1.0),   // Blue
        CodableColor(red: 1.0, green: 0.2, blue: 0.0),    // Red
        CodableColor(red: 0.0, green: 0.85, blue: 0.3),   // Green
        CodableColor(red: 1.0, green: 0.55, blue: 0.0),   // Orange
        CodableColor(red: 0.7, green: 0.2, blue: 0.95),   // Purple
        CodableColor(red: 0.0, green: 0.85, blue: 0.85),  // Cyan
        CodableColor(red: 1.0, green: 0.85, blue: 0.0),   // Yellow
        CodableColor(red: 1.0, green: 0.3, blue: 0.7),    // Pink
        CodableColor(red: 0.4, green: 1.0, blue: 0.4),    // Light green
        CodableColor(red: 0.5, green: 0.5, blue: 1.0),    // Periwinkle
        CodableColor(red: 1.0, green: 0.4, blue: 0.3),    // Coral
        CodableColor(red: 0.0, green: 0.5, blue: 0.4),    // Teal
    ]

    /// Returns the next palette color not already used by an existing layer's LED settings.
    /// Falls back to cycling through the palette if all colors are taken.
    static func nextColor(usedBy layers: [Layer]) -> CodableColor {
        let usedColors = layers.compactMap { $0.dualSenseLEDSettings?.lightBarColor }
        for color in colors {
            if !usedColors.contains(where: { $0.red == color.red && $0.green == color.green && $0.blue == color.blue }) {
                return color
            }
        }
        // All palette colors are taken — cycle by index
        return colors[layers.count % colors.count]
    }
}

/// Represents a mapping layer that can be activated by holding a button.
/// When the activator button is held, the layer's buttonMappings override the base layer.
/// Buttons not mapped in the layer fall through to the base layer mapping.
struct Layer: Codable, Identifiable, Equatable {
    var id: UUID

    /// User-defined name for the layer (e.g., "Combat Mode", "Navigation")
    var name: String

    /// The button that activates this layer when held (nil = layer exists but has no activator assigned)
    var activatorButton: ControllerButton?

    /// Layer-specific button mappings (overrides base layer when active)
    var buttonMappings: [ControllerButton: KeyMapping]

    /// Optional LED settings applied when this layer is active (nil = inherit profile settings)
    var dualSenseLEDSettings: DualSenseLEDSettings?

    init(
        id: UUID = UUID(),
        name: String,
        activatorButton: ControllerButton? = nil,
        buttonMappings: [ControllerButton: KeyMapping] = [:],
        dualSenseLEDSettings: DualSenseLEDSettings? = nil
    ) {
        self.id = id
        self.name = name
        self.activatorButton = activatorButton
        self.buttonMappings = buttonMappings
        self.dualSenseLEDSettings = dualSenseLEDSettings
    }

    // MARK: - Custom Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, activatorButton, buttonMappings, dualSenseLEDSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // id is required for identity
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(.name, default: "Layer")
        activatorButton = try container.decodeIfPresent(ControllerButton.self, forKey: .activatorButton)

        // Decode button mappings from string-keyed dictionary (same pattern as Profile)
        let stringKeyedMappings: [String: KeyMapping] = try container.decode(.buttonMappings, default: [:])
        buttonMappings = Dictionary(uniqueKeysWithValues: stringKeyedMappings.compactMap { key, value in
            guard let button = ControllerButton(rawValue: key) else { return nil }
            return (button, value)
        })

        dualSenseLEDSettings = try container.decodeIfPresent(DualSenseLEDSettings.self, forKey: .dualSenseLEDSettings)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(activatorButton, forKey: .activatorButton)

        // Encode button mappings as string-keyed dictionary
        let stringKeyedMappings = Dictionary(uniqueKeysWithValues: buttonMappings.map { ($0.key.rawValue, $0.value) })
        try container.encode(stringKeyedMappings, forKey: .buttonMappings)

        try container.encodeIfPresent(dualSenseLEDSettings, forKey: .dualSenseLEDSettings)
    }
}
