import XCTest
@testable import ControllerKeys

final class ProfileConfigurationPostLoadPolicyTests: XCTestCase {
    func testPreLoadLogMessageReturnsNilWhenNotMigratingFromLegacy() {
        let message = ProfileConfigurationPostLoadPolicy.preLoadLogMessage(
            migratingFromLegacy: false,
            legacyConfigURL: URL(fileURLWithPath: "/tmp/legacy-config.json")
        )

        XCTAssertNil(message)
    }

    func testPreLoadLogMessageIncludesLegacyPathWhenMigrating() {
        let legacyURL = URL(fileURLWithPath: "/tmp/legacy-config.json")
        let message = ProfileConfigurationPostLoadPolicy.preLoadLogMessage(
            migratingFromLegacy: true,
            legacyConfigURL: legacyURL
        )

        XCTAssertEqual(message, "[ProfileManager] Migrating config from legacy location: \(legacyURL.path)")
    }

    func testPersistenceDecisionDoesNotPersistWhenNoMigrationOccurred() {
        let configURL = URL(fileURLWithPath: "/tmp/config.json")
        let decision = ProfileConfigurationPostLoadPolicy.persistenceDecision(
            migratingFromLegacy: false,
            didMigrate: false,
            configURL: configURL
        )

        XCTAssertEqual(
            decision,
            ProfileConfigurationPostLoadDecision(
                shouldPersist: false,
                postPersistLogMessage: nil
            )
        )
    }

    func testPersistenceDecisionPersistsForDataMigrationWithoutLegacyMove() {
        let configURL = URL(fileURLWithPath: "/tmp/config.json")
        let decision = ProfileConfigurationPostLoadPolicy.persistenceDecision(
            migratingFromLegacy: false,
            didMigrate: true,
            configURL: configURL
        )

        XCTAssertEqual(
            decision,
            ProfileConfigurationPostLoadDecision(
                shouldPersist: true,
                postPersistLogMessage: nil
            )
        )
    }

    func testPersistenceDecisionPersistsAndLogsWhenMigratingFromLegacy() {
        let configURL = URL(fileURLWithPath: "/tmp/config.json")
        let decision = ProfileConfigurationPostLoadPolicy.persistenceDecision(
            migratingFromLegacy: true,
            didMigrate: false,
            configURL: configURL
        )

        XCTAssertEqual(
            decision,
            ProfileConfigurationPostLoadDecision(
                shouldPersist: true,
                postPersistLogMessage: "[ProfileManager] Config migrated to new location: \(configURL.path)"
            )
        )
    }
}
