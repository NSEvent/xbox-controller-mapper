import XCTest
@testable import ControllerKeys

/// A new two-finger touch during momentum scrolling must end the momentum
/// stream before the new gesture begins, so apps never see a gesture start
/// while momentum is still open, and the next lift's momentum opens with `.begin`.
final class TouchpadMomentumInterruptTests: MappingEngineTestCase {
	func testNewGestureEndsRunningMomentum() async throws {
		await MainActor.run { profileManager.installTestProfile(Profile(name: "Touchpad")) }
		await waitForTasks(0.1)

		// Momentum scrolling in flight.
		let (engine, state, pollingQueue) = await MainActor.run {
			(mappingEngine!, mappingEngine.state, mappingEngine.pollingQueue)
		}
		let now = CFAbsoluteTimeGetCurrent()
		state.lock.withLock {
			state.touchpadMomentumWasActive = true
			state.touchpadMomentumVelocity = CGPoint(x: 0, y: 900)
			state.touchpadMomentumLastGestureTime = now
			state.touchpadMomentumLastUpdate = now
		}
		mockInputSimulator.clearEvents()

		let touch = TouchpadGesture(centerDelta: .zero, distanceDelta: 0, isPrimaryTouching: true, isSecondaryTouching: true)
		pollingQueue.sync { engine.processTouchpadGesture(touch) }

		let scrolls = mockInputSimulator.scrollEvents
		let endIndex = scrolls.firstIndex { $0.momentumPhase == .end }
		let beganIndex = scrolls.firstIndex { $0.phase == .began }
		XCTAssertNotNil(endIndex, "interrupted momentum must post momentumPhase .end: \(scrolls)")
		XCTAssertNotNil(beganIndex)
		if let endIndex, let beganIndex {
			XCTAssertLessThan(endIndex, beganIndex, "momentum must end before the new gesture begins")
		}
		XCTAssertFalse(state.lock.withLock { state.touchpadMomentumWasActive })
	}
}
