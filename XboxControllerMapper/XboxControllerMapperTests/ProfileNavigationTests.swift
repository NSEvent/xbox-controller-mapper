import XCTest
@testable import ControllerKeys

@MainActor
final class ProfileNavigationTests: XCTestCase {
	private var profileManager: ProfileManager!
	private var testConfigDirectory: URL!

	override func setUp() async throws {
		try await super.setUp()
		testConfigDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("controllerkeys-tests-\(UUID().uuidString)", isDirectory: true)
		profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
	}

	override func tearDown() async throws {
		profileManager?.flushPendingSaves()
		profileManager = nil
		if let testConfigDirectory {
			try? FileManager.default.removeItem(at: testConfigDirectory)
		}
		testConfigDirectory = nil
		try await super.tearDown()
	}

	func testLastUsedProfileTogglesBetweenTwoProfiles() {
		let desktop = Profile(name: "Desktop")
		let gaming = Profile(name: "Gaming")
		profileManager.profiles = [desktop, gaming]

		profileManager.setActiveProfile(desktop)
		profileManager.setActiveProfile(gaming)
		XCTAssertEqual(profileManager.lastActiveProfileId, desktop.id)

		XCTAssertTrue(profileManager.navigateProfile(.lastUsed))
		XCTAssertEqual(profileManager.activeProfileId, desktop.id)
		XCTAssertEqual(profileManager.lastActiveProfileId, gaming.id)

		XCTAssertTrue(profileManager.navigateProfile(.lastUsed))
		XCTAssertEqual(profileManager.activeProfileId, gaming.id)
		XCTAssertEqual(profileManager.lastActiveProfileId, desktop.id)
	}

	func testSelectingActiveProfileDoesNotDestroyHistory() {
		let first = Profile(name: "First")
		let second = Profile(name: "Second")
		profileManager.profiles = [first, second]
		profileManager.setActiveProfile(first)
		profileManager.setActiveProfile(second)

		profileManager.setActiveProfile(second)

		XCTAssertEqual(profileManager.lastActiveProfileId, first.id)
		XCTAssertTrue(profileManager.navigateProfile(.lastUsed))
		XCTAssertEqual(profileManager.activeProfileId, first.id)
	}

	func testLastUsedProfileSurvivesRelaunch() {
		let desktop = Profile(name: "Desktop")
		let gaming = Profile(name: "Gaming")
		profileManager.profiles = [desktop, gaming]
		profileManager.setActiveProfile(desktop)
		profileManager.setActiveProfile(gaming)
		profileManager.flushPendingSaves()

		let reloadedManager = ProfileManager(configDirectoryOverride: testConfigDirectory)

		XCTAssertEqual(reloadedManager.activeProfileId, gaming.id)
		XCTAssertEqual(reloadedManager.lastActiveProfileId, desktop.id)
		XCTAssertTrue(reloadedManager.navigateProfile(.lastUsed))
		XCTAssertEqual(reloadedManager.activeProfileId, desktop.id)
		reloadedManager.flushPendingSaves()
	}

	func testNextAndPreviousFollowProfileOrderAndWrap() {
		let first = Profile(name: "First")
		let second = Profile(name: "Second")
		let third = Profile(name: "Third")
		profileManager.profiles = [first, second, third]
		profileManager.setActiveProfile(first)

		XCTAssertTrue(profileManager.navigateProfile(.previous))
		XCTAssertEqual(profileManager.activeProfileId, third.id)
		XCTAssertTrue(profileManager.navigateProfile(.next))
		XCTAssertEqual(profileManager.activeProfileId, first.id)
		XCTAssertTrue(profileManager.navigateProfile(.next))
		XCTAssertEqual(profileManager.activeProfileId, second.id)
	}

	func testNextAndPreviousUsePersistedSidebarOrderAfterRelaunch() {
		var first = Profile(name: "First")
		first.createdAt = Date(timeIntervalSince1970: 10)
		var second = Profile(name: "Second")
		second.createdAt = Date(timeIntervalSince1970: 20)
		var third = Profile(name: "Third")
		third.createdAt = Date(timeIntervalSince1970: 30)
		profileManager.profiles = [first, second, third]
		profileManager.setActiveProfile(second)
		profileManager.moveProfiles(from: IndexSet(integer: 0), to: 3)
		profileManager.flushPendingSaves()

		let reloadedManager = ProfileManager(configDirectoryOverride: testConfigDirectory)

		XCTAssertEqual(reloadedManager.profiles.map(\.id), [second.id, third.id, first.id])
		XCTAssertEqual(reloadedManager.activeProfileId, second.id)
		XCTAssertTrue(reloadedManager.navigateProfile(.next))
		XCTAssertEqual(reloadedManager.activeProfileId, third.id)
		XCTAssertTrue(reloadedManager.navigateProfile(.next))
		XCTAssertEqual(reloadedManager.activeProfileId, first.id)
		XCTAssertTrue(reloadedManager.navigateProfile(.previous))
		XCTAssertEqual(reloadedManager.activeProfileId, third.id)
		reloadedManager.flushPendingSaves()
	}

	func testNavigationNoOpsWithoutAValidDestination() {
		let only = Profile(name: "Only")
		profileManager.profiles = [only]
		profileManager.setActiveProfile(only)

		for action in ProfileNavigationAction.allCases {
			XCTAssertFalse(profileManager.navigateProfile(action))
			XCTAssertEqual(profileManager.activeProfileId, only.id)
		}
	}

	func testDeletingLastUsedProfileClearsHistory() {
		let first = Profile(name: "First")
		let second = Profile(name: "Second")
		let third = Profile(name: "Third")
		profileManager.profiles = [first, second, third]
		profileManager.setActiveProfile(second)
		profileManager.setActiveProfile(first)
		XCTAssertEqual(profileManager.lastActiveProfileId, second.id)

		profileManager.deleteProfile(second)

		XCTAssertNil(profileManager.lastActiveProfileId)
		XCTAssertFalse(profileManager.navigateProfile(.lastUsed))
		XCTAssertEqual(profileManager.activeProfileId, first.id)
	}

	func testResolverRejectsMissingActiveAndStaleHistory() {
		let first = Profile(name: "First")
		let second = Profile(name: "Second")
		let profiles = [first, second]

		XCTAssertNil(ProfileNavigationResolver.targetProfileId(
			for: .next,
			profiles: profiles,
			activeProfileId: UUID(),
			lastActiveProfileId: nil
		))
		XCTAssertNil(ProfileNavigationResolver.targetProfileId(
			for: .lastUsed,
			profiles: profiles,
			activeProfileId: first.id,
			lastActiveProfileId: UUID()
		))
		XCTAssertNil(ProfileNavigationResolver.targetProfileId(
			for: .lastUsed,
			profiles: profiles,
			activeProfileId: first.id,
			lastActiveProfileId: first.id
		))
	}
}

final class ProfileCommandSelectionTests: XCTestCase {
	func testSpecificProfileBuildsAndLoads() {
		let profileId = UUID()
		var selection = ProfileCommandSelection()
		XCTAssertNil(selection.systemCommand)

		selection.profileId = profileId
		selection.profileName = "Gaming"
		XCTAssertEqual(
			selection.systemCommand,
			.switchProfile(profileId: profileId, profileName: "Gaming")
		)

		var loaded = ProfileCommandSelection()
		loaded.load(.switchProfile(profileId: profileId, profileName: "Gaming"))
		XCTAssertEqual(loaded, selection)
	}

	func testNavigationActionsBuildAndLoad() {
		for action in ProfileNavigationAction.allCases {
			var selection = ProfileCommandSelection()
			selection.load(.navigateProfile(action))
			XCTAssertEqual(selection.systemCommand, .navigateProfile(action))
			XCTAssertNil(selection.profileId)
			XCTAssertNil(selection.profileName)
		}
	}
}

final class ProfileNavigationCodableTests: XCTestCase {
	private struct LegacyProfileCommand: Codable {
		let type: String
		let profileId: UUID?
		let profileName: String?
	}

	func testNavigationActionsRoundTripUsingLegacyTypeDiscriminator() throws {
		for action in ProfileNavigationAction.allCases {
			let command = SystemCommand.navigateProfile(action)
			let data = try JSONEncoder().encode(command)
			let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

			XCTAssertEqual(object["type"] as? String, "switchProfile")
			XCTAssertEqual(object["profileNavigation"] as? String, action.rawValue)
			XCTAssertEqual(object["profileId"] as? String, action.legacyRoundTripProfileId.uuidString)
			XCTAssertEqual(try JSONDecoder().decode(SystemCommand.self, from: data), command)
		}
	}

	func testNavigationActionsSurviveLegacyDecodeAndReencode() throws {
		for action in ProfileNavigationAction.allCases {
			let currentData = try JSONEncoder().encode(SystemCommand.navigateProfile(action))
			let legacyCommand = try JSONDecoder().decode(LegacyProfileCommand.self, from: currentData)
			let legacyResavedData = try JSONEncoder().encode(legacyCommand)

			XCTAssertEqual(
				try JSONDecoder().decode(SystemCommand.self, from: legacyResavedData),
				.navigateProfile(action)
			)
		}
	}

	func testUnknownNavigationActionDegradesToSpecificProfileSwitch() throws {
		let profileId = UUID()
		let data = try JSONSerialization.data(withJSONObject: [
			"type": "switchProfile",
			"profileId": profileId.uuidString,
			"profileNavigation": "futureNavigationAction"
		])

		XCTAssertEqual(
			try JSONDecoder().decode(SystemCommand.self, from: data),
			.switchProfile(profileId: profileId)
		)
	}
}

final class ProfileNavigationLocalizationTests: XCTestCase {
	func testProfileNavigationStringsExistInEverySupportedLocalization() throws {
		let keys = [
			"Profile Action",
			"Specific Profile",
			"Last Used Profile",
			"Next Profile",
			"Previous Profile",
			"Switches to the profile used immediately before this one. Assign it in both profiles to toggle between them.",
			"Switches to the next profile in sidebar order, wrapping at the end.",
			"Switches to the previous profile in sidebar order, wrapping at the beginning.",
		]
		let testBundle = Bundle(for: Self.self)
		let appBundleURL = testBundle.bundleURL
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let appBundle = try XCTUnwrap(
			Bundle(url: appBundleURL),
			"Missing host app bundle at \(appBundleURL.path)"
		)

		for localization in ["de", "ja", "zh-Hans", "zh-Hant"] {
			let path = try XCTUnwrap(
				appBundle.path(forResource: localization, ofType: "lproj"),
				"Missing \(localization) localization bundle"
			)
			let bundle = try XCTUnwrap(Bundle(path: path))
			for key in keys {
				XCTAssertNotEqual(
					bundle.localizedString(forKey: key, value: nil, table: nil),
					key,
					"\(localization) must translate \"\(key)\""
				)
			}
		}
	}
}
