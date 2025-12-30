import Foundation

/// A complete mapping profile
struct Profile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var isDefault: Bool
    var createdAt: Date
    var modifiedAt: Date

    /// Button mappings (system-wide defaults)
    var buttonMappings: [ControllerButton: KeyMapping]

    /// Chord mappings
    var chordMappings: [ChordMapping]

    /// Joystick settings
    var joystickSettings: JoystickSettings

    /// App-specific overrides: bundleIdentifier -> button mappings
    var appOverrides: [String: [ControllerButton: KeyMapping]]

    init(
        id: UUID = UUID(),
        name: String,
        isDefault: Bool = false,
        buttonMappings: [ControllerButton: KeyMapping] = [:],
        chordMappings: [ChordMapping] = [],
        joystickSettings: JoystickSettings = .default,
        appOverrides: [String: [ControllerButton: KeyMapping]] = [:]
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.buttonMappings = buttonMappings
        self.chordMappings = chordMappings
        self.joystickSettings = joystickSettings
        self.appOverrides = appOverrides
    }

    /// Gets the effective mapping for a button, considering app overrides
    func effectiveMapping(for button: ControllerButton, appBundleId: String?) -> KeyMapping? {
        // Check app-specific override first
        if let bundleId = appBundleId,
           let appMappings = appOverrides[bundleId],
           let mapping = appMappings[button] {
            return mapping
        }

        // Fall back to default mapping
        return buttonMappings[button]
    }

    /// Validates the profile for sanity
    func isValid() -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        return joystickSettings.isValid()
    }

    /// Creates a default profile with sensible mappings
    static func createDefault() -> Profile {
        var mappings: [ControllerButton: KeyMapping] = [:]

        // Face buttons
        mappings[.a] = .key(KeyCodeMapping.return)
        mappings[.b] = .key(KeyCodeMapping.escape)
        mappings[.x] = .key(KeyCodeMapping.space)
        mappings[.y] = .key(KeyCodeMapping.tab)

        // Bumpers as held modifiers
        mappings[.leftBumper] = .holdModifier(.command)
        mappings[.rightBumper] = .holdModifier(.option)

        // Triggers as held modifiers
        mappings[.leftTrigger] = .holdModifier(.shift)
        mappings[.rightTrigger] = .holdModifier(.control)

        // D-pad as arrow keys
        mappings[.dpadUp] = .key(KeyCodeMapping.upArrow)
        mappings[.dpadDown] = .key(KeyCodeMapping.downArrow)
        mappings[.dpadLeft] = .key(KeyCodeMapping.leftArrow)
        mappings[.dpadRight] = .key(KeyCodeMapping.rightArrow)

        // Special buttons
        mappings[.menu] = .combo(KeyCodeMapping.tab, modifiers: .command)  // App switcher
        mappings[.view] = .combo(KeyCodeMapping.upArrow, modifiers: .control)  // Mission Control
        mappings[.xbox] = .key(KeyCodeMapping.f4)  // Launchpad (requires system shortcut)

        // Thumbstick clicks as mouse buttons
        mappings[.leftThumbstick] = .key(KeyCodeMapping.mouseLeftClick)
        mappings[.rightThumbstick] = .key(KeyCodeMapping.mouseRightClick)

        return Profile(
            name: "Default",
            isDefault: true,
            buttonMappings: mappings,
            chordMappings: [],
            joystickSettings: .default
        )
    }
}

// MARK: - Custom Codable for Dictionary with enum keys

extension Profile {
    enum CodingKeys: String, CodingKey {
        case id, name, isDefault, createdAt, modifiedAt
        case buttonMappings, chordMappings, joystickSettings, appOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)

        // Decode button mappings from string-keyed dictionary
        let stringKeyedMappings = try container.decode([String: KeyMapping].self, forKey: .buttonMappings)
        buttonMappings = Dictionary(uniqueKeysWithValues: stringKeyedMappings.compactMap { key, value in
            guard let button = ControllerButton(rawValue: key) else { return nil }
            return (button, value)
        })

        chordMappings = try container.decode([ChordMapping].self, forKey: .chordMappings)
        joystickSettings = try container.decode(JoystickSettings.self, forKey: .joystickSettings)

        // Decode app overrides
        let stringKeyedOverrides = try container.decode([String: [String: KeyMapping]].self, forKey: .appOverrides)
        appOverrides = stringKeyedOverrides.mapValues { stringDict in
            Dictionary(uniqueKeysWithValues: stringDict.compactMap { key, value in
                guard let button = ControllerButton(rawValue: key) else { return nil }
                return (button, value)
            })
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)

        // Encode button mappings as string-keyed dictionary
        let stringKeyedMappings = Dictionary(uniqueKeysWithValues: buttonMappings.map { ($0.key.rawValue, $0.value) })
        try container.encode(stringKeyedMappings, forKey: .buttonMappings)

        try container.encode(chordMappings, forKey: .chordMappings)
        try container.encode(joystickSettings, forKey: .joystickSettings)

        // Encode app overrides
        let stringKeyedOverrides = appOverrides.mapValues { dict in
            Dictionary(uniqueKeysWithValues: dict.map { ($0.key.rawValue, $0.value) })
        }
        try container.encode(stringKeyedOverrides, forKey: .appOverrides)
    }
}
