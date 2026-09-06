import XCTest
import CoreGraphics
@testable import ControllerKeys

/// Production community JSON → import → foreground selection → controller input
/// → mapped output → disconnect/relaunch. No Anki account, deck, or real input.
@MainActor
final class AnkiFirstSessionTests: MappingEngineTestCase {
	private let modernAnkiID = "net.ankiweb.anki" // Official 26.08.1 macOS bundle.
	private let launcherAnkiID = "net.ankiweb.launcher"

	private func communityProfile(_ name: String = "Anki Flashcards") throws -> Profile {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let url = root.appendingPathComponent("community-profiles/\(name).json")
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try decoder.decode(Profile.self, from: Data(contentsOf: url))
	}

	private func connectAppMonitor() {
		mappingEngine.shutdown()
		appMonitor.frontmostBundleId = "com.apple.finder"
		profileManager = ProfileManager(appMonitor: appMonitor, configDirectoryOverride: testConfigDirectory)
		profileManager.setupControllerAutoSwitching(with: controllerService)
		mappingEngine = MappingEngine(
			controllerService: controllerService, profileManager: profileManager,
			appMonitor: appMonitor, inputSimulator: mockInputSimulator, midiService: mockMIDIService
		)
		mockInputSimulator.clearEvents()
	}

	private func importAndSelect(_ name: String = "Anki Flashcards") throws -> Profile {
		let imported = profileManager.importFetchedProfile(try communityProfile(name))
		profileManager.setActiveProfile(imported) // Same completion action as the picker.
		return imported
	}

	private func expectTap(_ button: ControllerButton, keyCode: CGKeyCode) async {
		mockInputSimulator.clearEvents()
		controllerService.buttonPressed(button)
		controllerService.buttonReleased(button)
		let output = await waitForCondition { [self] in
			mockInputSimulator.events.contains(.pressKey(keyCode, []))
		}
		XCTAssertTrue(output, "\(button) must produce key \(keyCode), not a default-profile action")
		await waitForTasks(0.08)
		XCTAssertEqual(mockInputSimulator.events.filter {
			if case .pressKey = $0 { return true }; return false
		}, [.pressKey(keyCode, [])], "One tap must not grade two cards")
	}

	func testBothShippedAnkiProfilesRecognizeCurrentAndLauncherApps() throws {
		for name in ["Anki Flashcards", "Anki - AnKing (USMLE)"] {
			let profile = try communityProfile(name)
			for bundleID in [modernAnkiID, launcherAnkiID] {
				XCTAssertTrue(profile.linkedApps.contains(bundleID), "\(name) misses \(bundleID)")
				let result = ProfileAutoSwitchResolver.resolve(
					bundleId: bundleID, appBundleId: "com.controllerkeys.app",
					profiles: [Profile.createDefault(), profile],
					state: ProfileAutoSwitchState(previousBundleId: nil,
						profileIdBeforeBackground: nil, activeProfileId: nil)
				)
				XCTAssertEqual(result.action?.profileId, profile.id)
			}
		}
	}

	func testImportThenOpenCurrentAnkiProducesShowAnswerAndRatings() async throws {
		connectAppMonitor()
		let profile = try importAndSelect()
		appMonitor.frontmostBundleId = modernAnkiID
		XCTAssertEqual(profileManager.activeProfileId, profile.id)
		await expectTap(.a, keyCode: 49) // Space: show answer / Good.
		await expectTap(.b, keyCode: 18) // 1: Again.
		await expectTap(.x, keyCode: 19) // 2: Hard.
		await expectTap(.y, keyCode: 21) // 4: Easy.
	}

	func testAnKingCoreReviewWorksWithoutOptionalTemplateAdditions() async throws {
		connectAppMonitor()
		let profile = try importAndSelect("Anki - AnKing (USMLE)")
		appMonitor.frontmostBundleId = modernAnkiID
		XCTAssertEqual(profileManager.activeProfileId, profile.id)
		await expectTap(.a, keyCode: 36) // Enter: show answer / Good.
		await expectTap(.x, keyCode: 18)
		await expectTap(.b, keyCode: 19)
		await expectTap(.y, keyCode: 21)
	}

	func testAnkiSelectionSurvivesDisconnectAndFirstTapAfterReconnect() async throws {
		connectAppMonitor()
		let profile = try importAndSelect()
		appMonitor.frontmostBundleId = launcherAnkiID
		let identity = ControllerIdentity(stableId: "fixture-pad", fallbackId: "fixture")
		controllerService.currentControllerIdentity = identity
		await expectTap(.a, keyCode: 49)
		controllerService.emitInputEvent(.controllerDisconnected)
		controllerService.currentControllerIdentity = nil
		await waitForTasks(0.1)
		controllerService.currentControllerIdentity = identity
		XCTAssertEqual(profileManager.activeProfileId, profile.id)
		await expectTap(.a, keyCode: 49)
	}

	func testImportedMappingsAndAppLinksSurviveRelaunch() async throws {
		connectAppMonitor()
		let imported = try importAndSelect()
		profileManager.flushPendingSaves()
		connectAppMonitor() // Recreate the production manager/engine from disk.
		XCTAssertEqual(profileManager.activeProfileId, imported.id)
		XCTAssertEqual(profileManager.activeProfile?.buttonMappings, imported.buttonMappings)
		XCTAssertEqual(profileManager.activeProfile?.linkedApps, imported.linkedApps)
		appMonitor.frontmostBundleId = launcherAnkiID
		await expectTap(.a, keyCode: 49)
	}

	func testChoosingBasicAnkiAfterImportingAnKingKeepsTheChosenBindings() async throws {
		connectAppMonitor()
		_ = try importAndSelect("Anki - AnKing (USMLE)")
		let selected = try importAndSelect("Anki Flashcards")
		appMonitor.frontmostBundleId = launcherAnkiID
		XCTAssertEqual(profileManager.activeProfileId, selected.id,
			"Import order must not override an explicit choice between two Anki profiles")
		await expectTap(.b, keyCode: 18) // Basic B = Again; AnKing B = Hard.
		appMonitor.frontmostBundleId = "com.apple.finder"
		appMonitor.frontmostBundleId = launcherAnkiID
		XCTAssertEqual(profileManager.activeProfileId, selected.id,
			"Returning from another app must keep the selected Anki variant")
	}

	func testPreviewMuteAndResumeDoNotReplayAButtonHeldAcrossExit() async throws {
		_ = try importAndSelect()
		mappingEngine.disable()
		controllerService.buttonPressed(.a)
		await waitForTasks(0.15)
		XCTAssertFalse(mockInputSimulator.events.contains(.pressKey(49, [])))
		mappingEngine.enable()
		controllerService.buttonReleased(.a)
		await waitForTasks(Config.chordReleaseProcessingDelay + 0.3)
		XCTAssertFalse(mockInputSimulator.events.contains(.pressKey(49, [])),
			"A press begun in safe preview must not grade a card on exit")
		await expectTap(.a, keyCode: 49)
	}

	func testChosenAnkiVariantSurvivesRelaunchWhileDefaultProfileIsActive() async throws {
		connectAppMonitor()
		_ = try importAndSelect("Anki - AnKing (USMLE)")
		let selected = try importAndSelect("Anki Flashcards")
		appMonitor.frontmostBundleId = modernAnkiID
		appMonitor.frontmostBundleId = "com.apple.finder"
		XCTAssertTrue(profileManager.activeProfile?.isDefault == true)
		profileManager.flushPendingSaves()
		connectAppMonitor()
		appMonitor.frontmostBundleId = modernAnkiID
		XCTAssertEqual(profileManager.activeProfileId, selected.id)
		await expectTap(.b, keyCode: 18)
	}

	func testPreviewExitConsumesAPressStillInTheControllerChordWindow() async throws {
		_ = try importAndSelect()
		controllerService.chordWindow = 0.3
		mappingEngine.disable()
		controllerService.buttonPressed(.a)
		mappingEngine.enable()
		controllerService.buttonReleased(.a)
		await waitForTasks(0.3 + Config.chordReleaseProcessingDelay + 0.3)
		XCTAssertFalse(mockInputSimulator.events.contains(.pressKey(49, [])))
		await expectTap(.a, keyCode: 49)
	}

	func testPreviewExitConsumesACompletedTapStillInTheControllerChordWindow() async throws {
		_ = try importAndSelect()
		controllerService.chordWindow = 0.3
		mappingEngine.disable()
		controllerService.buttonPressed(.a)
		controllerService.buttonReleased(.a)
		mappingEngine.enable()
		await waitForTasks(0.3 + Config.chordReleaseProcessingDelay + 0.3)
		XCTAssertFalse(mockInputSimulator.events.contains(.pressKey(49, [])))
		await expectTap(.a, keyCode: 49)
	}

	func testPauseResumeDiscardsInputAlreadyQueuedBeforePause() async throws {
		_ = try importAndSelect()
		mappingEngine.inputQueue.suspend()
		controllerService.emitInputEvent(.buttonPressed(.a))
		controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.05))
		mappingEngine.disable()
		mappingEngine.enable()
		mappingEngine.inputQueue.resume()
		await waitForTasks(Config.chordReleaseProcessingDelay + 0.3)
		XCTAssertFalse(mockInputSimulator.events.contains(.pressKey(49, [])))
		await expectTap(.a, keyCode: 49)
	}

	func testPreviewExitDiscardsInputQueuedWhileMuted() async throws {
		_ = try importAndSelect()
		mappingEngine.disable()
		mappingEngine.inputQueue.suspend()
		controllerService.emitInputEvent(.buttonPressed(.a))
		controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.05))
		mappingEngine.enable()
		mappingEngine.inputQueue.resume()
		await waitForTasks(Config.chordReleaseProcessingDelay + 0.3)
		XCTAssertFalse(mockInputSimulator.events.contains(.pressKey(49, [])))
		await expectTap(.a, keyCode: 49)
	}

	func testExportsActualMappedKeysForOptionalAnkiOracle() async throws {
		connectAppMonitor()
		var trace: [[String: Any]] = []
		for name in ["Anki Flashcards", "Anki - AnKing (USMLE)"] {
			_ = try importAndSelect(name)
			appMonitor.frontmostBundleId = modernAnkiID
			let expected: [ControllerButton: CGKeyCode] = name == "Anki Flashcards"
				? [.a: 49, .b: 18, .x: 19, .y: 21, .rightBumper: 20]
				: [.a: 36, .b: 19, .x: 18, .y: 21] // AnKing RB is a layer, not Good.
			for button in [ControllerButton.a, .b, .x, .y, .rightBumper] {
				guard let keyCode = expected[button] else { continue }
				await expectTap(button, keyCode: keyCode)
				let keys = mockInputSimulator.events.compactMap { event -> Int? in
					if case let .pressKey(code, modifiers) = event, modifiers.isEmpty {
						return Int(code)
					}
					return nil
				}
				trace.append(["profile": name, "button": button.rawValue, "keyCodes": keys])
			}
		}
		if let path = ProcessInfo.processInfo.environment["CONTROLLERKEYS_ANKI_KEY_TRACE"] {
			try JSONSerialization.data(withJSONObject: trace, options: [.prettyPrinted, .sortedKeys])
				.write(to: URL(fileURLWithPath: path))
		}
	}

	override func tearDown() async throws {
		await MainActor.run {
			mappingEngine?.shutdown()
			profileManager?.flushPendingSaves()
		}
		try await super.tearDown()
	}
}
