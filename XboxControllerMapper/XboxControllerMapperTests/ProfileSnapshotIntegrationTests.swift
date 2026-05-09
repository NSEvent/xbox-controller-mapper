import XCTest
@testable import ControllerKeys

@MainActor
final class ProfileSnapshotIntegrationTests: XCTestCase {
    private var testConfigDirectory: URL!
    private var profileManager: ProfileManager!

    override func setUp() async throws {
        try await super.setUp()
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-snapshot-integration-\(UUID().uuidString)", isDirectory: true)
        profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
    }

    override func tearDown() async throws {
        if let testConfigDirectory {
            try? FileManager.default.removeItem(at: testConfigDirectory)
        }
        profileManager = nil
        testConfigDirectory = nil
        try await super.tearDown()
    }

    func testDeleteProfileWritesSnapshotBeforeRemoval() async throws {
        let extra = profileManager.createProfile(name: "Doomed")
        XCTAssertTrue(profileManager.profiles.contains(where: { $0.id == extra.id }))

        let snapshotsBefore = profileManager.availableSnapshots().count
        profileManager.deleteProfile(extra)

        // Snapshot was written synchronously (file I/O is sync in writeSnapshot).
        let snapshots = profileManager.availableSnapshots()
        XCTAssertEqual(snapshots.count, snapshotsBefore + 1)
        XCTAssertTrue(snapshots.first?.reason.contains("Doomed") == true,
                      "Expected snapshot reason to mention deleted profile name, got: \(snapshots.first?.reason ?? "nil")")
    }

    func testRestoreSnapshotReinstatesDeletedProfile() async throws {
        let extra = profileManager.createProfile(name: "BringMeBack")
        let countWithExtra = profileManager.profiles.count

        profileManager.deleteProfile(extra)
        XCTAssertEqual(profileManager.profiles.count, countWithExtra - 1)

        let snapshot = try XCTUnwrap(
            profileManager.availableSnapshots().first { $0.reason.contains("BringMeBack") },
            "Expected a snapshot tagged with the deleted profile's name"
        )

        XCTAssertTrue(profileManager.restoreSnapshot(snapshot))

        XCTAssertEqual(profileManager.profiles.count, countWithExtra)
        XCTAssertTrue(profileManager.profiles.contains(where: { $0.id == extra.id }),
                      "Restored config should contain the previously-deleted profile")
    }

    func testRestoreItselfIsUndoable() async throws {
        let extra = profileManager.createProfile(name: "FirstState")
        profileManager.deleteProfile(extra)

        let snapshot = try XCTUnwrap(profileManager.availableSnapshots().first { $0.reason.contains("FirstState") })
        let snapshotsBeforeRestore = profileManager.availableSnapshots().count

        XCTAssertTrue(profileManager.restoreSnapshot(snapshot))

        let snapshotsAfter = profileManager.availableSnapshots()
        XCTAssertEqual(snapshotsAfter.count, snapshotsBeforeRestore + 1,
                       "Restore should write a 'before restore' snapshot first")
        XCTAssertTrue(snapshotsAfter.first?.reason.lowercased().contains("before restoring") == true,
                      "Newest snapshot should be the pre-restore checkpoint, got: \(snapshotsAfter.first?.reason ?? "nil")")
    }
}
