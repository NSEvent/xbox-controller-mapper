import XCTest
@testable import ControllerKeys

@MainActor
final class AnkiProfileSelectionTests: MappingEngineTestCase {
	private func communityProfile(_ name: String) throws -> Profile {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try decoder.decode(Profile.self, from: Data(contentsOf:
			root.appendingPathComponent("community-profiles/\(name).json")))
	}

	private func prepareProfiles() throws -> (Profile, Profile) {
		mappingEngine.shutdown()
		appMonitor.frontmostBundleId = "com.apple.finder"
		profileManager = ProfileManager(appMonitor: appMonitor, configDirectoryOverride: testConfigDirectory)
		let basic = profileManager.importFetchedProfile(try communityProfile("Anki Flashcards"))
		let anking = profileManager.importFetchedProfile(try communityProfile("Anki - AnKing (USMLE)"))
		appMonitor.frontmostBundleId = Bundle.main.bundleIdentifier
		profileManager.setActiveProfile(basic)
		appMonitor.frontmostBundleId = "net.ankiweb.anki"
		XCTAssertEqual(profileManager.activeProfileId, basic.id)
		return (basic, anking)
	}

	private func returnToAnkiExpecting(_ profile: Profile) {
		appMonitor.frontmostBundleId = "com.apple.finder"
		XCTAssertTrue(profileManager.activeProfile?.isDefault == true)
		appMonitor.frontmostBundleId = "net.ankiweb.anki"
		XCTAssertEqual(profileManager.activeProfileId, profile.id)
		XCTAssertEqual(profileManager.activeProfile?.buttonMappings[.b]?.keyCode, 19,
			"AnKing B=Hard must not silently revert to basic Anki B=Again")
	}

	func testNewerMenuBarChoiceSurvivesFinderRoundTrip() throws {
		let (_, anking) = try prepareProfiles()
		// MenuBarView's onSelect does not need to foreground the editor.
		profileManager.setActiveProfile(anking)
		XCTAssertEqual(profileManager.activeProfileId, anking.id)
		returnToAnkiExpecting(anking)
	}

	func testControllerProfileNavigationSurvivesFinderRoundTrip() throws {
		let (_, anking) = try prepareProfiles()
		XCTAssertTrue(profileManager.navigateProfile(.next))
		XCTAssertEqual(profileManager.activeProfileId, anking.id)
		returnToAnkiExpecting(anking)
	}

	func testMainWindowChoiceSurvivesSameFinderRoundTrip() throws {
		let (_, anking) = try prepareProfiles()
		appMonitor.frontmostBundleId = Bundle.main.bundleIdentifier
		profileManager.setActiveProfile(anking)
		appMonitor.frontmostBundleId = "net.ankiweb.anki"
		returnToAnkiExpecting(anking)
	}

	func testReselectingAutomaticallyActivatedProfileMakesItExplicit() throws {
		let (_, anking) = try prepareProfiles()
		profileManager.setActiveProfile(anking, isAutomatic: true)
		profileManager.setActiveProfile(anking) // Same ID, but now explicitly chosen.
		returnToAnkiExpecting(anking)
	}

	func testAutomaticLinkedAppSwitchDoesNotReplaceEditingChoice() throws {
		let (basic, _) = try prepareProfiles()
		let other = Profile(name: "Other App", linkedApps: ["com.controllerkeys.other-fixture"])
		profileManager.profiles.append(other)
		appMonitor.frontmostBundleId = "com.controllerkeys.other-fixture"
		XCTAssertEqual(profileManager.activeProfileId, other.id)
		appMonitor.frontmostBundleId = Bundle.main.bundleIdentifier
		XCTAssertEqual(profileManager.activeProfileId, basic.id)
	}

	func testBackgroundChoiceSurvivesRelaunchFromDefaultProfile() throws {
		let (_, anking) = try prepareProfiles()
		profileManager.setActiveProfile(anking)
		appMonitor.frontmostBundleId = "com.apple.finder"
		profileManager.flushPendingSaves()
		profileManager = ProfileManager(appMonitor: appMonitor, configDirectoryOverride: testConfigDirectory)
		appMonitor.frontmostBundleId = "net.ankiweb.anki"
		XCTAssertEqual(profileManager.activeProfileId, anking.id)
		XCTAssertEqual(profileManager.activeProfile?.buttonMappings[.b]?.keyCode, 19)
	}

	override func tearDown() async throws {
		await MainActor.run { profileManager?.flushPendingSaves() }
		try await super.tearDown()
	}
}
