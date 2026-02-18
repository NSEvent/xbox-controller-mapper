import XCTest
@testable import ControllerKeys

final class ProfileAutoSwitchResolverTests: XCTestCase {
    private let configBundleId = "com.example.controllerkeys"

    func testResolveRestoresEditingProfileWhenReturningToConfigApp() {
        let editingProfile = makeProfile(name: "Editing")
        let activeProfile = makeProfile(name: "Auto")

        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.game",
            profileIdBeforeBackground: editingProfile.id,
            activeProfileId: activeProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: configBundleId,
            appBundleId: configBundleId,
            profiles: [editingProfile, activeProfile],
            state: state
        )

        XCTAssertEqual(
            result.action,
            ProfileAutoSwitchAction(
                profileId: editingProfile.id,
                reason: .restoreEditingProfile
            )
        )
        XCTAssertEqual(result.previousBundleId, configBundleId)
        XCTAssertEqual(result.profileIdBeforeBackground, editingProfile.id)
    }

    func testResolveDoesNotRestoreMissingEditingProfile() {
        let activeProfile = makeProfile(name: "Auto")
        let missingProfileId = UUID()

        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.game",
            profileIdBeforeBackground: missingProfileId,
            activeProfileId: activeProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: configBundleId,
            appBundleId: configBundleId,
            profiles: [activeProfile],
            state: state
        )

        XCTAssertNil(result.action)
        XCTAssertEqual(result.previousBundleId, configBundleId)
        XCTAssertEqual(result.profileIdBeforeBackground, missingProfileId)
    }

    func testResolveSavesCurrentProfileWhenLeavingConfigApp() {
        let activeProfile = makeProfile(name: "Editing")
        let state = ProfileAutoSwitchState(
            previousBundleId: configBundleId,
            profileIdBeforeBackground: nil,
            activeProfileId: activeProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: "com.example.notes",
            appBundleId: configBundleId,
            profiles: [activeProfile],
            state: state
        )

        XCTAssertEqual(result.previousBundleId, "com.example.notes")
        XCTAssertEqual(result.profileIdBeforeBackground, activeProfile.id)
    }

    func testResolveSwitchesToLinkedProfileBeforeDefault() {
        let defaultProfile = makeProfile(name: "Default", isDefault: true)
        let linkedProfile = makeProfile(name: "Game", linkedApps: ["com.example.game"])
        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.mail",
            profileIdBeforeBackground: nil,
            activeProfileId: defaultProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: "com.example.game",
            appBundleId: configBundleId,
            profiles: [defaultProfile, linkedProfile],
            state: state
        )

        XCTAssertEqual(
            result.action,
            ProfileAutoSwitchAction(
                profileId: linkedProfile.id,
                reason: .linkedApp(bundleId: "com.example.game")
            )
        )
    }

    func testResolveFallsBackToDefaultProfileWhenNoLinkedProfileExists() {
        let defaultProfile = makeProfile(name: "Default", isDefault: true)
        let customProfile = makeProfile(name: "Editing")
        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.game",
            profileIdBeforeBackground: customProfile.id,
            activeProfileId: customProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: "com.example.notes",
            appBundleId: configBundleId,
            profiles: [defaultProfile, customProfile],
            state: state
        )

        XCTAssertEqual(
            result.action,
            ProfileAutoSwitchAction(
                profileId: defaultProfile.id,
                reason: .defaultProfile(bundleId: "com.example.notes")
            )
        )
    }

    func testResolveDoesNothingWhenTargetProfileAlreadyActive() {
        let defaultProfile = makeProfile(name: "Default", isDefault: true)
        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.mail",
            profileIdBeforeBackground: nil,
            activeProfileId: defaultProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: "com.example.notes",
            appBundleId: configBundleId,
            profiles: [defaultProfile],
            state: state
        )

        XCTAssertNil(result.action)
        XCTAssertEqual(result.previousBundleId, "com.example.notes")
    }

    private func makeProfile(name: String, isDefault: Bool = false, linkedApps: [String] = []) -> Profile {
        Profile(
            id: UUID(),
            name: name,
            isDefault: isDefault,
            linkedApps: linkedApps
        )
    }
}
