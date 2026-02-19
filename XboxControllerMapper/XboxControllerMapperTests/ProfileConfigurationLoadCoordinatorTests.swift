import XCTest
import SwiftUI
@testable import ControllerKeys

final class ProfileConfigurationLoadCoordinatorTests: XCTestCase {
    private var tempDirectory: URL!
    private var fileManager: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = .default
        tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "controllerkeys-load-coordinator-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? fileManager.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        fileManager = nil
        try super.tearDownWithError()
    }

    func testLoadAppliesSortingActiveProfileAndUiScale() throws {
        var older = Profile(id: UUID(), name: "Older")
        older.createdAt = Date(timeIntervalSince1970: 10)
        var newer = Profile(id: UUID(), name: "Newer")
        newer.createdAt = Date(timeIntervalSince1970: 20)

        let data = try makeConfigData(
            profiles: [newer, older],
            activeProfileId: newer.id,
            uiScale: 1.25
        )

        let result = try ProfileConfigurationLoadCoordinator.load(data: data)

        XCTAssertEqual(result.profiles.map(\.id), [older.id, newer.id])
        XCTAssertEqual(result.activeProfile?.id, newer.id)
        XCTAssertEqual(result.activeProfileId, newer.id)
        XCTAssertEqual(result.uiScale ?? 0, 1.25, accuracy: 0.0001)
        XCTAssertFalse(result.didMigrate)
    }

    func testLoadMigratesLegacyTouchpadSettings() throws {
        var legacySettings = JoystickSettings.default
        legacySettings.touchpadSensitivity = 0.5
        legacySettings.touchpadAcceleration = 0.5
        legacySettings.touchpadDeadzone = 0.01
        legacySettings.touchpadSmoothing = 0.4
        let profile = Profile(id: UUID(), name: "Legacy", joystickSettings: legacySettings)

        let data = try makeConfigData(
            profiles: [profile],
            activeProfileId: profile.id,
            uiScale: nil
        )

        let result = try ProfileConfigurationLoadCoordinator.load(data: data)

        XCTAssertTrue(result.didMigrate)
        XCTAssertEqual(result.profiles.first?.joystickSettings.touchpadDeadzone, 0.0)
    }

    func testLoadMigratesLegacyKeyboardSettings() throws {
        let activeId = UUID()
        var profile = Profile(id: activeId, name: "P")
        profile.onScreenKeyboardSettings = OnScreenKeyboardSettings(
            quickTexts: [],
            toggleShortcutKeyCode: nil
        )
        let legacySettings = OnScreenKeyboardSettings(
            quickTexts: [QuickText(text: "legacy")],
            toggleShortcutKeyCode: 40
        )
        let data = try makeConfigData(
            profiles: [profile],
            activeProfileId: activeId,
            uiScale: nil,
            legacyKeyboard: legacySettings
        )

        let result = try ProfileConfigurationLoadCoordinator.load(data: data)

        XCTAssertTrue(result.didMigrate)
        XCTAssertEqual(result.profiles.first?.onScreenKeyboardSettings, legacySettings)
        XCTAssertEqual(result.activeProfile?.id, activeId)
    }

    func testLoadReturnsEmptyWhenAllProfilesInvalid() throws {
        var invalid = Profile(id: UUID(), name: "Invalid")
        invalid.name = ""
        let data = try makeConfigData(
            profiles: [invalid],
            activeProfileId: invalid.id,
            uiScale: nil
        )

        let result = try ProfileConfigurationLoadCoordinator.load(data: data)

        XCTAssertTrue(result.profiles.isEmpty)
        XCTAssertNil(result.activeProfile)
        XCTAssertNil(result.activeProfileId)
    }

    func testLoadFromURLReadsAndParsesConfigFile() throws {
        let profile = Profile(id: UUID(), name: "FromFile")
        let data = try makeConfigData(
            profiles: [profile],
            activeProfileId: profile.id,
            uiScale: nil
        )
        let configURL = tempDirectory.appendingPathComponent("config.json")
        try data.write(to: configURL)

        let result = try ProfileConfigurationLoadCoordinator.load(from: configURL)

        XCTAssertEqual(result.profiles.first?.id, profile.id)
        XCTAssertEqual(result.activeProfileId, profile.id)
    }

    private func makeConfigData(
        profiles: [Profile],
        activeProfileId: UUID?,
        uiScale: CGFloat?,
        legacyKeyboard: OnScreenKeyboardSettings? = nil
    ) throws -> Data {
        var config = ProfileConfiguration(
            profiles: profiles,
            activeProfileId: activeProfileId,
            uiScale: uiScale
        )
        config.onScreenKeyboardSettings = legacyKeyboard
        return try ProfileConfigurationCodec.encode(config)
    }
}
