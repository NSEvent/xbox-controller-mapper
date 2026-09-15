import XCTest
@testable import ControllerKeys

/// Covers the d-pad preset repeat-seed fix (Discord #support 2026-07-30:
/// configuring the 4th arrow appeared to flip all four to hold-while-held).
/// Presets no longer seed repeat-while-held enabled, an explicitly enabled
/// repeat opts a preset direction out of the forced hold path, and legacy
/// profiles still carrying the untouched 20 Hz seed are migrated off it on
/// decode so upgraders keep held-diagonal movement.
final class DPadPresetRepeatMigrationTests: XCTestCase {

    private static let legacySeed = RepeatMapping(enabled: true, interval: 0.05)

    private func roundTrip(_ profile: Profile) throws -> Profile {
        let data = try JSONEncoder().encode(profile)
        return try JSONDecoder().decode(Profile.self, from: data)
    }

    // MARK: Seeds

    func testDPadPresetApplySeedsRepeatDisabled() {
        var mappings: [ControllerButton: KeyMapping] = [:]
        DPadPreset.arrows.apply(to: &mappings)

        for button in DPadPreset.buttons {
            XCTAssertEqual(mappings[button]?.repeatMapping?.enabled, false,
                           "preset seed for \(button) should not enable repeat")
        }
    }

    func testCreateDefaultSeedsDPadRepeatDisabled() {
        let profile = Profile.createDefault()

        XCTAssertEqual(profile.dpadPreset, .arrows)
        for button in DPadPreset.buttons {
            XCTAssertEqual(profile.buttonMappings[button]?.repeatMapping?.enabled, false,
                           "default profile seed for \(button) should not enable repeat")
        }
    }

    // MARK: Decode migration

    func testDecodeMigratesUntouchedLegacySeedsOff() throws {
        var mappings: [ControllerButton: KeyMapping] = [:]
        DPadPreset.arrows.apply(to: &mappings)
        for button in DPadPreset.buttons {
            mappings[button]?.repeatMapping = Self.legacySeed
        }
        let legacy = Profile(name: "Legacy Arrows", buttonMappings: mappings, dpadPreset: .arrows)

        let decoded = try roundTrip(legacy)

        XCTAssertEqual(decoded.dpadPreset, .arrows)
        for button in DPadPreset.buttons {
            XCTAssertEqual(decoded.buttonMappings[button]?.repeatMapping?.enabled, false,
                           "untouched legacy seed on \(button) should migrate off")
        }
    }

    func testDecodePreservesUserAuthoredRepeatConfig() throws {
        var mappings: [ControllerButton: KeyMapping] = [:]
        DPadPreset.arrows.apply(to: &mappings)
        // Interval differs from the legacy seed, so this is user-authored.
        mappings[.dpadUp]?.repeatMapping = RepeatMapping(enabled: true, interval: 0.2)
        let profile = Profile(name: "User Repeat", buttonMappings: mappings, dpadPreset: .arrows)

        let decoded = try roundTrip(profile)

        XCTAssertEqual(decoded.buttonMappings[.dpadUp]?.repeatMapping?.enabled, true)
        XCTAssertEqual(decoded.buttonMappings[.dpadUp]?.repeatMapping?.interval ?? 0, 0.2, accuracy: 0.0001)
    }

    func testDecodeLeavesCustomPresetRepeatAlone() throws {
        // Manually configured four-arrow d-pad (stays .custom per 38bf0a6):
        // the migration must not touch its repeat config even though the key
        // shape and seed values match the arrows preset exactly.
        var mappings: [ControllerButton: KeyMapping] = [:]
        for (button, keyCode) in [
            (ControllerButton.dpadUp, KeyCodeMapping.upArrow),
            (.dpadDown, KeyCodeMapping.downArrow),
            (.dpadLeft, KeyCodeMapping.leftArrow),
            (.dpadRight, KeyCodeMapping.rightArrow)
        ] {
            mappings[button] = KeyMapping(keyCode: keyCode, repeatMapping: Self.legacySeed)
        }
        let profile = Profile(name: "Custom Repeat", buttonMappings: mappings, dpadPreset: .custom)

        let decoded = try roundTrip(profile)

        XCTAssertEqual(decoded.dpadPreset, .custom)
        for button in DPadPreset.buttons {
            XCTAssertEqual(decoded.buttonMappings[button]?.repeatMapping?.enabled, true,
                           "custom-preset repeat config on \(button) must survive decode")
        }
    }
}
