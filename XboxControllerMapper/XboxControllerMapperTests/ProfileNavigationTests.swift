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
		profileManager = nil
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
	func testNavigationActionsRoundTripUsingLegacyTypeDiscriminator() throws {
		for action in ProfileNavigationAction.allCases {
			let command = SystemCommand.navigateProfile(action)
			let data = try JSONEncoder().encode(command)
			let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

			XCTAssertEqual(object["type"] as? String, "switchProfile")
			XCTAssertEqual(object["profileNavigation"] as? String, action.rawValue)
			XCTAssertNil(object["profileId"])
			XCTAssertEqual(try JSONDecoder().decode(SystemCommand.self, from: data), command)
		}
	}
}
