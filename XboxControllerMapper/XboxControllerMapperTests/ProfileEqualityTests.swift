import XCTest
@testable import ControllerKeys

@MainActor
final class ProfileEqualityTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a profile with known values for all content properties.
    private func makeProfile(
        id: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        name: String = "Test",
        isDefault: Bool = false,
        icon: String? = "star.fill",
        buttonMappings: [ControllerButton: KeyMapping] = [.a: .key(36)],
        chordMappings: [ChordMapping] = [],
        sequenceMappings: [SequenceMapping] = [],
        joystickSettings: JoystickSettings = .default,
        dualSenseLEDSettings: DualSenseLEDSettings = .default,
        linkedApps: [String] = [],
        macros: [Macro] = [],
        scripts: [Script] = [],
        onScreenKeyboardSettings: OnScreenKeyboardSettings = OnScreenKeyboardSettings(),
        layers: [Layer] = []
    ) -> Profile {
        var p = Profile(
            id: id,
            name: name,
            isDefault: isDefault,
            icon: icon,
            buttonMappings: buttonMappings,
            chordMappings: chordMappings,
            sequenceMappings: sequenceMappings,
            joystickSettings: joystickSettings,
            dualSenseLEDSettings: dualSenseLEDSettings,
            linkedApps: linkedApps,
            macros: macros,
            scripts: scripts,
            onScreenKeyboardSettings: onScreenKeyboardSettings,
            layers: layers
        )
        return p
    }

    // MARK: - Timestamp exclusion tests

    func testProfilesWithDifferentTimestampsAreEqual() {
        var a = makeProfile()
        var b = makeProfile()

        // Force different timestamps
        a.createdAt = Date(timeIntervalSince1970: 1000)
        a.modifiedAt = Date(timeIntervalSince1970: 2000)
        b.createdAt = Date(timeIntervalSince1970: 3000)
        b.modifiedAt = Date(timeIntervalSince1970: 4000)

        XCTAssertEqual(a, b, "Profiles with identical content but different timestamps should be equal")
    }

    func testProfilesWithDifferentCreatedAtOnly() {
        var a = makeProfile()
        var b = makeProfile()

        a.createdAt = Date.distantPast
        b.createdAt = Date.distantFuture

        XCTAssertEqual(a, b, "Different createdAt alone should not make profiles unequal")
    }

    func testProfilesWithDifferentModifiedAtOnly() {
        var a = makeProfile()
        var b = makeProfile()

        a.modifiedAt = Date.distantPast
        b.modifiedAt = Date.distantFuture

        XCTAssertEqual(a, b, "Different modifiedAt alone should not make profiles unequal")
    }

    // MARK: - Content difference tests (should NOT be equal)

    func testProfilesWithDifferentIDsAreNotEqual() {
        let a = makeProfile(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
        let b = makeProfile(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentNamesAreNotEqual() {
        let a = makeProfile(name: "Alpha")
        let b = makeProfile(name: "Beta")
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentIsDefaultAreNotEqual() {
        let a = makeProfile(isDefault: true)
        let b = makeProfile(isDefault: false)
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentIconsAreNotEqual() {
        let a = makeProfile(icon: "star.fill")
        let b = makeProfile(icon: "heart.fill")
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentButtonMappingsAreNotEqual() {
        let a = makeProfile(buttonMappings: [.a: .key(36)])
        let b = makeProfile(buttonMappings: [.b: .key(36)])
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentChordMappingsAreNotEqual() {
        let chord = ChordMapping(buttons: [.a, .b], keyCode: 36, modifiers: ModifierFlags())
        let a = makeProfile(chordMappings: [chord])
        let b = makeProfile(chordMappings: [])
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentSequenceMappingsAreNotEqual() {
        let seq = SequenceMapping(steps: [.a, .b], keyCode: 36)
        let a = makeProfile(sequenceMappings: [seq])
        let b = makeProfile(sequenceMappings: [])
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentJoystickSettingsAreNotEqual() {
        var js = JoystickSettings.default
        js.mouseSensitivity = 1.0
        let a = makeProfile(joystickSettings: js)
        let b = makeProfile(joystickSettings: .default)
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentDualSenseLEDSettingsAreNotEqual() {
        var led = DualSenseLEDSettings.default
        led.lightBarEnabled = false
        let a = makeProfile(dualSenseLEDSettings: led)
        let b = makeProfile(dualSenseLEDSettings: .default)
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentLinkedAppsAreNotEqual() {
        let a = makeProfile(linkedApps: ["com.example.app"])
        let b = makeProfile(linkedApps: [])
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentMacrosAreNotEqual() {
        let macro = Macro(name: "test", steps: [])
        let a = makeProfile(macros: [macro])
        let b = makeProfile(macros: [])
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentScriptsAreNotEqual() {
        let script = Script(name: "test", source: "return 1;")
        let a = makeProfile(scripts: [script])
        let b = makeProfile(scripts: [])
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentOnScreenKeyboardSettingsAreNotEqual() {
        var osk = OnScreenKeyboardSettings()
        osk.defaultTerminalApp = "iTerm"
        let a = makeProfile(onScreenKeyboardSettings: osk)
        let b = makeProfile(onScreenKeyboardSettings: OnScreenKeyboardSettings())
        XCTAssertNotEqual(a, b)
    }

    func testProfilesWithDifferentLayersAreNotEqual() {
        let layer = Layer(name: "Layer 1", activatorButton: .leftBumper)
        let a = makeProfile(layers: [layer])
        let b = makeProfile(layers: [])
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Identity test

    func testIdenticalProfilesAreEqual() {
        let a = makeProfile()
        let b = makeProfile()
        XCTAssertEqual(a, b)
    }
}
