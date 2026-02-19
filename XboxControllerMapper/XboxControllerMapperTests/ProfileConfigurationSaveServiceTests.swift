import XCTest
@testable import ControllerKeys

final class ProfileConfigurationSaveServiceTests: XCTestCase {
    private var tempDirectory: URL!
    private var fileManager: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = .default
        tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "controllerkeys-save-service-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? fileManager.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        fileManager = nil
        try super.tearDownWithError()
    }

    func testShouldSaveReturnsFalseWhenLoadFailedAndConfigExists() throws {
        let configURL = tempDirectory.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: configURL)
        let service = makeSynchronousService()

        let shouldSave = service.shouldSave(loadSucceeded: false, configURL: configURL)

        XCTAssertFalse(shouldSave)
    }

    func testShouldSaveReturnsTrueWhenLoadSucceededAndConfigExists() throws {
        let configURL = tempDirectory.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: configURL)
        let service = makeSynchronousService()

        let shouldSave = service.shouldSave(loadSucceeded: true, configURL: configURL)

        XCTAssertTrue(shouldSave)
    }

    func testShouldSaveReturnsTrueWhenConfigDoesNotExist() {
        let configURL = tempDirectory.appendingPathComponent("missing-config.json")
        let service = makeSynchronousService()

        let shouldSave = service.shouldSave(loadSucceeded: false, configURL: configURL)

        XCTAssertTrue(shouldSave)
    }

    func testSaveWritesConfigurationAndCreatesBackupWhenConfigExists() throws {
        let configURL = tempDirectory.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: configURL)
        let service = makeSynchronousService()

        let profile = Profile(id: UUID(), name: "Saved")
        let config = ProfileConfiguration(
            profiles: [profile],
            activeProfileId: profile.id,
            uiScale: 1.3
        )

        service.save(config, to: configURL)

        let writtenData = try Data(contentsOf: configURL)
        let decoded = try ProfileConfigurationCodec.decode(from: writtenData)
        XCTAssertEqual(decoded.profiles.count, 1)
        XCTAssertEqual(decoded.profiles.first?.id, profile.id)
        XCTAssertEqual(decoded.activeProfileId, profile.id)
        XCTAssertEqual(decoded.uiScale ?? 0, 1.3, accuracy: 0.0001)

        let backupDirectory = tempDirectory.appendingPathComponent("backups", isDirectory: true)
        let backups = (try? fileManager.contentsOfDirectory(atPath: backupDirectory.path)) ?? []
        XCTAssertFalse(backups.isEmpty)
    }

    func testSaveLogsFailureWhenWriteFails() {
        guard let configURL = tempDirectory else {
            XCTFail("tempDirectory should be set in setUp")
            return
        }
        var logMessages: [String] = []
        let service = ProfileConfigurationSaveService(
            fileManager: fileManager,
            scheduleWrite: { work in work() },
            logSaveFailure: { logMessages.append($0) }
        )

        let profile = Profile(id: UUID(), name: "Saved")
        let config = ProfileConfiguration(
            profiles: [profile],
            activeProfileId: profile.id,
            uiScale: 1.0
        )

        service.save(config, to: configURL)

        XCTAssertEqual(logMessages.count, 1)
        XCTAssertTrue(logMessages[0].contains("[ProfileManager] Configuration save failed"))
    }

    private func makeSynchronousService() -> ProfileConfigurationSaveService {
        ProfileConfigurationSaveService(
            fileManager: fileManager,
            scheduleWrite: { work in
                work()
            }
        )
    }
}
