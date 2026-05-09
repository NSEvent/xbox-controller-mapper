import XCTest
@testable import ControllerKeys

final class SnapshotServiceTests: XCTestCase {
    private var tempDirectory: URL!
    private var snapshotsDirectory: URL!
    private var fileManager: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = .default
        tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "controllerkeys-snapshot-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        snapshotsDirectory = tempDirectory.appendingPathComponent("snapshots", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? fileManager.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        snapshotsDirectory = nil
        fileManager = nil
        try super.tearDownWithError()
    }

    func testWriteSnapshotCreatesDirectoryAndFile() throws {
        let service = SnapshotService(snapshotsDirectory: snapshotsDirectory, fileManager: fileManager)
        let config = makeConfiguration(profileName: "Original")

        let snapshot = service.writeSnapshot(config, reason: "test write")

        XCTAssertNotNil(snapshot)
        XCTAssertTrue(fileManager.fileExists(atPath: snapshotsDirectory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: snapshot!.fileURL.path))
        XCTAssertEqual(snapshot!.reason, "test write")
    }

    func testWriteThenLoadRoundTripsConfiguration() throws {
        let service = SnapshotService(snapshotsDirectory: snapshotsDirectory, fileManager: fileManager)
        let original = makeConfiguration(profileName: "Original", uiScale: 1.4)

        let snapshot = try XCTUnwrap(service.writeSnapshot(original, reason: "round-trip"))
        let restored = try service.loadConfiguration(from: snapshot)

        XCTAssertEqual(restored.profiles.count, 1)
        XCTAssertEqual(restored.profiles.first?.name, "Original")
        XCTAssertEqual(restored.activeProfileId, original.activeProfileId)
        XCTAssertEqual(restored.uiScale ?? 0, 1.4, accuracy: 0.0001)
    }

    func testListSnapshotsReturnsNewestFirst() throws {
        let service = SnapshotService(snapshotsDirectory: snapshotsDirectory, fileManager: fileManager)
        let config = makeConfiguration(profileName: "P")

        // Use distinct timestamps so filenames don't collide.
        let older = Date(timeIntervalSince1970: 1_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000)
        _ = service.writeSnapshot(config, reason: "older", now: older)
        _ = service.writeSnapshot(config, reason: "newer", now: newer)

        let snapshots = service.listSnapshots()

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].reason, "newer")
        XCTAssertEqual(snapshots[1].reason, "older")
    }

    func testPruningEnforcesMaxSnapshots() throws {
        let service = SnapshotService(
            snapshotsDirectory: snapshotsDirectory,
            fileManager: fileManager,
            maxSnapshots: 3
        )
        let config = makeConfiguration(profileName: "P")

        for i in 0..<5 {
            _ = service.writeSnapshot(config, reason: "snap \(i)", now: Date(timeIntervalSince1970: TimeInterval(1_000_000 + i)))
        }

        let snapshots = service.listSnapshots()
        XCTAssertEqual(snapshots.count, 3)
        // Oldest two ("snap 0", "snap 1") should have been pruned.
        let reasons = snapshots.map(\.reason)
        XCTAssertEqual(reasons, ["snap 4", "snap 3", "snap 2"])
    }

    func testWritingNewSnapshotAtCapPrunesOldestImmediately() throws {
        // Documents the constraint that callers (notably ProfileManager.restoreSnapshot)
        // must load a target snapshot BEFORE writing a new one if they want to
        // guarantee the target remains on disk. A previous version of restore
        // wrote the pre-restore checkpoint first, which evicted the target
        // when the target was the oldest at the cap boundary.
        let service = SnapshotService(
            snapshotsDirectory: snapshotsDirectory,
            fileManager: fileManager,
            maxSnapshots: 3
        )
        let config = makeConfiguration(profileName: "P")
        let oldest = try XCTUnwrap(
            service.writeSnapshot(config, reason: "oldest", now: Date(timeIntervalSince1970: 1))
        )
        _ = service.writeSnapshot(config, reason: "mid", now: Date(timeIntervalSince1970: 2))
        _ = service.writeSnapshot(config, reason: "newer", now: Date(timeIntervalSince1970: 3))

        // At the cap, oldest is still loadable.
        XCTAssertNoThrow(try service.loadConfiguration(from: oldest))

        // Writing a 4th at the cap evicts the oldest.
        _ = service.writeSnapshot(config, reason: "fourth", now: Date(timeIntervalSince1970: 4))

        XCTAssertThrowsError(try service.loadConfiguration(from: oldest),
                             "Oldest file should be gone after a write past the cap — load now fails")
    }

    func testListIgnoresUnrelatedAndUnreadableFiles() throws {
        let service = SnapshotService(snapshotsDirectory: snapshotsDirectory, fileManager: fileManager)
        let config = makeConfiguration(profileName: "P")
        _ = service.writeSnapshot(config, reason: "valid")

        // Unrelated file in the directory should be ignored.
        let stray = snapshotsDirectory.appendingPathComponent("README.txt")
        try Data("not a snapshot".utf8).write(to: stray)

        // A snapshot-named file with garbage contents should be skipped, not crash.
        let garbage = snapshotsDirectory.appendingPathComponent("snapshot_2026-01-01_00-00-00.json")
        try Data("{not json".utf8).write(to: garbage)

        let snapshots = service.listSnapshots()
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].reason, "valid")
    }

    // MARK: - Helpers

    private func makeConfiguration(profileName: String, uiScale: CGFloat = 1.0) -> ProfileConfiguration {
        let profile = Profile(id: UUID(), name: profileName)
        return ProfileConfiguration(
            profiles: [profile],
            activeProfileId: profile.id,
            uiScale: uiScale
        )
    }
}
