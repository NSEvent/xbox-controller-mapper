import XCTest
@testable import ControllerKeys

@MainActor
final class CommunityProfileImportBatchTests: XCTestCase {
	func testAeroSpaceCodexCommunityPresetSurvivesProductionImport() throws {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let source = try decoder.decode(Profile.self, from: Data(contentsOf:
			root.appendingPathComponent("community-profiles/AeroSpace & Codex.json")))
		let imported = ProfileTransferService.prepareForImport(source)
		XCTAssertNotEqual(imported.id, source.id)
		XCTAssertEqual(imported.layers.map(\.name), ["AeroSpace", "Codex"])
		XCTAssertEqual(imported.layers.map(\.activatorButton), [.leftTrigger, .rightTrigger])
		XCTAssertTrue(imported.layers.allSatisfy { $0.activationStyle == .hold })
		XCTAssertTrue(imported.linkedApps.isEmpty, "Window management must remain available across apps")
		XCTAssertEqual(imported.joystickSettings.leftStick.mode, .mouse)
		XCTAssertEqual(imported.joystickSettings.rightStick.mode, .scroll)
		XCTAssertTrue(imported.buttonMappings[.a]?.isHoldModifier == true)
		XCTAssertTrue(imported.buttonMappings[.leftBumper]?.isHoldModifier == true)
		for (original, layer) in zip(source.layers, imported.layers) {
			XCTAssertEqual(layer.buttonMappings, original.buttonMappings)
			XCTAssertEqual(layer.dualSenseLEDSettings, original.dualSenseLEDSettings)
			XCTAssertNil(layer.buttonMappings[layer.activatorButton!])
		}
		let codex = imported.layers[1]
		XCTAssertNil(codex.buttonMappings[.a], "Click/drag must fall through from base")
		XCTAssertNil(codex.buttonMappings[.x], "Return must fall through from base")
		XCTAssertEqual(codex.buttonMappings[.b]?.keyCode, 46)
		XCTAssertTrue(codex.buttonMappings[.b]?.hint?.contains("adapted") == true,
			"Model picker must not claim to reproduce an unverified cycle-reasoning shortcut")
		let roundTrip = try decoder.decode(Profile.self, from: {
			let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
			return try encoder.encode(imported)
		}())
		XCTAssertEqual(roundTrip.layers, imported.layers)
	}

	private func info(_ name: String) throws -> CommunityProfileInfo {
		let data = try JSONSerialization.data(withJSONObject: [
			"name": "\(name).json", "download_url": "https://example.invalid/\(name).json"
		])
		return try JSONDecoder().decode(CommunityProfileInfo.self, from: data)
	}

	func testSuccessfulImportDismissesAndReportsThePersistedIdentity() async throws {
		let entry = try info("Anki")
		let candidate = Profile(name: "Anki")
		var reported: [Profile] = []
		let result = await CommunityProfileImportBatch.run(
			[entry], fetch: { _ in candidate }, approve: { _, _ in true },
			persist: { ProfileTransferService.prepareForImport($0) },
			didImport: { _, profile in reported.append(profile) }
		)
		XCTAssertTrue(result.shouldDismiss)
		XCTAssertEqual(result.imported.count, 1)
		XCTAssertEqual(result.imported.first?.id, reported.first?.id)
		XCTAssertNotEqual(result.imported.first?.id, candidate.id)
	}

	func testOfflineFailureKeepsPickerOpenAndPreservesFailureName() async throws {
		let result = await CommunityProfileImportBatch.run(
			[try info("Anki")], fetch: { _ in throw URLError(.notConnectedToInternet) },
			approve: { _, _ in XCTFail("No downloaded profile to approve"); return true },
			persist: { profile in XCTFail("No downloaded profile to persist"); return profile },
			didImport: { _, _ in XCTFail("Must not report a failed import as success") }
		)
		XCTAssertFalse(result.shouldDismiss)
		XCTAssertTrue(result.imported.isEmpty)
		XCTAssertEqual(result.failures.map(\.profileName), ["Anki"])
		XCTAssertFalse(result.failures[0].message.isEmpty)
	}

	func testPartialFailureRetriesOnlyMissingProfiles() async throws {
		let entries = try [info("Anki"), info("Slides")]
		var importedIDs = Set<String>()
		var persistedNames: [String] = []
		let first = await CommunityProfileImportBatch.run(
			entries,
			fetch: { info in
				if info.displayName == "Slides" { throw URLError(.timedOut) }
				return Profile(name: info.displayName)
			}, approve: { _, _ in true },
			persist: { profile in persistedNames.append(profile.name); return profile },
			didImport: { info, _ in importedIDs.insert(info.id) }
		)
		XCTAssertFalse(first.shouldDismiss)
		XCTAssertEqual(first.imported.map(\.name), ["Anki"])
		XCTAssertEqual(first.failures.map(\.profileName), ["Slides"])
		let retry = await CommunityProfileImportBatch.run(
			entries.filter { !importedIDs.contains($0.id) },
			fetch: { Profile(name: $0.displayName) }, approve: { _, _ in true },
			persist: { profile in persistedNames.append(profile.name); return profile },
			didImport: { info, _ in importedIDs.insert(info.id) }
		)
		XCTAssertTrue(retry.shouldDismiss)
		XCTAssertEqual(persistedNames, ["Anki", "Slides"])
		XCTAssertEqual(importedIDs.count, 2)
	}

	func testSafetyDeclineNeverPersistsOrDismissesAsSuccess() async throws {
		let result = await CommunityProfileImportBatch.run(
			[try info("Scripts")], fetch: { Profile(name: $0.displayName) },
			approve: { _, name in XCTAssertEqual(name, "Scripts"); return false },
			persist: { profile in XCTFail("Declined profile must not be imported"); return profile },
			didImport: { _, _ in XCTFail("Decline is not success") }
		)
		XCTAssertFalse(result.shouldDismiss)
		XCTAssertEqual(result.declinedCount, 1)
		XCTAssertTrue(result.failures.isEmpty)
	}

	func testDeclinedProfileDoesNotHideASeparateSuccessfulImport() async throws {
		let result = await CommunityProfileImportBatch.run(
			try [info("Safe"), info("Scripts")], fetch: { Profile(name: $0.displayName) },
			approve: { _, name in name == "Safe" }, persist: { $0 }, didImport: { _, _ in }
		)
		XCTAssertEqual(result.imported.map(\.name), ["Safe"])
		XCTAssertEqual(result.declinedCount, 1)
		XCTAssertFalse(result.shouldDismiss)
	}

	func testDismissalDuringDownloadCannotInstallAfterThePickerIsGone() async throws {
		let entry = try info("Anki")
		var task: Task<CommunityProfileImportBatch.Result, Never>!
		task = Task { @MainActor in
			await CommunityProfileImportBatch.run(
				[entry],
				fetch: { _ in
					// A transport may return cached data despite cancellation.
					task.cancel()
					return Profile(name: "Anki")
				},
				approve: { _, _ in XCTFail("Cancelled download must not show an approval sheet"); return true },
				persist: { profile in XCTFail("Cancelled import mutated the library"); return profile },
				didImport: { _, _ in XCTFail("Cancelled import reported success") }
			)
		}
		let result = await task.value
		XCTAssertTrue(result.wasCancelled)
		XCTAssertFalse(result.shouldDismiss)
		XCTAssertTrue(result.imported.isEmpty)
	}

	func testDismissalDuringSafetyApprovalDoesNotInstallOrContinueTheBatch() async throws {
		let entries = try [info("Scripts"), info("Later")]
		var fetchCount = 0
		var task: Task<CommunityProfileImportBatch.Result, Never>!
		task = Task { @MainActor in
			await CommunityProfileImportBatch.run(
				entries,
				fetch: { info in fetchCount += 1; return Profile(name: info.displayName) },
				approve: { _, _ in task.cancel(); return true },
				persist: { profile in XCTFail("Approval completed after dismissal"); return profile },
				didImport: { _, _ in XCTFail("Cancelled import reported success") }
			)
		}
		let result = await task.value
		XCTAssertTrue(result.wasCancelled)
		XCTAssertTrue(result.imported.isEmpty)
		XCTAssertEqual(fetchCount, 1)
	}

	func testEmptyBatchIsNotACompletedImport() async {
		let result = await CommunityProfileImportBatch.run(
			[], fetch: { Profile(name: $0.displayName) }, approve: { _, _ in true },
			persist: { $0 }, didImport: { _, _ in }
		)
		XCTAssertFalse(result.shouldDismiss)
	}
}
