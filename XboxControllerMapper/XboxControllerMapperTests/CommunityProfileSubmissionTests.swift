import Foundation
import XCTest
@testable import ControllerKeys

final class CommunityProfileSubmissionTests: XCTestCase {
	private let details = CommunityProfileSubmissionDetails(name: "Anki on DualSense", summary: "Review cards", controller: "DualSense, Bluetooth", instructions: "Open a card; press Cross to reveal the answer.")

	func testSharingCreatesIndependentCopyWithoutDefaultOrInheritance() throws {
		var source = Profile(name: "My private default")
		source.isDefault = true
		source.inheritedOnScreenKeyboardProfileId = UUID()
		source.linkedApps = ["net.ankiweb.anki"]
		source.buttonMappings[.a] = KeyMapping(keyCode: 49)
		let before = source
		let id = UUID(), date = Date(timeIntervalSince1970: 1234)
		let result = try CommunityProfileSubmission.prepare(profile: source, details: details, now: date, id: id)
		XCTAssertEqual(source, before)
		XCTAssertEqual(result.profile.id, id)
		XCTAssertNotEqual(result.profile.id, source.id)
		XCTAssertFalse(result.profile.isDefault)
		XCTAssertTrue(result.profile.linkedControllers.isEmpty)
		XCTAssertNil(result.profile.inheritedOnScreenKeyboardProfileId)
		XCTAssertEqual(result.profile.linkedApps, source.linkedApps)
		XCTAssertEqual(result.profile.buttonMappings[.a]?.keyCode, 49)
		XCTAssertEqual(result.profile.createdAt, date)
	}

	func testDefaultCopyRemovesNestedCommandsWithoutUnmaskingDormantKeys() throws {
		var source = Profile(name: "Commands")
		source.buttonMappings[.a] = KeyMapping(keyCode: 0,
			longHoldMapping: LongHoldMapping(systemCommand: .httpRequest(url: "https://example.com", headers: ["Authorization": "private"])),
			doubleTapMapping: DoubleTapMapping(keyCode: 49), systemCommand: .shellCommand(command: "secret-command", inTerminal: false))
		source.layers = [Layer(name: "Private", activatorButton: .leftTrigger, buttonMappings: [.b: KeyMapping(systemCommand: .runShortcut(name: "Private shortcut"))])]
		source.chordMappings = [ChordMapping(buttons: [.x, .y], systemCommand: .obsWebSocket(url: "ws://192.168.1.2", password: "password", requestType: "Test"))]
		let result = try CommunityProfileSubmission.prepare(profile: source, details: details)
		let json = String(decoding: result.json, as: UTF8.self)
		for privateValue in ["secret-command", "Authorization", "192.168.1.2", "Private shortcut"] { XCTAssertFalse(json.contains(privateValue)) }
		XCTAssertNil(result.profile.buttonMappings[.a]?.systemCommand)
		XCTAssertNil(result.profile.buttonMappings[.a]?.keyCode, "Removing a command must not activate its dormant key")
		XCTAssertEqual(result.profile.buttonMappings[.a]?.doubleTapMapping?.keyCode, 49)
		XCTAssertFalse(ProfileImportSafetyAuditor.audit(result.profile).requiresUserConfirmation)
	}

	func testDefaultOmitsMacrosScriptsAndCustomKeyboardData() throws {
		var source = Profile(name: "Automations")
		let macro = Macro(name: "Private text", steps: [.typeText("private@example.com", speed: 0)])
		source.macros = [macro]
		source.buttonMappings[.a] = KeyMapping(keyCode: 0, macroId: macro.id)
		source.onScreenKeyboardSettings = OnScreenKeyboardSettings(quickTexts: [QuickText(text: "secret")], defaultTerminalApp: "/Users/private/Terminal")
		let result = try CommunityProfileSubmission.prepare(profile: source, details: details)
		XCTAssertTrue(result.profile.macros.isEmpty)
		XCTAssertTrue(result.profile.scripts.isEmpty)
		XCTAssertTrue(result.profile.sharedMacroSnapshots.isEmpty)
		XCTAssertNil(result.profile.buttonMappings[.a]?.macroId)
		XCTAssertNil(result.profile.buttonMappings[.a]?.keyCode)
		XCTAssertTrue(result.profile.onScreenKeyboardSettings.quickTexts.isEmpty)
		XCTAssertFalse(String(decoding: result.json, as: UTF8.self).contains("private@example.com"))
	}

	func testCustomActionsRequireReviewAndLocalProfileTargetsStillOmitted() throws {
		var source = Profile(name: "Custom")
		source.buttonMappings[.a] = KeyMapping(systemCommand: .shellCommand(command: "echo /Users/private/file", inTerminal: false))
		source.buttonMappings[.b] = KeyMapping(keyCode: 0, systemCommand: .switchProfile(profileId: UUID(), profileName: "Other private profile"))
		let result = try CommunityProfileSubmission.prepare(profile: source, details: details, includeCustomActions: true)
		XCTAssertEqual(result.profile.buttonMappings[.a]?.systemCommand, source.buttonMappings[.a]?.systemCommand)
		XCTAssertFalse(result.reviewFields.isEmpty)
		XCTAssertNil(result.profile.buttonMappings[.b]?.systemCommand)
		XCTAssertNil(result.profile.buttonMappings[.b]?.keyCode)
	}

	func testDraftContainsDescriptionButNeverProfilePayloadOrPermissionParameters() throws {
		var input = details
		input.name = "Anki & study #1"
		input.summary = "Hello @somebody <script>"
		var source = Profile(name: "Source")
		source.buttonMappings[.a] = KeyMapping(keyCode: 49, hint: "Private local label")
		let result = try CommunityProfileSubmission.prepare(profile: source, details: input)
		let components = try XCTUnwrap(URLComponents(url: result.issueURL, resolvingAgainstBaseURL: false))
		XCTAssertEqual(components.host, "github.com")
		XCTAssertEqual(components.path, "/NSEvent/xbox-controller-mapper/issues/new")
		XCTAssertEqual(Set(components.queryItems!.map(\.name)), ["title", "body"])
		XCTAssertEqual(components.queryItems?.first { $0.name == "body" }?.value, result.issueBody)
		XCTAssertFalse(result.issueBody.contains("@somebody"))
		XCTAssertFalse(result.issueBody.contains("<script>"))
		XCTAssertFalse(result.issueURL.absoluteString.contains("Private%20local%20label"))
		XCTAssertLessThanOrEqual(result.issueURL.absoluteString.utf8.count, 8000)
	}

	func testPublicMetadataAndMappingLabelsReceivePrivateFieldReminders() throws {
		var source = Profile(name: "Source")
		source.buttonMappings[.a] = KeyMapping(keyCode: 49, hint: "alice@example.com")
		var input = details
		input.instructions = "token=private"
		let result = try CommunityProfileSubmission.prepare(profile: source, details: input)
		XCTAssertTrue(result.reviewFields.contains("description.instructions"))
		XCTAssertTrue(result.reviewFields.contains { $0.contains("hint") })
	}

	func testPacketUsesFreshDirectoryAndImportableFiles() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		var input = details
		input.name = "../../Study/Setup"
		let result = try CommunityProfileSubmission.prepare(profile: Profile(name: "Source"), details: input)
		let first = try CommunityProfileSubmissionFiles.write(result, to: directory)
		let second = try CommunityProfileSubmissionFiles.write(result, to: directory)
		XCTAssertNotEqual(first.directory, second.directory)
		XCTAssertEqual(first.profileURL.deletingLastPathComponent(), first.directory)
		XCTAssertEqual(try Data(contentsOf: first.profileURL), result.json)
		XCTAssertEqual(try String(contentsOf: first.guideURL, encoding: .utf8), result.guide)
		let imported = try ProfileTransferService.importProfile(from: first.profileURL)
		XCTAssertEqual(imported.name, input.name)
		XCTAssertFalse(imported.isDefault)
	}

	func testIncompleteAndOversizedDetailsDoNotPrepare() {
		XCTAssertThrowsError(try CommunityProfileSubmission.prepare(profile: Profile(name: "Source"), details: .init(name: "")))
		var input = details
		input.instructions = String(repeating: "a", count: 1501)
		XCTAssertThrowsError(try CommunityProfileSubmission.prepare(profile: Profile(name: "Source"), details: input))
	}

	func testExistingCommunityProfilesRemainDecodableAfterSharingPreparation() throws {
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let directory = root.appendingPathComponent("community-profiles")
		let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
		XCTAssertGreaterThan(files.count, 30)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		for file in files {
			let original = try decoder.decode(Profile.self, from: Data(contentsOf: file))
			let result = try CommunityProfileSubmission.prepare(profile: original, details: details)
			let copy = try decoder.decode(Profile.self, from: result.json)
			XCTAssertEqual(copy.name, details.name, file.lastPathComponent)
			XCTAssertFalse(copy.isDefault, file.lastPathComponent)
			XCTAssertFalse(ProfileImportSafetyAuditor.audit(copy).requiresUserConfirmation, file.lastPathComponent)
		}
	}

	func testIncludedWebhookCredentialsAreFlaggedWithoutEchoingTheirValue() throws {
		var source = Profile(name: "Webhook")
		source.buttonMappings[.a] = KeyMapping(systemCommand: .httpRequest(url: "https://example.com", headers: ["Authorization": "opaque-value"]))
		let result = try CommunityProfileSubmission.prepare(profile: source, details: details, includeCustomActions: true)
		XCTAssertTrue(result.reviewFields.contains { $0.hasSuffix(".Authorization") })
		XCTAssertFalse(result.reviewFields.contains { $0.contains("opaque-value") })
	}

	func testOBSSharingOmitsCredentialsInCommandsAndMacros() throws {
		var source = Profile(name: "OBS")
		source.buttonMappings[.a] = KeyMapping(systemCommand: .obsWebSocket(url: "ws://example.com", password: "private-password", requestType: "GetVersion"))
		source.macros = [Macro(name: "OBS", steps: [.obsWebSocket(url: "ws://example.com", password: "macro-password", requestType: "GetVersion", requestData: nil)])]
		let result = try CommunityProfileSubmission.prepare(profile: source, details: details, includeCustomActions: true)
		let json = String(decoding: result.json, as: UTF8.self)
		XCTAssertFalse(json.contains("private-password"))
		XCTAssertFalse(json.contains("macro-password"))
		XCTAssertFalse(json.contains("\"password\""))
		XCTAssertEqual(result.profile.buttonMappings[.a]?.systemCommand, .obsWebSocket(url: "ws://example.com", password: nil, requestType: "GetVersion"))
	}
}
