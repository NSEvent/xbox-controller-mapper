import XCTest
@testable import ControllerKeys

final class ProfileLoadedDataApplicatorTests: XCTestCase {
    func testApplyFiltersInvalidProfilesPreservesStoredOrderAndKeepsMatchingActiveProfile() {
        let now = Date()
        let older = now.addingTimeInterval(-60)

        var newerProfile = Profile(id: UUID(), name: "Newer")
        newerProfile.createdAt = now

        var olderProfile = Profile(id: UUID(), name: "Older")
        olderProfile.createdAt = older

        var invalidProfile = Profile(id: UUID(), name: "Invalid")
        invalidProfile.name = "   "

        let result = ProfileLoadedDataApplicator.apply(
            loadedProfiles: [newerProfile, invalidProfile, olderProfile],
			activeProfileId: newerProfile.id,
			lastActiveProfileId: olderProfile.id
        )

		XCTAssertEqual(result?.profiles.map(\.id), [newerProfile.id, olderProfile.id])
        XCTAssertEqual(result?.activeProfile?.id, newerProfile.id)
        XCTAssertEqual(result?.activeProfileId, newerProfile.id)
		XCTAssertEqual(result?.lastActiveProfileId, olderProfile.id)
    }

    func testApplyClearsActiveProfileWhenActiveIdMissing() {
        let profile = Profile(id: UUID(), name: "Only")

        let result = ProfileLoadedDataApplicator.apply(
            loadedProfiles: [profile],
            activeProfileId: UUID()
        )

        XCTAssertEqual(result?.profiles.count, 1)
        XCTAssertNil(result?.activeProfile)
        XCTAssertNil(result?.activeProfileId)
		XCTAssertNil(result?.lastActiveProfileId)
    }

	func testApplyClearsSameOrMissingLastActiveProfile() {
		let first = Profile(id: UUID(), name: "First")
		let second = Profile(id: UUID(), name: "Second")

		let sameAsActive = ProfileLoadedDataApplicator.apply(
			loadedProfiles: [first, second],
			activeProfileId: first.id,
			lastActiveProfileId: first.id
		)
		let missing = ProfileLoadedDataApplicator.apply(
			loadedProfiles: [first, second],
			activeProfileId: first.id,
			lastActiveProfileId: UUID()
		)

		XCTAssertNil(sameAsActive?.lastActiveProfileId)
		XCTAssertNil(missing?.lastActiveProfileId)
	}

    func testApplyReturnsNilWhenNoValidProfilesRemain() {
        var invalidProfile = Profile(id: UUID(), name: "Invalid")
        invalidProfile.name = ""

        let result = ProfileLoadedDataApplicator.apply(
            loadedProfiles: [invalidProfile],
            activeProfileId: nil
        )

        XCTAssertNil(result)
    }
}
