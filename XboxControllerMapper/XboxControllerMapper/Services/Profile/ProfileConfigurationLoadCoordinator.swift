import Foundation
import SwiftUI

struct ProfileConfigurationLoadResult: Equatable {
    let profiles: [Profile]
    let activeProfile: Profile?
    let activeProfileId: UUID?
	let lastActiveProfileId: UUID?
    let uiScale: CGFloat?
    let didMigrate: Bool
}

enum ProfileConfigurationLoadCoordinator {
    static func load(from url: URL) throws -> ProfileConfigurationLoadResult {
        let data = try Data(contentsOf: url)
        return try load(data: data)
    }

    static func load(data: Data) throws -> ProfileConfigurationLoadResult {
        let config = try ProfileConfigurationCodec.decode(from: data)
		// Profile decoding performs the conservative v4 → v5 D-pad migration.
		// Mark it dirty so the newly explicit provenance is persisted immediately.
		var didMigrate = config.schemaVersion < 5

        let (touchpadSettingsMigrated, migratedTouchpadSettings) = ProfileConfigurationMigrationService
            .migrateTouchpadSettingsIfNeeded(in: config.profiles)
        didMigrate = didMigrate || migratedTouchpadSettings

        // v1 → v2: promote `touchpadRegionMappings` rows to first-class
        // ControllerButton mappings. Idempotent — profiles whose legacy list
        // is already empty pass through unchanged.
        let (migratedProfiles, regionsPromoted) = ProfileConfigurationMigrationService
            .migrateTouchpadRegionsToButtons(in: touchpadSettingsMigrated)
        didMigrate = didMigrate || regionsPromoted

        let applied = ProfileLoadedDataApplicator.apply(
            loadedProfiles: migratedProfiles,
			activeProfileId: config.activeProfileId,
			lastActiveProfileId: config.lastActiveProfileId
        )

        var profiles = applied?.profiles ?? []
		var activeProfile = applied?.activeProfile
		var activeProfileId = applied?.activeProfileId
		let lastActiveProfileId = applied?.lastActiveProfileId

        if let legacyKeyboardSettings = config.onScreenKeyboardSettings {
            let migration = ProfileConfigurationMigrationService.migrateLegacyKeyboardSettings(
                legacyKeyboardSettings,
                in: profiles,
                activeProfileId: activeProfileId
            )
            profiles = migration.profiles
            activeProfile = migration.activeProfile
            activeProfileId = migration.activeProfile?.id
            didMigrate = didMigrate || migration.didMigrate
        }

        return ProfileConfigurationLoadResult(
            profiles: profiles,
			activeProfile: activeProfile,
			activeProfileId: activeProfileId,
			lastActiveProfileId: lastActiveProfileId,
			uiScale: config.uiScale,
            didMigrate: didMigrate
        )
    }
}
