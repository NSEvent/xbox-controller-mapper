import XCTest
import CoreGraphics
@testable import ControllerKeys

/// Release actions: the primary fires on press, the release action fires once
/// when the button comes up, and routing boundaries never fire a stray release.
final class ReleaseActionTests: MappingEngineTestCase {
	private let keyC: CGKeyCode = 8
	private let keyX: CGKeyCode = 7

	private func pressKeyCount(_ keyCode: CGKeyCode) -> Int {
		mockInputSimulator.events.filter {
			if case .pressKey(let code, _) = $0 { return code == keyCode }
			return false
		}.count
	}

	@MainActor
	private func install(_ profile: Profile) async {
		await MainActor.run {
			profileManager.profiles = [profile]
			profileManager.setActiveProfile(profile)
		}
		let ready = await waitForCondition {
			self.mappingEngine.state.lock.withLock {
				self.mappingEngine.state.activeProfile?.id == profile.id
			}
		}
		XCTAssertTrue(ready, "Profile did not settle")
	}

	private func toggleProfile(mode: InputLatencyMode = .standard) -> Profile {
		Profile(
			name: "Toggle",
			buttonMappings: [.a: KeyMapping(keyCode: keyC, releaseMapping: ReleaseMapping(keyCode: keyC))],
			inputLatencyMode: mode
		)
	}

	// MARK: - Engine

	func testSameKeyFiresOncePerEdgeThroughChordWindow() async throws {
		await install(toggleProfile())

		await MainActor.run { controllerService.buttonPressed(.a) }
		let pressed = await waitForCondition { self.pressKeyCount(self.keyC) == 1 }
		XCTAssertTrue(pressed, "Primary should fire while the button is still held")
		await waitForTasks(0.15)
		XCTAssertEqual(pressKeyCount(keyC), 1, "Holding must not send anything else")

		await MainActor.run { controllerService.buttonReleased(.a) }
		let released = await waitForCondition { self.pressKeyCount(self.keyC) == 2 }
		XCTAssertTrue(released, "Release should send the key a second time")
		await waitForTasks(0.15)
		XCTAssertEqual(pressKeyCount(keyC), 2, "Exactly one key per edge")
	}

	func testReleaseCanSendDifferentAction() async throws {
		await install(Profile(
			name: "Different",
			buttonMappings: [.a: KeyMapping(keyCode: keyC, releaseMapping: ReleaseMapping(keyCode: keyX))]
		))

		await MainActor.run { controllerService.emitInputEvent(.buttonPressed(.a)) }
		let pressed = await waitForCondition { self.pressKeyCount(self.keyC) == 1 }
		XCTAssertTrue(pressed)
		XCTAssertEqual(pressKeyCount(keyX), 0)

		await MainActor.run { controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.4)) }
		let released = await waitForCondition { self.pressKeyCount(self.keyX) == 1 }
		XCTAssertTrue(released)
		XCTAssertEqual(pressKeyCount(keyC), 1, "Primary must not repeat on release")
	}

	func testRealtimeModeTapsOnPressInsteadOfHolding() async throws {
		await install(toggleProfile(mode: .realtime))

		await MainActor.run { controllerService.emitInputEvent(.buttonPressed(.a)) }
		let pressed = await waitForCondition { self.pressKeyCount(self.keyC) == 1 }
		XCTAssertTrue(pressed)
		XCTAssertFalse(mockInputSimulator.events.contains {
			if case .startHoldMapping = $0 { return true }
			return false
		}, "A release action keeps the primary a tap so the pair cannot overlap")

		await MainActor.run { controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.4)) }
		let released = await waitForCondition { self.pressKeyCount(self.keyC) == 2 }
		XCTAssertTrue(released)
	}

	func testHeldPrimaryStopsBeforeReleaseAction() async throws {
		await install(Profile(
			name: "Held",
			buttonMappings: [.a: KeyMapping(
				modifiers: ModifierFlags(shift: true),
				releaseMapping: ReleaseMapping(keyCode: keyX),
				isHoldModifier: true
			)]
		))

		await MainActor.run { controllerService.emitInputEvent(.buttonPressed(.a)) }
		let held = await waitForCondition {
			self.mockInputSimulator.events.contains {
				if case .startHoldMapping = $0 { return true }
				return false
			}
		}
		XCTAssertTrue(held)

		await MainActor.run { controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.4)) }
		let released = await waitForCondition { self.pressKeyCount(self.keyX) == 1 }
		XCTAssertTrue(released)

		let events = mockInputSimulator.events
		let stopIndex = events.firstIndex {
			if case .stopHoldMapping = $0 { return true }
			return false
		}
		let releaseIndex = events.firstIndex {
			if case .pressKey(let code, _) = $0 { return code == keyX }
			return false
		}
		XCTAssertNotNil(stopIndex)
		XCTAssertLessThan(try XCTUnwrap(stopIndex), try XCTUnwrap(releaseIndex))
	}

	@MainActor
	func testDisconnectWhileHeldDropsReleaseAction() async throws {
		await install(toggleProfile())

		await MainActor.run { controllerService.emitInputEvent(.buttonPressed(.a)) }
		let pressed = await waitForCondition { self.pressKeyCount(self.keyC) == 1 }
		XCTAssertTrue(pressed)

		await MainActor.run {
			controllerService.emitInputEvent(.controllerDisconnected)
			controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.4))
		}
		await waitForTasks(0.2)
		XCTAssertEqual(pressKeyCount(keyC), 1, "A disconnect must not fire a stray release action")
		XCTAssertTrue(mappingEngine.state.lock.withLock { mappingEngine.state.armedReleaseActions.isEmpty })
	}

	func testProfileSwitchWhileHeldDropsReleaseAction() async throws {
		await install(toggleProfile())

		await MainActor.run { controllerService.emitInputEvent(.buttonPressed(.a)) }
		let pressed = await waitForCondition { self.pressKeyCount(self.keyC) == 1 }
		XCTAssertTrue(pressed)

		let other = Profile(name: "Other", buttonMappings: [.a: .key(keyX)])
		await install(other)
		await MainActor.run { controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.4)) }
		await waitForTasks(0.2)

		XCTAssertEqual(pressKeyCount(keyC), 1, "The old profile's release action must not fire")
		XCTAssertEqual(pressKeyCount(keyX), 0, "The release must not run the new profile's mapping either")
	}

	func testLongHoldDisablesReleaseAction() async throws {
		var mapping = KeyMapping(keyCode: keyC, releaseMapping: ReleaseMapping(keyCode: keyX))
		mapping.longHoldMapping = LongHoldMapping(keyCode: 2, threshold: 1.0)
		await install(Profile(name: "Conflict", buttonMappings: [.a: mapping]))

		await MainActor.run { controllerService.emitInputEvent(.buttonPressed(.a)) }
		await waitForTasks(0.1)
		XCTAssertEqual(pressKeyCount(keyC), 0, "Long hold keeps the existing fire-on-release behavior")

		await MainActor.run { controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.05)) }
		let tapped = await waitForCondition { self.pressKeyCount(self.keyC) == 1 }
		XCTAssertTrue(tapped)
		XCTAssertEqual(pressKeyCount(keyX), 0)
	}

	@MainActor
	func testLockAndUnlockWhileHeldDoesNotReplayPrimary() async throws {
		await install(Profile(
			name: "Lock",
			buttonMappings: [.a: KeyMapping(keyCode: keyC, releaseMapping: ReleaseMapping(keyCode: keyX))]
		))

		controllerService.emitInputEvent(.buttonPressed(.a))
		let pressed = await waitForCondition { self.pressKeyCount(self.keyC) == 1 }
		XCTAssertTrue(pressed)

		XCTAssertTrue(mappingEngine.performLockToggle())
		XCTAssertFalse(mappingEngine.performLockToggle())
		controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.4))
		await waitForTasks(0.2)

		XCTAssertEqual(pressKeyCount(keyC), 1, "Unlocking mid-hold must not replay the primary as a tap")
		XCTAssertEqual(pressKeyCount(keyX), 0, "The lock dropped the armed release action")
	}

	@MainActor
	func testLockReleaseActionCanUnlockAgain() async throws {
		await install(Profile(
			name: "Lock Toggle",
			buttonMappings: [.a: KeyMapping(keyCode: keyC, releaseMapping: ReleaseMapping(keyCode: KeyCodeMapping.controllerLock))]
		))

		controllerService.emitInputEvent(.buttonPressed(.a))
		controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.1))
		let locked = await waitForCondition { self.mappingEngine.state.lock.withLock { self.mappingEngine.state.isLocked } }
		XCTAssertTrue(locked, "Releasing should lock the controller")

		controllerService.emitInputEvent(.buttonPressed(.a))
		controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.1))
		let unlocked = await waitForCondition { !self.mappingEngine.state.lock.withLock { self.mappingEngine.state.isLocked } }
		XCTAssertTrue(unlocked, "The same button's release should unlock it")
		XCTAssertEqual(pressKeyCount(keyC), 1, "The primary must not fire while locked")
	}

	func testDPadPresetDirectionWithReleaseActionTaps() {
		let mapping = KeyMapping(keyCode: KeyCodeMapping.leftArrow, releaseMapping: ReleaseMapping(keyCode: 7))
		XCTAssertFalse(ButtonInteractionFlowPolicy.shouldUseHoldPath(
			button: .dpadLeft,
			mapping: mapping,
			isChordPart: false,
			isDPadPresetDirection: true
		))
	}

	// MARK: - Model

	func testEffectiveReleaseMappingYieldsToResolveOnReleaseFeatures() {
		let release = ReleaseMapping(keyCode: keyC)
		XCTAssertEqual(KeyMapping(keyCode: keyC, releaseMapping: release).effectiveReleaseMapping, release)
		XCTAssertNil(KeyMapping(keyCode: keyC, longHoldMapping: LongHoldMapping(keyCode: 1), releaseMapping: release).effectiveReleaseMapping)
		XCTAssertNil(KeyMapping(keyCode: keyC, doubleTapMapping: DoubleTapMapping(keyCode: 1), releaseMapping: release).effectiveReleaseMapping)
		XCTAssertNil(KeyMapping(
			keyCode: keyC,
			releaseMapping: release,
			repeatMapping: RepeatMapping(enabled: true, interval: 0.2)
		).effectiveReleaseMapping)
		XCTAssertNil(KeyMapping(keyCode: keyC, releaseMapping: ReleaseMapping()).effectiveReleaseMapping)
		XCTAssertTrue(KeyMapping(releaseMapping: release).hasConfiguredBehavior, "Release-only mappings count as mapped")
	}

	func testCodableRoundTripAndLegacyDecode() throws {
		let mapping = KeyMapping(keyCode: keyC, releaseMapping: ReleaseMapping(keyCode: keyX, hint: "Back to brush"))
		let decoded = try JSONDecoder().decode(KeyMapping.self, from: JSONEncoder().encode(mapping))
		XCTAssertEqual(decoded, mapping)

		let legacy = try JSONDecoder().decode(KeyMapping.self, from: Data(#"{"keyCode": 8}"#.utf8))
		XCTAssertNil(legacy.releaseMapping)
	}

	func testDeletingMacroClearsReleaseReference() {
		let targetId = UUID()
		let profile = Profile(
			name: "Work",
			buttonMappings: [.a: KeyMapping(keyCode: keyC, releaseMapping: ReleaseMapping(macroId: targetId))],
			macros: [Macro(id: targetId, name: "Target")]
		)

		XCTAssertEqual(ProfileAutomationReferencePolicy.report(for: targetId, kind: .macro, in: profile).count, 1)
		let cleaned = ProfileAutomationReferencePolicy.removingReferences(to: targetId, kind: .macro, from: profile)
		XCTAssertNil(cleaned.buttonMappings[.a]?.releaseMapping)
		XCTAssertEqual(cleaned.buttonMappings[.a]?.keyCode, keyC)
	}
}
