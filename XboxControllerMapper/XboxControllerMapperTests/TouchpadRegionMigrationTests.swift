import XCTest
@testable import ControllerKeys

/// Covers the v1 → v3 and v2 → v3 migrations that promote
/// `Profile.touchpadRegionMappings` rows (v1) and the four single-case quadrant
/// buttons + trigger map (v2) into the v3 per-trigger first-class buttons
/// (`*Click` and `*Touch` variants).
///
/// The user-facing contract: existing configs MUST NOT lose data on upgrade.
/// `.both`-trigger entries fan out to BOTH the click and touch variants so a
/// dual-action quadrant config survives. Profiles with any quadrant data
/// switch to `.quadrants` mode automatically so those bindings actually fire.
@MainActor
final class TouchpadRegionMigrationTests: XCTestCase {

    // MARK: - v1 single-trigger mappings

    func testMigrate_V1ClickMappingPromotesToClickButton() {
        let profile = profileWith(regionMappings: [
            TouchpadRegionMapping(region: .topLeft, triggerMode: .click,
                                  keyCode: KeyCodeMapping.keyA, modifiers: .command)
        ])

        let (out, didMigrate) = ProfileConfigurationMigrationService
            .migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertTrue(didMigrate)
        let migrated = out[0]
        XCTAssertTrue(migrated.touchpadRegionMappings.isEmpty,
                      "Legacy list must be drained after migration")
        XCTAssertEqual(migrated.touchpadInputMode, .quadrants,
                       "Profile with quadrant data must auto-switch to quadrants mode")
        let clickMapping = migrated.buttonMappings[.touchpadRegionTopLeftClick]
        XCTAssertNotNil(clickMapping, "Click trigger should land in the *Click button case")
        XCTAssertEqual(clickMapping?.keyCode, KeyCodeMapping.keyA)
        XCTAssertTrue(clickMapping?.modifiers.command ?? false)
        XCTAssertNil(migrated.buttonMappings[.touchpadRegionTopLeftTouch],
                     "Touch case stays empty for click-only legacy entries")
    }

    func testMigrate_V1TouchMappingPromotesToTouchButton() {
        let profile = profileWith(regionMappings: [
            TouchpadRegionMapping(region: .topRight, triggerMode: .touch,
                                  keyCode: KeyCodeMapping.tab)
        ])

        let (out, _) = ProfileConfigurationMigrationService
            .migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertEqual(out[0].buttonMappings[.touchpadRegionTopRightTouch]?.keyCode, KeyCodeMapping.tab)
        XCTAssertNil(out[0].buttonMappings[.touchpadRegionTopRightClick])
        XCTAssertEqual(out[0].touchpadInputMode, .quadrants)
    }

    func testMigrate_V1BothMappingFansOutToClickAndTouch() {
        // The whole point of fanning `.both` to both variants: don't lose the
        // user's intent that the action fires on either trigger.
        let profile = profileWith(regionMappings: [
            TouchpadRegionMapping(region: .bottomRight, triggerMode: .both,
                                  keyCode: KeyCodeMapping.escape)
        ])

        let (out, _) = ProfileConfigurationMigrationService
            .migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertEqual(out[0].buttonMappings[.touchpadRegionBottomRightClick]?.keyCode, KeyCodeMapping.escape,
                       ".both must populate the click variant")
        XCTAssertEqual(out[0].buttonMappings[.touchpadRegionBottomRightTouch]?.keyCode, KeyCodeMapping.escape,
                       ".both must populate the touch variant")
    }

    // MARK: - v1 dual touch+click bindings preserved

    func testMigrate_V1DualTouchAndClickPreservesBoth() {
        // Reverses the previous behavior where one would be dropped — with the
        // 8-button design we keep both, each routed to the appropriate variant.
        let profile = profileWith(regionMappings: [
            TouchpadRegionMapping(region: .topLeft, triggerMode: .touch,
                                  keyCode: KeyCodeMapping.keyA),
            TouchpadRegionMapping(region: .topLeft, triggerMode: .click,
                                  keyCode: KeyCodeMapping.keyB)
        ])

        let (out, _) = ProfileConfigurationMigrationService
            .migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertEqual(out[0].buttonMappings[.touchpadRegionTopLeftTouch]?.keyCode, KeyCodeMapping.keyA,
                       "Touch action goes to the *Touch button")
        XCTAssertEqual(out[0].buttonMappings[.touchpadRegionTopLeftClick]?.keyCode, KeyCodeMapping.keyB,
                       "Click action goes to the *Click button — NO data loss")
    }

    // MARK: - Mode auto-switch

    func testMigrate_NoQuadrantDataKeepsWholePadMode() {
        // Profiles that never had quadrant data should stay in whole-pad mode.
        let profile = profileWith(regionMappings: [])

        let (out, didMigrate) = ProfileConfigurationMigrationService
            .migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertFalse(didMigrate)
        XCTAssertEqual(out[0].touchpadInputMode, .wholePad)
    }

    func testMigrate_DoesNotDowngradeAnExplicitlyChosenMode() {
        // If the profile is already in quadrants mode (e.g. user picked it
        // manually before any data exists), don't reset it during migration.
        var profile = profileWith(regionMappings: [])
        profile.touchpadInputMode = .quadrants

        let (out, _) = ProfileConfigurationMigrationService
            .migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertEqual(out[0].touchpadInputMode, .quadrants,
                       "Migration must not flip an already-set quadrants choice back")
    }

    // MARK: - Defensive: existing button mapping not overwritten

    func testMigrate_DoesNotOverwriteExistingClickButtonMapping() {
        var profile = profileWith(regionMappings: [
            TouchpadRegionMapping(region: .topLeft, triggerMode: .click,
                                  keyCode: KeyCodeMapping.keyB)
        ])
        profile.buttonMappings[.touchpadRegionTopLeftClick] = KeyMapping(keyCode: KeyCodeMapping.keyA)

        let (out, _) = ProfileConfigurationMigrationService
            .migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertEqual(out[0].buttonMappings[.touchpadRegionTopLeftClick]?.keyCode, KeyCodeMapping.keyA,
                       "Pre-existing button mapping must not be overwritten by legacy migration")
    }

    // MARK: - Empty mappings ignored

    func testMigrate_EmptyLegacyMappingsAreSkipped() {
        let profile = profileWith(regionMappings: [
            TouchpadRegionMapping(region: .topLeft, triggerMode: .click)
        ])

        let (out, didMigrate) = ProfileConfigurationMigrationService
            .migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertFalse(didMigrate, "Empty legacy mapping shouldn't count as a migration")
        XCTAssertNil(out[0].buttonMappings[.touchpadRegionTopLeftClick])
        XCTAssertNil(out[0].buttonMappings[.touchpadRegionTopLeftTouch])
        XCTAssertEqual(out[0].touchpadInputMode, .wholePad,
                       "No data → no mode flip")
    }

    // MARK: - v2 → v3 key rewrite via decoder

    func testDecode_V2QuadrantKeysWithBothTriggerFanOutToClickAndTouch() throws {
        // Hand-craft a v2-shaped JSON payload — uses the old "touchpadRegionTopLeft"
        // key plus a touchpadRegionTriggerModes map indicating .both.
        let v2JSON = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy v2",
            "isDefault": true,
            "createdAt": "2026-01-01T00:00:00Z",
            "modifiedAt": "2026-01-01T00:00:00Z",
            "buttonMappings": {
                "touchpadRegionTopLeft": { "keyCode": \(KeyCodeMapping.keyA), "modifiers": {"command": true, "option": false, "shift": false, "control": false}, "isHoldModifier": false, "holdRepeatEnabled": false, "holdRepeatInterval": 0.033 }
            },
            "chordMappings": [],
            "sequenceMappings": [],
            "joystickSettings": {},
            "dualSenseLEDSettings": {},
            "linkedApps": [],
            "macros": [],
            "scripts": [],
            "onScreenKeyboardSettings": {},
            "gestureMappings": [],
            "layers": [],
            "touchpadRegionMappings": [],
            "commandWheelActions": [],
            "touchpadRegionTriggerModes": {
                "touchpadRegionTopLeft": "both"
            }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(Profile.self, from: v2JSON.data(using: .utf8)!)

        XCTAssertEqual(profile.buttonMappings[.touchpadRegionTopLeftClick]?.keyCode, KeyCodeMapping.keyA,
                       "v2 .both must rewrite into the click variant")
        XCTAssertEqual(profile.buttonMappings[.touchpadRegionTopLeftTouch]?.keyCode, KeyCodeMapping.keyA,
                       "v2 .both must rewrite into the touch variant")
        XCTAssertNil(profile.buttonMappings.first(where: { $0.key.rawValue == "touchpadRegionTopLeft" })?.value,
                     "v2 raw key shouldn't survive into buttonMappings")
        XCTAssertTrue(profile.touchpadRegionTriggerModes.isEmpty,
                      "Legacy trigger-mode map must be drained on decode")
    }

    // MARK: - Round-trip: encode → decode → migrate → equals

    func testMigrate_EncodedV1ConfigRoundtripsThroughLoadCoordinator() throws {
        let v1Profile = profileWith(regionMappings: [
            TouchpadRegionMapping(region: .topLeft,    triggerMode: .click, keyCode: KeyCodeMapping.keyA),
            TouchpadRegionMapping(region: .bottomLeft, triggerMode: .touch, keyCode: KeyCodeMapping.keyZ)
        ])
        let config = ProfileConfiguration(
            profiles: [v1Profile],
            activeProfileId: v1Profile.id,
            uiScale: nil
        )
        let encoded = try ProfileConfigurationCodec.encode(config)
        let result = try ProfileConfigurationLoadCoordinator.load(data: encoded)

        XCTAssertTrue(result.didMigrate)
        let loaded = result.profiles[0]
        XCTAssertTrue(loaded.touchpadRegionMappings.isEmpty)
        XCTAssertEqual(loaded.touchpadInputMode, .quadrants)
        XCTAssertEqual(loaded.buttonMappings[.touchpadRegionTopLeftClick]?.keyCode, KeyCodeMapping.keyA)
        XCTAssertEqual(loaded.buttonMappings[.touchpadRegionBottomLeftTouch]?.keyCode, KeyCodeMapping.keyZ)
    }

    func testMigrate_PostMigrationReencodeIsStable() throws {
        let v1Profile = profileWith(regionMappings: [
            TouchpadRegionMapping(region: .topRight, triggerMode: .both, keyCode: KeyCodeMapping.escape)
        ])
        let v1Config = ProfileConfiguration(
            profiles: [v1Profile],
            activeProfileId: v1Profile.id,
            uiScale: nil
        )
        let v1Encoded = try ProfileConfigurationCodec.encode(v1Config)
        let v1Loaded = try ProfileConfigurationLoadCoordinator.load(data: v1Encoded)
        let migratedProfile = v1Loaded.profiles[0]

        let v3Config = ProfileConfiguration(
            profiles: [migratedProfile],
            activeProfileId: migratedProfile.id,
            uiScale: nil
        )
        let v3Encoded = try ProfileConfigurationCodec.encode(v3Config)
        let v3Loaded = try ProfileConfigurationLoadCoordinator.load(data: v3Encoded)

        XCTAssertFalse(v3Loaded.didMigrate,
                       "Already-migrated config must not re-migrate (idempotent)")
        XCTAssertEqual(v3Loaded.profiles[0].buttonMappings[.touchpadRegionTopRightClick]?.keyCode,
                       KeyCodeMapping.escape)
        XCTAssertEqual(v3Loaded.profiles[0].buttonMappings[.touchpadRegionTopRightTouch]?.keyCode,
                       KeyCodeMapping.escape)
        XCTAssertEqual(v3Loaded.profiles[0].touchpadInputMode, .quadrants)
    }

    // MARK: - Regression: v3 wholePad with leftover quadrant mappings

    func testMigrate_V3WholePadWithLeftoverQuadrantMappings_PreservesWholePadAcrossReload() throws {
        // Repro for the reopen bug: a user previously bound quadrant buttons,
        // then switched the profile to .wholePad. The quadrant button mappings
        // remain in `buttonMappings` (the UI doesn't auto-purge them). Each
        // reload must preserve the user's .wholePad choice — the migration
        // must NOT silently flip back to .quadrants based on data presence.
        var profile = profileWith(regionMappings: [])
        profile.buttonMappings[.touchpadRegionTopLeftClick] = KeyMapping(keyCode: KeyCodeMapping.keyA)
        profile.touchpadInputMode = .wholePad

        let config = ProfileConfiguration(
            profiles: [profile],
            activeProfileId: profile.id,
            uiScale: nil
        )
        let encoded = try ProfileConfigurationCodec.encode(config)
        let loaded = try ProfileConfigurationLoadCoordinator.load(data: encoded)

        XCTAssertEqual(loaded.profiles[0].touchpadInputMode, .wholePad,
                       "Reload must respect the saved .wholePad choice even when leftover quadrant mappings exist")
        XCTAssertFalse(loaded.didMigrate,
                       "A clean v3 reload must not report a migration")
    }

    // MARK: - Helpers

    private func profileWith(regionMappings: [TouchpadRegionMapping]) -> Profile {
        Profile(
            id: UUID(),
            name: "Test",
            isDefault: true,
            buttonMappings: [:],
            touchpadRegionMappings: regionMappings
        )
    }
}
