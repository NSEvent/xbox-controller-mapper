import Foundation
import SwiftUI

struct ProfileConfigurationLoadResult: Equatable {
    let profiles: [Profile]
    let activeProfile: Profile?
    let activeProfileId: UUID?
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
        var didMigrate = false

        let (migratedProfiles, migratedTouchpadSettings) = ProfileConfigurationMigrationService
            .migrateTouchpadSettingsIfNeeded(in: config.profiles)
        didMigrate = didMigrate || migratedTouchpadSettings

        let applied = ProfileLoadedDataApplicator.apply(
            loadedProfiles: migratedProfiles,
            activeProfileId: config.activeProfileId
        )

        var profiles = applied?.profiles ?? []
        var activeProfile = applied?.activeProfile
        var activeProfileId = applied?.activeProfileId

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
            uiScale: config.uiScale,
            didMigrate: didMigrate
        )
    }
}
