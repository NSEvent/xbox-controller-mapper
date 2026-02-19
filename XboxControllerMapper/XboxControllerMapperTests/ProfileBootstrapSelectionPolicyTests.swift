import XCTest
@testable import ControllerKeys

final class ProfileBootstrapSelectionPolicyTests: XCTestCase {
    func testResolveCreatesDefaultWhenProfilesAreEmpty() {
        let action = ProfileBootstrapSelectionPolicy.resolve(
            profiles: [],
            hasActiveProfile: false
        )

        XCTAssertEqual(action, .createAndActivateDefault)
    }

    func testResolveDoesNothingWhenActiveProfileAlreadyExists() {
        let profile = Profile(id: UUID(), name: "Active")
        let action = ProfileBootstrapSelectionPolicy.resolve(
            profiles: [profile],
            hasActiveProfile: true
        )

        XCTAssertEqual(action, .none)
    }

    func testResolveActivatesDefaultProfileWhenNoActiveProfile() {
        let defaultProfile = Profile(id: UUID(), name: "Default", isDefault: true)
        let secondaryProfile = Profile(id: UUID(), name: "Secondary")
        let action = ProfileBootstrapSelectionPolicy.resolve(
            profiles: [secondaryProfile, defaultProfile],
            hasActiveProfile: false
        )

        XCTAssertEqual(action, .activateProfile(defaultProfile.id))
    }

    func testResolveActivatesFirstProfileWhenNoDefaultExists() {
        let firstProfile = Profile(id: UUID(), name: "First")
        let secondProfile = Profile(id: UUID(), name: "Second")
        let action = ProfileBootstrapSelectionPolicy.resolve(
            profiles: [firstProfile, secondProfile],
            hasActiveProfile: false
        )

        XCTAssertEqual(action, .activateProfile(firstProfile.id))
    }

    func testResolvePrefersCreateDefaultForInconsistentEmptyProfilesState() {
        let action = ProfileBootstrapSelectionPolicy.resolve(
            profiles: [],
            hasActiveProfile: true
        )

        XCTAssertEqual(action, .createAndActivateDefault)
    }
}
