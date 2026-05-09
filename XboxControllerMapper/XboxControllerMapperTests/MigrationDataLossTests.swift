import XCTest
import CoreGraphics
@testable import ControllerKeys

/// Pins the "what happens to data we can't migrate" contract for the touchpad
/// region migration. Existing TouchpadRegionMigrationTests cover the happy paths
/// (every region/trigger combo migrates correctly) — this file targets the
/// silent-data-loss edges that those don't pin:
///
///   1. `ControllerButton.from(region:trigger:)` is the migration's lookup
///      table. If a future region case is added without updating `from()`, it
///      returns nil and migration silently drops the entry (line 71 of
///      ProfileConfigurationMigrationService.swift uses `guard let ... else
///      { continue }` with no log on the nil branch).
///   2. `.both` trigger fan-out depends on `from()` returning nil for
///      `(_, .both)` — the migration code expands `.both` into [.click, .touch]
///      *before* calling `from()`. If `from(_, .both)` ever returned non-nil,
///      the fan-out would short-circuit and only one button would be populated.
///   3. Two v1 entries targeting the same button: first one wins, second is
///      logged-but-dropped. Not previously asserted.
///   4. `.both` triggers where one of the two target buttons already has a
///      mapping: only the unconfigured side migrates, the conflicting side is
///      dropped silently (well, NSLog'd) — partial migration risk.
///   5. Modifier-only legacy mappings (no keyCode/macroId/systemCommand but
///      `modifiers.hasAny == true`) get caught by `legacy.isEmpty` and dropped
///      silently. Documented here so it's a deliberate decision, not an
///      accident.
final class MigrationDataLossTests: XCTestCase {

    // MARK: - 1. Lookup-table completeness

    func testControllerButton_from_returnsNonNilForEveryRegionAndConcreteTrigger() {
        // The migration calls `from()` only with .click or .touch (it expands
        // .both upstream). Every region must map for every concrete trigger,
        // or migration silently drops the entry.
        for region in TouchpadRegion.allCases {
            for trigger in [TouchpadTriggerMode.click, .touch] {
                XCTAssertNotNil(
                    ControllerButton.from(region: region, trigger: trigger),
                    "Migration would silently drop (\(region), \(trigger)) — every concrete combo MUST map"
                )
            }
        }
    }

    // MARK: - 2. .both trigger contract

    func testControllerButton_from_returnsNilForBothTrigger() {
        // The migration relies on this. If `from(_, .both)` ever returned a
        // button, the fan-out logic in migrateTouchpadRegionsToButtons would
        // bypass the [click, touch] expansion and only populate one variant.
        for region in TouchpadRegion.allCases {
            XCTAssertNil(
                ControllerButton.from(region: region, trigger: .both),
                ".both must return nil — migration's fan-out depends on this"
            )
        }
    }

    // MARK: - 3. Two v1 entries to same target

    func testMigrate_TwoLegacyEntriesToSameRegionAndTrigger_FirstWins() {
        var profile = Profile(name: "test")
        let firstKey: CGKeyCode = 1
        let secondKey: CGKeyCode = 2
        profile.touchpadRegionMappings = [
            TouchpadRegionMapping(region: .topLeft, triggerMode: .click, keyCode: firstKey),
            TouchpadRegionMapping(region: .topLeft, triggerMode: .click, keyCode: secondKey),
        ]

        let (migrated, didMigrate) = ProfileConfigurationMigrationService.migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertTrue(didMigrate)
        let resolved = migrated[0].buttonMappings[.touchpadRegionTopLeftClick]
        XCTAssertNotNil(resolved, "First entry should have populated the slot")
        XCTAssertEqual(resolved?.keyCode, firstKey,
                       "First entry wins — second is dropped (logged via NSLog by the migration)")
        XCTAssertNotEqual(resolved?.keyCode, secondKey,
                          "Second entry must NOT overwrite the first")
    }

    // MARK: - 4. Partial migration with .both + existing conflict

    func testMigrate_BothTrigger_WithPreExistingClickMapping_OnlyTouchSideMigrates() {
        var profile = Profile(name: "test")
        // User had previously bound the Click variant directly.
        let preExistingKey: CGKeyCode = 99
        profile.buttonMappings[.touchpadRegionTopLeftClick] = KeyMapping(keyCode: preExistingKey)
        // Now a legacy v1 entry tries to migrate to BOTH variants.
        let legacyKey: CGKeyCode = 1
        profile.touchpadRegionMappings = [
            TouchpadRegionMapping(region: .topLeft, triggerMode: .both, keyCode: legacyKey),
        ]

        let (migrated, _) = ProfileConfigurationMigrationService.migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertEqual(migrated[0].buttonMappings[.touchpadRegionTopLeftClick]?.keyCode, preExistingKey,
                       "Pre-existing click mapping must not be overwritten")
        XCTAssertEqual(migrated[0].buttonMappings[.touchpadRegionTopLeftTouch]?.keyCode, legacyKey,
                       "Touch side had no conflict — legacy entry should populate it")
    }

    // MARK: - 5. Modifier-only legacy entries silently dropped

    func testMigrate_ModifierOnlyLegacyEntry_IsSilentlyDropped() {
        // A legacy entry with ONLY modifiers (no keyCode/macroId/systemCommand)
        // is considered `isEmpty` by TouchpadRegionMapping — the migration's
        // `where !legacy.isEmpty` filter drops it without warning. Document
        // this so it's a tracked decision rather than an invisible behavior.
        var profile = Profile(name: "test")
        profile.touchpadRegionMappings = [
            TouchpadRegionMapping(
                region: .topLeft,
                triggerMode: .click,
                keyCode: nil,
                modifiers: ModifierFlags(command: true)
            ),
        ]

        let (migrated, didMigrate) = ProfileConfigurationMigrationService.migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertNil(migrated[0].buttonMappings[.touchpadRegionTopLeftClick],
                     "Modifier-only entries are dropped — TouchpadRegionMapping.isEmpty doesn't count modifiers")
        XCTAssertFalse(didMigrate, "Dropped entries don't count as migration")
    }

    // MARK: - 6. Cleanup invariants

    func testMigrate_LegacyArrayIsClearedAfterSuccessfulMigration() {
        var profile = Profile(name: "test")
        profile.touchpadRegionMappings = [
            TouchpadRegionMapping(region: .topLeft, triggerMode: .click, keyCode: 1),
        ]

        let (migrated, _) = ProfileConfigurationMigrationService.migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertTrue(migrated[0].touchpadRegionMappings.isEmpty,
                      "Stale legacy entries must be cleared so re-encoding doesn't propagate them")
    }

    func testMigrate_LegacyArrayPreservedWhenAllEntriesAreNoOps() {
        // If every legacy entry is empty/skipped, didMigrateThisProfile stays
        // false and we leave the array alone. This is current behavior — pin it
        // so a future change makes the choice deliberately.
        var profile = Profile(name: "test")
        let modifierOnly = TouchpadRegionMapping(
            region: .topLeft,
            triggerMode: .click,
            keyCode: nil,
            modifiers: ModifierFlags(command: true)
        )
        profile.touchpadRegionMappings = [modifierOnly]

        let (migrated, _) = ProfileConfigurationMigrationService.migrateTouchpadRegionsToButtons(in: [profile])

        XCTAssertEqual(migrated[0].touchpadRegionMappings.count, 1,
                       "Legacy array stays when nothing actually migrated — re-running migration sees the same state")
    }

    // MARK: - 7. All-regions sweep

    func testMigrate_AllFourRegionsWithClickAndTouch_PopulateAllEightButtons() {
        var profile = Profile(name: "test")
        for (i, region) in TouchpadRegion.allCases.enumerated() {
            profile.touchpadRegionMappings.append(
                TouchpadRegionMapping(region: region, triggerMode: .both, keyCode: CGKeyCode(i + 1))
            )
        }

        let (migrated, _) = ProfileConfigurationMigrationService.migrateTouchpadRegionsToButtons(in: [profile])

        let expectedButtons: [ControllerButton] = [
            .touchpadRegionTopLeftClick, .touchpadRegionTopLeftTouch,
            .touchpadRegionTopRightClick, .touchpadRegionTopRightTouch,
            .touchpadRegionBottomLeftClick, .touchpadRegionBottomLeftTouch,
            .touchpadRegionBottomRightClick, .touchpadRegionBottomRightTouch,
        ]
        for button in expectedButtons {
            XCTAssertNotNil(migrated[0].buttonMappings[button],
                            "Migration should populate \(button.rawValue)")
        }
        XCTAssertEqual(migrated[0].touchpadInputMode, .quadrants,
                       "Profile with quadrant data must flip to .quadrants mode")
    }
}
