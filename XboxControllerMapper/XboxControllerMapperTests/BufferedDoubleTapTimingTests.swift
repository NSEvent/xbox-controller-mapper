import XCTest
import CoreGraphics
@testable import ControllerKeys

@MainActor
final class BufferedDoubleTapTimingTests: MappingEngineTestCase {
	private func install(_ button: ControllerButton = .dpadUp, shift: Bool = false,
		chord: Bool = false, realtime: Bool = false) async {
		await MainActor.run {
			controllerService.chordWindow = 0.15
			let flags = ModifierFlags(command: true, shift: shift)
			var profile = Profile(name: "Buffered tap timing", buttonMappings: [
				button: KeyMapping(keyCode: 48, modifiers: flags,
					doubleTapMapping: DoubleTapMapping(keyCode: 50, modifiers: flags, threshold: 0.25))
			])
			profile.inputLatencyMode = realtime ? .realtime : .standard
			if chord { profile.chordMappings = [ChordMapping(buttons: [button, .b], keyCode: 3)] }
			profileManager.installTestProfile(profile)
		}
		let state = await MainActor.run { mappingEngine.state }
		let ready = await waitForCondition {
			state.lock.withLock { state.activeProfile?.name == "Buffered tap timing" }
		}
		XCTAssertTrue(ready)
		mockInputSimulator.clearEvents()
	}

	private func firstTap(_ button: ControllerButton = .dpadUp) async {
		await MainActor.run { controllerService.buttonPressed(button) }
		await waitForTasks(0.2) // First press is resolved before the physical release.
		await MainActor.run { controllerService.buttonReleased(button) }
		let state = await MainActor.run { mappingEngine.state }
		let pending = await waitForCondition {
			state.lock.withLock { state.pendingSingleTap[button] != nil }
		}
		XCTAssertTrue(pending)
	}

	func testUpNearDeadlineSurvivesChordBuffer() async {
		await checkBufferedSecondPress(.dpadUp, shift: false)
	}

	func testDownNearDeadlineSurvivesChordBufferAndKeepsShift() async {
		await checkBufferedSecondPress(.dpadDown, shift: true)
	}

	private func checkBufferedSecondPress(_ button: ControllerButton, shift: Bool) async {
		await install(button, shift: shift)
		await firstTap(button)
		await waitForTasks(0.18)
		let state = await MainActor.run { mappingEngine.state }
		let gap = state.lock.withLock { CFAbsoluteTimeGetCurrent() - (state.lastTapTime[button] ?? 0) }
		XCTAssertLessThan(gap, 0.25, "Physical second press must be in time")
		await MainActor.run { controllerService.buttonPressed(button) }
		await waitForTasks(0.22)
		await MainActor.run { controllerService.buttonReleased(button) }
		await waitForTasks(0.4)
		let flags: CGEventFlags = shift ? [.maskCommand, .maskShift] : .maskCommand
		XCTAssertEqual(mockInputSimulator.events, [.pressKey(50, flags)])
	}

	func testChordWinsOverReservedDoubleTap() async { await checkChordWins(realtime: false) }
	func testRealtimeChordWinsOverReservedDoubleTap() async { await checkChordWins(realtime: true) }

	private func checkChordWins(realtime: Bool) async {
		await install(.a, chord: true, realtime: realtime)
		await firstTap(.a)
		await waitForTasks(0.18)
		await MainActor.run { controllerService.buttonPressed(.a) }
		await waitForTasks(0.02)
		await MainActor.run { controllerService.buttonPressed(.b) }
		XCTAssertTrue(mockInputSimulator.events.isEmpty, "Reservation cannot emit an action before chord resolution")
		await waitForTasks(0.2)
		await MainActor.run {
			controllerService.buttonReleased(.a)
			controllerService.buttonReleased(.b)
		}
		await waitForTasks(0.35)
		XCTAssertEqual(mockInputSimulator.events, [.pressKey(3, [])])
	}

	func testFastFlushWithDelayedQueueUsesPhysicalTimes() async {
		await install()
		let first = CFAbsoluteTimeGetCurrent() - 1
		await MainActor.run {
			// Fast double-tap flushing can announce DOWN #2 before tap #1's
			// buffered callbacks reach the engine. Both are already old here.
			controllerService.emitInputEvent(.buttonPressed(.dpadUp), timing: .physicalPressBegan(first + 0.2))
			controllerService.emitInputEvent(.buttonPressed(.dpadUp), timing: .resolved(first))
			controllerService.emitInputEvent(.buttonReleased(.dpadUp, holdDuration: 0.02), timing: .resolved(first + 0.02))
			controllerService.emitInputEvent(.buttonPressed(.dpadUp), timing: .resolved(first + 0.2))
			controllerService.emitInputEvent(.buttonReleased(.dpadUp, holdDuration: 0.02), timing: .resolved(first + 0.22))
		}
		await waitForTasks(0.15)
		XCTAssertEqual(mockInputSimulator.events, [.pressKey(50, .maskCommand)])
	}

	func testGenuinelyLateTapRemainsTwoSinglesAfterQueueDelay() async {
		await install()
		let first = CFAbsoluteTimeGetCurrent() - 1
		await MainActor.run {
			controllerService.emitInputEvent(.buttonPressed(.dpadUp), timing: .physicalPressBegan(first + 0.4))
			controllerService.emitInputEvent(.buttonPressed(.dpadUp), timing: .resolved(first))
			controllerService.emitInputEvent(.buttonReleased(.dpadUp, holdDuration: 0.02), timing: .resolved(first + 0.02))
			controllerService.emitInputEvent(.buttonPressed(.dpadUp), timing: .resolved(first + 0.4))
			controllerService.emitInputEvent(.buttonReleased(.dpadUp, holdDuration: 0.02), timing: .resolved(first + 0.42))
		}
		await waitForTasks(0.15)
		XCTAssertEqual(mockInputSimulator.events, [.pressKey(48, .maskCommand), .pressKey(48, .maskCommand)])
	}

	func testDisableClearsReservationWithoutOutput() async {
		await install()
		await firstTap()
		await MainActor.run { controllerService.buttonPressed(.dpadUp) }
		let state = await MainActor.run { mappingEngine.state }
		let reserved = await waitForCondition {
			state.lock.withLock { state.pendingDoubleTapPressTime[.dpadUp] != nil }
		}
		XCTAssertTrue(reserved)
		await MainActor.run {
			mappingEngine.disable()
			controllerService.buttonReleased(.dpadUp)
		}
		await waitForTasks(0.45)
		XCTAssertTrue(mockInputSimulator.events.filter {
			if case .pressKey = $0 { return true }; return false
		}.isEmpty)
		XCTAssertTrue(state.lock.withLock { state.pendingDoubleTapPressTime.isEmpty && state.unresolvedPhysicalTapPresses.isEmpty })
	}

	func testHoldRepeatAndLongHoldKeepExistingTimingPaths() {
		let mapping = KeyMapping(keyCode: 48, doubleTapMapping: DoubleTapMapping(keyCode: 50))
		XCTAssertTrue(MappingEngine.usesPhysicalDoubleTapTiming(mapping))
		var held = mapping; held.isHoldModifier = true
		XCTAssertFalse(MappingEngine.usesPhysicalDoubleTapTiming(held))
		var repeated = mapping; repeated.repeatMapping = RepeatMapping(enabled: true)
		XCTAssertFalse(MappingEngine.usesPhysicalDoubleTapTiming(repeated))
		var longHeld = mapping; longHeld.longHoldMapping = LongHoldMapping(keyCode: 1)
		XCTAssertFalse(MappingEngine.usesPhysicalDoubleTapTiming(longHeld))
	}

	func testProfileSwitchDiscardsBufferedOldPressButAllowsNewTap() async {
		await install()
		await firstTap()
		await MainActor.run { controllerService.buttonPressed(.dpadUp) }
		let state = await MainActor.run { mappingEngine.state }
		let reserved = await waitForCondition {
			state.lock.withLock { state.pendingDoubleTapPressTime[.dpadUp] != nil }
		}
		XCTAssertTrue(reserved)
		await MainActor.run {
			profileManager.installTestProfile(Profile(name: "New context", buttonMappings: [.dpadUp: KeyMapping(keyCode: 9)]))
		}
		await waitForTasks(0.2)
		await MainActor.run { controllerService.buttonReleased(.dpadUp) }
		await waitForTasks(0.35)
		XCTAssertTrue(mockInputSimulator.events.filter {
			if case .pressKey = $0 { return true }; return false
		}.isEmpty, "Buffered press from the old profile cannot become an action in the new profile")
		await MainActor.run {
			controllerService.buttonPressed(.dpadUp)
			controllerService.buttonReleased(.dpadUp)
		}
		await waitForTasks(0.35)
		XCTAssertEqual(mockInputSimulator.events.filter {
			if case .pressKey = $0 { return true }; return false
		}, [.pressKey(9, [])])
		XCTAssertTrue(state.lock.withLock { state.physicalTapPressOwners.isEmpty })
	}

	func testLockUnlockCannotReviveAReservedOldPress() async {
		await install()
		await firstTap()
		await MainActor.run { controllerService.buttonPressed(.dpadUp) }
		let state = await MainActor.run { mappingEngine.state }
		let reserved = await waitForCondition {
			state.lock.withLock { state.pendingDoubleTapPressTime[.dpadUp] != nil }
		}
		XCTAssertTrue(reserved)
		XCTAssertTrue(mappingEngine.performLockToggle())
		XCTAssertFalse(mappingEngine.performLockToggle())
		await waitForTasks(0.2)
		await MainActor.run { controllerService.buttonReleased(.dpadUp) }
		await waitForTasks(0.35)
		XCTAssertTrue(mockInputSimulator.events.filter {
			if case .pressKey = $0 { return true }; return false
		}.isEmpty)
	}
}
