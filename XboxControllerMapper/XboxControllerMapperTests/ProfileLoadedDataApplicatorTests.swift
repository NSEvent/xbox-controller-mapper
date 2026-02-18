import XCTest
@testable import ControllerKeys

final class ProfileLoadedDataApplicatorTests: XCTestCase {
    func testApplyFiltersInvalidProfilesSortsByCreationDateAndKeepsMatchingActiveProfile() {
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
            activeProfileId: newerProfile.id
        )

        XCTAssertEqual(result?.profiles.map(\.id), [olderProfile.id, newerProfile.id])
        XCTAssertEqual(result?.activeProfile?.id, newerProfile.id)
        XCTAssertEqual(result?.activeProfileId, newerProfile.id)
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
