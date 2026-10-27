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
		let first = CFAbsoluteTimeGetCurrent() - 1
		await MainActor.run {
			// Replay a recorded in-time second press. Scheduler load must not
			// turn a 60 ms fixture gap into a genuinely late physical press.
			controllerService.emitInputEvent(.buttonPressed(button), timing: .physicalPressBegan(first + 0.08))
			controllerService.emitInputEvent(.buttonPressed(button), timing: .resolved(first))
			controllerService.emitInputEvent(.buttonReleased(button, holdDuration: 0.02), timing: .resolved(first + 0.02))
			controllerService.emitInputEvent(.buttonPressed(button), timing: .resolved(first + 0.08))
		}
		let flags: CGEventFlags = shift ? [.maskCommand, .maskShift] : .maskCommand
		let recognized = await waitForCondition {
			self.mockInputSimulator.events == [.pressKey(50, flags)]
		}
		XCTAssertTrue(recognized, "Recognize the double on second press")
		await waitForTasks(0.4)
		XCTAssertEqual(mockInputSimulator.events, [.pressKey(50, flags)],
			"Never emit the app-switch fallback while the second press is held")
		await MainActor.run {
			controllerService.emitInputEvent(.buttonReleased(button, holdDuration: 0.72), timing: .resolved(first + 0.8))
		}
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
