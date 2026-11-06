import XCTest
import Carbon.HIToolbox
@testable import ControllerKeys

/// Releases that happen while an overlay owns the d-pad or after a lock must
/// still clear the press state they started, or keys and overlays stay stuck.
final class OverlayReleaseCleanupTests: MappingEngineTestCase {

	override func tearDown() async throws {
		await MainActor.run {
			OnScreenKeyboardManager.shared.hide()
			CommandWheelManager.shared.hide()
		}
		try await super.tearDown()
	}

	func testHeldDpadMappingStopsWhenReleasedWhileKeyboardIsVisible() async throws {
		let heldMapping = KeyMapping(keyCode: CGKeyCode(kVK_ANSI_W), isHoldModifier: true)
		let profile = Profile(
			name: "HeldDpad",
			buttonMappings: [
				.dpadUp: heldMapping,
				.y: KeyMapping(keyCode: KeyCodeMapping.showOnScreenKeyboard)
			]
		)
		await MainActor.run { profileManager.installTestProfile(profile) }

		await MainActor.run { controllerService.buttonPressed(.dpadUp) }
		await waitForTasks(0.1)
		await MainActor.run {
			controllerService.buttonPressed(.y)
			controllerService.buttonReleased(.y)
		}
		let keyboardShown = await waitForMain { OnScreenKeyboardManager.shared.isVisible }
		XCTAssertTrue(keyboardShown)

		await MainActor.run { controllerService.buttonReleased(.dpadUp) }
		await waitForTasks(0.2)

		let stillHeld = await MainActor.run {
			let state = mappingEngine.state
			return state.lock.withLock {
				state.heldButtons[.dpadUp] != nil
					|| state.holdRepeatTimers[.dpadUp] != nil
					|| state.longHoldTimers[.dpadUp] != nil
			}
		}
		XCTAssertFalse(stillHeld, "release under the keyboard must clear the held d-pad state")
		XCTAssertTrue(mockInputSimulator.events.contains(.stopHoldMapping(heldMapping)),
			"the held key must be released, not left down")
	}

	func testLockClearsHeldCommandWheelSoReleaseCannotActivateIt() async throws {
		var profile = Profile(
			name: "Wheel",
			buttonMappings: [
				.y: KeyMapping(keyCode: KeyCodeMapping.showCommandWheel, isHoldModifier: true)
			]
		)
		profile.commandWheelActions = [CommandWheelAction(displayName: "Return", keyCode: CGKeyCode(kVK_Return))]
		await MainActor.run { profileManager.installTestProfile(profile) }

		await MainActor.run { controllerService.buttonPressed(.y) }
		let wheelShown = await waitForMain { CommandWheelManager.shared.isVisible }
		XCTAssertTrue(wheelShown)

		_ = await MainActor.run { mappingEngine.performLockToggle() }
		await waitForTasks(0.2)

		let wheelState = await MainActor.run {
			let state = mappingEngine.state
			return state.lock.withLock { (state.commandWheelButton, state.commandWheelActive) }
		}
		XCTAssertNil(wheelState.0, "lock must drop the wheel's owning button")
		XCTAssertFalse(wheelState.1)
		let wheelVisible = await MainActor.run { CommandWheelManager.shared.isVisible }
		XCTAssertFalse(wheelVisible, "lock must hide the command wheel")
	}

	private func waitForMain(timeout: TimeInterval = 3.0, _ condition: @escaping @MainActor () -> Bool) async -> Bool {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			if await MainActor.run(body: condition) { return true }
			try? await Task.sleep(nanoseconds: 10_000_000)
		}
		return await MainActor.run(body: condition)
	}
}
