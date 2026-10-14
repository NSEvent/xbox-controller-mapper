import XCTest
import CoreGraphics
@testable import ControllerKeys

final class DoubleTapPressTimingTests: MappingEngineTestCase {
	func testUpSecondPressCancelsAppSwitchBeforeItsRelease() async throws {
		try await checkSecondPressHeldPastDeadline(button: .dpadUp, shift: false)
	}

	func testDownSecondPressCancelsAppSwitchAndPreservesShift() async throws {
		try await checkSecondPressHeldPastDeadline(button: .dpadDown, shift: true)
	}

	private func installMapping(button: ControllerButton, shift: Bool = false) async {
		await MainActor.run {
			let modifiers = ModifierFlags(command: true, shift: shift)
			profileManager.installTestProfile(Profile(name: "Remote tap timing", buttonMappings: [
				button: KeyMapping(keyCode: 48, modifiers: modifiers,
					doubleTapMapping: DoubleTapMapping(keyCode: 50, modifiers: modifiers, threshold: 0.25))
			]))
		}
		let engineState = await MainActor.run { mappingEngine.state }
		_ = await waitForCondition {
			engineState.lock.withLock { engineState.activeProfile?.name == "Remote tap timing" }
		}
		mockInputSimulator.clearEvents()
	}

	private func tap(_ button: ControllerButton) async {
		await MainActor.run {
			controllerService.buttonPressed(button)
			controllerService.buttonReleased(button)
		}
	}

	private func checkSecondPressHeldPastDeadline(button: ControllerButton, shift: Bool) async throws {
		await installMapping(button: button, shift: shift)
		await tap(button)
		let engineState = await MainActor.run { mappingEngine.state }
		let firstTapPending = await waitForCondition {
			engineState.lock.withLock { engineState.pendingSingleTap[button] != nil }
		}
		XCTAssertTrue(firstTapPending)
		await waitForTasks(0.06)
		await MainActor.run { controllerService.buttonPressed(button) }
		// The second DOWN is in time; its UP occurs after the first tap's deadline.
		await waitForTasks(0.4)
		let flags: CGEventFlags = shift ? [.maskCommand, .maskShift] : .maskCommand
		XCTAssertEqual(mockInputSimulator.events, [.pressKey(50, flags)],
			"Recognize the double on second press; never emit the app-switch fallback while held")
		await MainActor.run { controllerService.buttonReleased(button) }
		await waitForTasks(0.35)
		XCTAssertEqual(mockInputSimulator.events, [.pressKey(50, flags)],
			"Second release must not start a new single tap")
	}

	func testSingleTapStillSwitchesAppExactlyOnce() async {
		await installMapping(button: .dpadUp)
		await tap(.dpadUp)
		await waitForTasks(0.4)
		XCTAssertEqual(mockInputSimulator.events, [.pressKey(48, .maskCommand)])
	}

	func testPressAfterDeadlineStartsAnotherSingleTap() async {
		await installMapping(button: .dpadUp)
		await tap(.dpadUp)
		await waitForTasks(0.4)
		await tap(.dpadUp)
		await waitForTasks(0.4)
		XCTAssertEqual(mockInputSimulator.events, [
			.pressKey(48, .maskCommand), .pressKey(48, .maskCommand)
		])
	}
}
