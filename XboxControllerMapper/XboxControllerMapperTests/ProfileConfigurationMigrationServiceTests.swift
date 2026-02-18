import XCTest
@testable import ControllerKeys

final class ProfileConfigurationMigrationServiceTests: XCTestCase {
    func testMigrateTouchpadSettingsMigratesLegacySensitivityAndAccelerationPreset() {
        var legacySettings = JoystickSettings.default
        legacySettings.touchpadSensitivity = 0.8
        legacySettings.touchpadAcceleration = 0.9
        legacySettings.touchpadDeadzone = 0.0
        legacySettings.touchpadSmoothing = 0.4

        let profile = Profile(name: "Legacy", joystickSettings: legacySettings)
        let (profiles, didMigrate) = ProfileConfigurationMigrationService
            .migrateTouchpadSettingsIfNeeded(in: [profile])

        XCTAssertTrue(didMigrate)
        XCTAssertEqual(profiles[0].joystickSettings.touchpadSensitivity, 0.5)
        XCTAssertEqual(profiles[0].joystickSettings.touchpadAcceleration, 0.5)
    }

    func testMigrateTouchpadSettingsMigratesLegacyDeadzonePreset() {
        var legacySettings = JoystickSettings.default
        legacySettings.touchpadSensitivity = 0.5
        legacySettings.touchpadAcceleration = 0.5
        legacySettings.touchpadDeadzone = 0.01
        legacySettings.touchpadSmoothing = 0.4

        let profile = Profile(name: "Legacy Deadzone", joystickSettings: legacySettings)
        let (profiles, didMigrate) = ProfileConfigurationMigrationService
            .migrateTouchpadSettingsIfNeeded(in: [profile])

        XCTAssertTrue(didMigrate)
        XCTAssertEqual(profiles[0].joystickSettings.touchpadDeadzone, 0.0)
    }

    func testMigrateTouchpadSettingsLeavesNonLegacySettingsUntouched() {
        var settings = JoystickSettings.default
        settings.touchpadSensitivity = 0.62
        settings.touchpadAcceleration = 0.47
        settings.touchpadDeadzone = 0.001

        let profile = Profile(name: "Current", joystickSettings: settings)
        let (profiles, didMigrate) = ProfileConfigurationMigrationService
            .migrateTouchpadSettingsIfNeeded(in: [profile])

        XCTAssertFalse(didMigrate)
        XCTAssertEqual(profiles[0].joystickSettings, settings)
    }

    func testMigrateLegacyKeyboardSettingsOnlyAppliesToProfilesWithoutCustomKeyboardState() {
        let targetProfileId = UUID()
        var emptyKeyboardProfile = Profile(id: targetProfileId, name: "Empty")
        emptyKeyboardProfile.onScreenKeyboardSettings = OnScreenKeyboardSettings(
            quickTexts: [],
            toggleShortcutKeyCode: nil
        )

        var customizedProfile = Profile(id: UUID(), name: "Custom")
        customizedProfile.onScreenKeyboardSettings = OnScreenKeyboardSettings(
            quickTexts: [QuickText(text: "keep")],
            toggleShortcutKeyCode: nil
        )

        let legacySettings = OnScreenKeyboardSettings(
            quickTexts: [QuickText(text: "legacy")],
            defaultTerminalApp: "Warp",
            typingDelay: 0.09,
            appBarItems: [],
            websiteLinks: [],
            showExtendedFunctionKeys: true,
            toggleShortcutKeyCode: 40,
            toggleShortcutModifiers: .command,
            activateAllWindows: false,
            wheelShowsWebsites: true,
            wheelAlternateModifiers: .option
        )

        let result = ProfileConfigurationMigrationService.migrateLegacyKeyboardSettings(
            legacySettings,
            in: [emptyKeyboardProfile, customizedProfile],
            activeProfileId: targetProfileId
        )

        XCTAssertTrue(result.didMigrate)
        XCTAssertEqual(result.activeProfile?.id, targetProfileId)
        XCTAssertEqual(result.profiles[0].onScreenKeyboardSettings, legacySettings)
        XCTAssertEqual(result.profiles[1].onScreenKeyboardSettings, customizedProfile.onScreenKeyboardSettings)
    }

    func testMigrateLegacyKeyboardSettingsReportsMigrationEvenWhenNoProfileChanges() {
        var customizedProfile = Profile(id: UUID(), name: "Custom")
        customizedProfile.onScreenKeyboardSettings = OnScreenKeyboardSettings(
            quickTexts: [QuickText(text: "existing")],
            toggleShortcutKeyCode: 12
        )

        let legacySettings = OnScreenKeyboardSettings(quickTexts: [QuickText(text: "legacy")])
        let result = ProfileConfigurationMigrationService.migrateLegacyKeyboardSettings(
            legacySettings,
            in: [customizedProfile],
            activeProfileId: nil
        )

        XCTAssertTrue(result.didMigrate)
        XCTAssertEqual(result.profiles[0].onScreenKeyboardSettings, customizedProfile.onScreenKeyboardSettings)
        XCTAssertNil(result.activeProfile)
    }
}
