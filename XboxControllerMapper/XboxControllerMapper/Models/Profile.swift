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

    init(
        id: UUID = UUID(),
        name: String,
        isDefault: Bool = false,
        buttonMappings: [ControllerButton: KeyMapping] = [:],
        chordMappings: [ChordMapping] = [],
        joystickSettings: JoystickSettings = .default
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.buttonMappings = buttonMappings
        self.chordMappings = chordMappings
        self.joystickSettings = joystickSettings
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
        // A = Mouse left click (hold modifier style)
        mappings[.a] = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true)

        // B = Return, long hold = Cmd+Return
        mappings[.b] = KeyMapping(
            keyCode: KeyCodeMapping.return,
            longHoldMapping: LongHoldMapping(keyCode: KeyCodeMapping.return, modifiers: .command, threshold: 0.5)
        )

        // X = Delete with repeat
        mappings[.x] = KeyMapping(
            keyCode: KeyCodeMapping.delete,
            repeatMapping: RepeatMapping(enabled: true, interval: 0.05)
        )

        // Y = Escape
        mappings[.y] = .key(KeyCodeMapping.escape)

        // Bumpers as held modifiers
        // LB = Option (hold), double-tap = Cmd+Opt+Ctrl+Period
        mappings[.leftBumper] = KeyMapping(
            modifiers: .option,
            doubleTapMapping: DoubleTapMapping(
                keyCode: KeyCodeMapping.period,
                modifiers: ModifierFlags(command: true, option: true, shift: false, control: true),
                threshold: 0.4
            ),
            isHoldModifier: true
        )

        // RB = Control (hold)
        mappings[.rightBumper] = .holdModifier(.control)

        // Triggers
        // LT = F13 (brightness key)
        mappings[.leftTrigger] = .key(105)

        // RT = Command (hold)
        mappings[.rightTrigger] = .holdModifier(.command)

        // D-pad as arrow keys with repeat
        mappings[.dpadUp] = KeyMapping(
            keyCode: KeyCodeMapping.upArrow,
            repeatMapping: RepeatMapping(enabled: true, interval: 0.05)
        )
        mappings[.dpadDown] = KeyMapping(
            keyCode: KeyCodeMapping.downArrow,
            repeatMapping: RepeatMapping(enabled: true, interval: 0.05)
        )
        mappings[.dpadLeft] = KeyMapping(
            keyCode: KeyCodeMapping.leftArrow,
            repeatMapping: RepeatMapping(enabled: true, interval: 0.05)
        )
        mappings[.dpadRight] = KeyMapping(
            keyCode: KeyCodeMapping.rightArrow,
            repeatMapping: RepeatMapping(enabled: true, interval: 0.05)
        )

        // Special buttons
        // Menu = Cmd+V, double-tap = Shift+Cmd+V, long hold = Cmd+L
        mappings[.menu] = KeyMapping(
            keyCode: KeyCodeMapping.keyV,
            modifiers: .command,
            longHoldMapping: LongHoldMapping(keyCode: KeyCodeMapping.keyL, modifiers: .command, threshold: 0.2),
            doubleTapMapping: DoubleTapMapping(
                keyCode: KeyCodeMapping.keyV,
                modifiers: ModifierFlags(command: true, option: false, shift: true, control: false),
                threshold: 0.4
            )
        )

        // View = Cmd+C, double-tap = Cmd+A
        mappings[.view] = KeyMapping(
            keyCode: KeyCodeMapping.keyC,
            modifiers: .command,
            doubleTapMapping: DoubleTapMapping(keyCode: KeyCodeMapping.keyA, modifiers: .command, threshold: 0.4)
        )

        // Xbox = Space
        mappings[.xbox] = .key(KeyCodeMapping.space)

        // Share = Cmd+Opt (hold)
        mappings[.share] = KeyMapping(
            modifiers: ModifierFlags(command: true, option: true, shift: false, control: false),
            isHoldModifier: true
        )

        // Thumbstick clicks
        // Left stick = Option+A, long hold = Cmd+Tab
        mappings[.leftThumbstick] = KeyMapping(
            keyCode: KeyCodeMapping.keyA,
            modifiers: .option,
            longHoldMapping: LongHoldMapping(keyCode: KeyCodeMapping.tab, modifiers: .command, threshold: 0.5)
        )

        // Right stick = Ctrl+C, double-tap = Cmd+W
        mappings[.rightThumbstick] = KeyMapping(
            keyCode: KeyCodeMapping.keyC,
            modifiers: .control,
            doubleTapMapping: DoubleTapMapping(keyCode: KeyCodeMapping.keyW, modifiers: .command, threshold: 0.4)
        )

        // DualSense touchpad click = Mouse left click (hold modifier style)
        mappings[.touchpadButton] = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true)

        // Chord mappings
        let chords: [ChordMapping] = [
            // RB + X = Cmd+Delete
            ChordMapping(buttons: [.rightBumper, .x], keyCode: KeyCodeMapping.delete, modifiers: .command),
            // LB + View = Cmd+Minus
            ChordMapping(buttons: [.leftBumper, .view], keyCode: KeyCodeMapping.minus, modifiers: .command),
            // RB + View = Cmd+Equal
            ChordMapping(buttons: [.rightBumper, .view], keyCode: KeyCodeMapping.equal, modifiers: .command),
            // Menu + RB = Cmd+Equal
            ChordMapping(buttons: [.menu, .rightBumper], keyCode: KeyCodeMapping.equal, modifiers: .command),
            // RB + D-Right = Ctrl+E
            ChordMapping(buttons: [.rightBumper, .dpadRight], keyCode: KeyCodeMapping.keyE, modifiers: .control),
            // RB + D-Left = Ctrl+A
            ChordMapping(buttons: [.rightBumper, .dpadLeft], keyCode: KeyCodeMapping.keyA, modifiers: .control),
        ]

        // Joystick settings tuned for comfortable use
        let joystick = JoystickSettings(
            mouseSensitivity: 0.5,
            scrollSensitivity: 0.5,
            mouseDeadzone: 0.15,
            scrollDeadzone: 0.15,
            invertMouseY: false,
            invertScrollY: false,
            mouseAcceleration: 0.5,
            scrollAcceleration: 0.5,
            scrollBoostMultiplier: 4.0,
            focusModeSensitivity: 0.1,
            focusModeModifier: .command
        )

        return Profile(
            name: "Default",
            isDefault: true,
            buttonMappings: mappings,
            chordMappings: chords,
            joystickSettings: joystick
        )
    }
}

// MARK: - Custom Codable for Dictionary with enum keys

extension Profile {
    enum CodingKeys: String, CodingKey {
        case id, name, isDefault, createdAt, modifiedAt
        case buttonMappings, chordMappings, joystickSettings
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
    }
}
