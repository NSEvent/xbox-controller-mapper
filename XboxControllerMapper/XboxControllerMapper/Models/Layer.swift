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

    /// Per-stick tuning overrides applied when this layer is active.
    /// nil = inherit the profile-level `JoystickSettings.leftStick` / `rightStick`.
    /// A non-nil override only changes the fields it explicitly sets (mode,
    /// sensitivity, acceleration, deadzone, …); unset fields fall through to the
    /// base stick — same transparency model as button mappings.
    var leftStickTuning: StickTuningOverride?
    var rightStickTuning: StickTuningOverride?

    init(
        id: UUID = UUID(),
        name: String,
        activatorButton: ControllerButton? = nil,
        buttonMappings: [ControllerButton: KeyMapping] = [:],
        dualSenseLEDSettings: DualSenseLEDSettings? = nil,
        leftStickTuning: StickTuningOverride? = nil,
        rightStickTuning: StickTuningOverride? = nil
    ) {
        self.id = id
        self.name = name
        self.activatorButton = activatorButton
        self.buttonMappings = buttonMappings
        self.dualSenseLEDSettings = dualSenseLEDSettings
        self.leftStickTuning = leftStickTuning
        self.rightStickTuning = rightStickTuning
    }

    // MARK: - Custom Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, activatorButton, buttonMappings, dualSenseLEDSettings
        case leftStickTuning, rightStickTuning
        // Legacy mode-only overrides (pre per-stick tuning) — migrated on decode,
        // re-encoded for downgrade safety.
        case leftStickModeOverride, rightStickModeOverride
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
        // Prefer the new per-stick tuning override; otherwise migrate the legacy
        // mode-only override into a tuning override carrying just the mode.
        // Lenient: an unknown StickMode raw value (newer build) falls back to nil
        // ("inherit") instead of throwing out the layer.
        leftStickTuning = try container.decodeIfPresent(StickTuningOverride.self, forKey: .leftStickTuning)
            ?? Self.migrateLegacyModeOverride(try container.decodeLenient(.leftStickModeOverride))
        rightStickTuning = try container.decodeIfPresent(StickTuningOverride.self, forKey: .rightStickTuning)
            ?? Self.migrateLegacyModeOverride(try container.decodeLenient(.rightStickModeOverride))
    }

    /// Wraps a legacy mode-only override into a full tuning override (or nil).
    private static func migrateLegacyModeOverride(_ mode: StickMode?) -> StickTuningOverride? {
        guard let mode else { return nil }
        var override = StickTuningOverride()
        override.mode = mode
        return override
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
        try container.encodeIfPresent(leftStickTuning, forKey: .leftStickTuning)
        try container.encodeIfPresent(rightStickTuning, forKey: .rightStickTuning)
        // Downgrade safety: also write the legacy mode-only override so a
        // pre-per-stick build still honors a layer's stick-mode change.
        try container.encodeIfPresent(leftStickTuning?.mode, forKey: .leftStickModeOverride)
        try container.encodeIfPresent(rightStickTuning?.mode, forKey: .rightStickModeOverride)
    }
}
