import Foundation

struct ProfileConfigurationPostLoadDecision: Equatable {
    let shouldPersist: Bool
    let postPersistLogMessage: String?
}

enum ProfileConfigurationPostLoadPolicy {
    static func preLoadLogMessage(migratingFromLegacy: Bool, legacyConfigURL: URL) -> String? {
        guard migratingFromLegacy else { return nil }
        return "[ProfileManager] Migrating config from legacy location: \(legacyConfigURL.path)"
    }

    static func persistenceDecision(
        migratingFromLegacy: Bool,
        didMigrate: Bool,
        configURL: URL
    ) -> ProfileConfigurationPostLoadDecision {
        let shouldPersist = migratingFromLegacy || didMigrate
        let postPersistLogMessage = migratingFromLegacy
            ? "[ProfileManager] Config migrated to new location: \(configURL.path)"
            : nil
        return ProfileConfigurationPostLoadDecision(
            shouldPersist: shouldPersist,
            postPersistLogMessage: postPersistLogMessage
        )
    }
}
