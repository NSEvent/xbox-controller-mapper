import XCTest
@testable import ControllerKeys

@MainActor
final class ProfileManagerSettingsCoverageTests: XCTestCase {
    private var profileManager: ProfileManager!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-tests-\(UUID().uuidString)", isDirectory: true)
        profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
    }

    override func tearDown() async throws {
        profileManager = nil
        testConfigDirectory = nil
        try await super.tearDown()
    }

    func testSetDefaultTerminalAndTypingDelayUpdatesActiveProfile() {
        profileManager.setDefaultTerminalApp("Warp")
        profileManager.setTypingDelay(0.12)

        guard let settings = profileManager.activeProfile?.onScreenKeyboardSettings else {
            return XCTFail("Expected active profile settings")
        }
        XCTAssertEqual(settings.defaultTerminalApp, "Warp")
        XCTAssertEqual(settings.typingDelay, 0.12, accuracy: 0.0001)
    }

    func testAppBarItemCRUDAndMove() {
        let firstId = UUID()
        let secondId = UUID()
        let first = AppBarItem(id: firstId, bundleIdentifier: "com.example.first", displayName: "First")
        let second = AppBarItem(id: secondId, bundleIdentifier: "com.example.second", displayName: "Second")

        profileManager.addAppBarItem(first)
        profileManager.addAppBarItem(second)
        XCTAssertEqual(profileManager.activeProfile?.onScreenKeyboardSettings.appBarItems.map(\.id), [firstId, secondId])

        profileManager.moveAppBarItems(from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(profileManager.activeProfile?.onScreenKeyboardSettings.appBarItems.map(\.id), [secondId, firstId])

        let updatedFirst = AppBarItem(id: firstId, bundleIdentifier: "com.example.first", displayName: "First Updated")
        profileManager.updateAppBarItem(updatedFirst)
        XCTAssertEqual(
            profileManager.activeProfile?.onScreenKeyboardSettings.appBarItems.first(where: { $0.id == firstId })?.displayName,
            "First Updated"
        )

        profileManager.removeAppBarItem(second)
        XCTAssertEqual(profileManager.activeProfile?.onScreenKeyboardSettings.appBarItems.map(\.id), [firstId])
    }

    func testWebsiteLinkCRUDAndMove() {
        let firstId = UUID()
        let secondId = UUID()
        let first = WebsiteLink(id: firstId, url: "https://example.com", displayName: "Example")
        let second = WebsiteLink(id: secondId, url: "https://swift.org", displayName: "Swift")

        profileManager.addWebsiteLink(first)
        profileManager.addWebsiteLink(second)
        XCTAssertEqual(profileManager.activeProfile?.onScreenKeyboardSettings.websiteLinks.map(\.id), [firstId, secondId])

        profileManager.moveWebsiteLinks(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(profileManager.activeProfile?.onScreenKeyboardSettings.websiteLinks.map(\.id), [secondId, firstId])

        let updatedSecond = WebsiteLink(id: secondId, url: "https://swift.org/docs", displayName: "Swift Docs")
        profileManager.updateWebsiteLink(updatedSecond)
        let updated = profileManager.activeProfile?.onScreenKeyboardSettings.websiteLinks.first(where: { $0.id == secondId })
        XCTAssertEqual(updated?.url, "https://swift.org/docs")
        XCTAssertEqual(updated?.displayName, "Swift Docs")

        profileManager.removeWebsiteLink(first)
        XCTAssertEqual(profileManager.activeProfile?.onScreenKeyboardSettings.websiteLinks.map(\.id), [secondId])
    }

    func testMoveMacrosReordersInActiveProfile() {
        let macroA = Macro(name: "A", steps: [.delay(0.01)])
        let macroB = Macro(name: "B", steps: [.delay(0.01)])
        let macroC = Macro(name: "C", steps: [.delay(0.01)])

        profileManager.addMacro(macroA)
        profileManager.addMacro(macroB)
        profileManager.addMacro(macroC)
        XCTAssertEqual(profileManager.activeProfile?.macros.map(\.name), ["A", "B", "C"])

        profileManager.moveMacros(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(profileManager.activeProfile?.macros.map(\.name), ["B", "C", "A"])
    }

    func testExportAndImportProfileRoundTrip() throws {
        let original = Profile(name: "Export Me")
        let exportURL = testConfigDirectory.appendingPathComponent("exported-profile.json")

        try profileManager.exportProfile(original, to: exportURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))

        let imported = try profileManager.importProfile(from: exportURL)
        XCTAssertNotEqual(imported.id, original.id)
        XCTAssertEqual(imported.name, original.name)
        XCTAssertFalse(imported.isDefault)
        XCTAssertTrue(profileManager.profiles.contains(where: { $0.id == imported.id }))
    }

    func testImportFetchedProfileAssignsNewIdentity() {
        let remote = Profile(name: "Remote", isDefault: true)
        let imported = profileManager.importFetchedProfile(remote)

        XCTAssertNotEqual(imported.id, remote.id)
        XCTAssertFalse(imported.isDefault)
        XCTAssertTrue(profileManager.profiles.contains(where: { $0.id == imported.id }))
    }

    func testCommunityProfileInfoDecodingDisplayNameAndId() throws {
        let json = """
        {
          "name": "my-profile.json",
          "download_url": "https://example.com/my-profile.json",
          "type": "file"
        }
        """

        let info = try JSONDecoder().decode(CommunityProfileInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.id, "my-profile.json")
        XCTAssertEqual(info.displayName, "my-profile")
        XCTAssertEqual(info.downloadURL, "https://example.com/my-profile.json")
    }

    func testCommunityProfileErrorDescriptions() {
        XCTAssertEqual(CommunityProfileError.invalidURL.errorDescription, "Invalid URL")
        XCTAssertTrue((CommunityProfileError.networkError(URLError(.timedOut)).errorDescription ?? "").contains("Network error:"))
        XCTAssertEqual(CommunityProfileError.invalidResponse.errorDescription, "Invalid response from server")
        XCTAssertTrue((CommunityProfileError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))).errorDescription ?? "").contains("Failed to decode profile:"))
    }

    func testFetchProfileForPreviewRejectsInvalidURL() async {
        do {
            _ = try await profileManager.fetchProfileForPreview(from: "")
            XCTFail("Expected invalid URL error")
        } catch let error as CommunityProfileError {
            XCTAssertEqual(error.errorDescription, CommunityProfileError.invalidURL.errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDownloadProfileRejectsInvalidURL() async {
        do {
            _ = try await profileManager.downloadProfile(from: "")
            XCTFail("Expected invalid URL error")
        } catch let error as CommunityProfileError {
            XCTAssertEqual(error.errorDescription, CommunityProfileError.invalidURL.errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
