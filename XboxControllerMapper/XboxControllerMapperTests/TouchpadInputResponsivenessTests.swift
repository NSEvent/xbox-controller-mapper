import XCTest
@preconcurrency import GameController
@testable import ControllerKeys

final class TouchpadInputResponsivenessTests: XCTestCase {
	/// Exercise the installed GameController callback while the UI thread is
	/// occupied (as during keyboard layout). No real controller or mouse events.
	@MainActor
	func testTouchpadMovementDoesNotWaitForMainActor() {
		let service = ControllerService(enableHardwareMonitoring: false)
		let controller = GCController.withExtendedGamepad()
		let gamepad = controller.extendedGamepad!
		service.connectedController = controller
		service.storage.lock.withLock {
			service.storage.applyControllerTypeLocked(.dualSense)
		}
		service.setupTouchpadHandlers(
			for: controller,
			primary: gamepad.leftThumbstick,
			secondary: gamepad.rightThumbstick,
			button: gamepad.buttonA
		)
		service.activeTouchpadRouting.activate(ObjectIdentifier(controller))
		defer {
			service.activeTouchpadRouting.invalidate()
			service.clearGameControllerHandlers(for: controller)
			service.onInputEvent = nil
			service.cleanup()
		}

		XCTAssertTrue(controller.handlerQueue === service.controllerQueue)
		let moved = DispatchSemaphore(value: 0)
		service.onInputEvent = { event in
			if case .touchpadMoved(let delta) = event, delta.x > 0 {
				moved.signal()
			}
		}
		let primary = gamepad.leftThumbstick
		let callback = primary.valueChangedHandler!
		controller.handlerQueue.async {
			// Include idle-sentinel detection, touch-start settling, and the
			// pending-delta filter before expecting movement to be emitted.
			for sample in 1...10 {
				callback(primary, Float(sample) / 10, 0.2)
			}
			callback(primary, 0, 0)
		}

		// Intentionally block the main actor. A route through Task @MainActor
		// cannot deliver input until this wait ends and must fail this test.
		XCTAssertEqual(moved.wait(timeout: .now() + 1), .success)
	}

	func testOnlyActiveControllerCanUpdateAndNeutralSamplesStillFlow() {
		let router = ActiveTouchpadRouting()
		let active = NSObject()
		let inactive = NSObject()
		router.activate(ObjectIdentifier(active))
		var updates = 0

		XCTAssertFalse(router.performIfActive(ObjectIdentifier(inactive), meaningful: true, now: 10) {
			updates += 1
		})
		XCTAssertTrue(router.performIfActive(ObjectIdentifier(active), meaningful: true, now: 20) {
			updates += 1
		})
		XCTAssertTrue(router.performIfActive(ObjectIdentifier(active), meaningful: false, now: 30) {
			updates += 1
		})
		XCTAssertEqual(updates, 2, "Finger-lift and click-release samples must not be dropped")
		XCTAssertEqual(router.lastActivity, 20)
		XCTAssertFalse(ControllerService.shouldActivateInactiveControllerInput(
			meaningful: true, activeControllerHasInput: false,
			activeControllerLastInputTime: router.lastActivity, now: 20.5, quietInterval: 0.75
		))
	}

	func testControllerSwitchRejectsOldSamplesAndResetsActivity() {
		let router = ActiveTouchpadRouting()
		let old = NSObject()
		let new = NSObject()
		router.activate(ObjectIdentifier(old))
		XCTAssertTrue(router.performIfActive(ObjectIdentifier(old), meaningful: true, now: 20) {})
		router.invalidate()
		XCTAssertEqual(router.lastActivity, 0)
		XCTAssertFalse(router.performIfActive(ObjectIdentifier(old), meaningful: true) {
			XCTFail("Disconnected input must not update state")
		})
		router.activate(ObjectIdentifier(new))
		XCTAssertFalse(router.performIfActive(ObjectIdentifier(old), meaningful: true) {
			XCTFail("Old controller must not update the new controller's state")
		})
		XCTAssertTrue(router.performIfActive(ObjectIdentifier(new), meaningful: false) {})
	}

	func testInvalidationWaitsForInFlightSampleBeforeClearingState() {
		let router = ActiveTouchpadRouting()
		let controller = NSObject()
		let controllerID = ObjectIdentifier(controller)
		router.activate(controllerID)
		let entered = DispatchSemaphore(value: 0)
		let release = DispatchSemaphore(value: 0)
		let invalidated = DispatchSemaphore(value: 0)
		let finished = DispatchSemaphore(value: 0)

		DispatchQueue.global().async {
			_ = router.performIfActive(controllerID, meaningful: true) {
				entered.signal()
				_ = release.wait(timeout: .now() + 2)
			}
			finished.signal()
		}
		XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)
		DispatchQueue.global().async {
			router.invalidate()
			invalidated.signal()
		}
		XCTAssertEqual(invalidated.wait(timeout: .now() + 0.05), .timedOut)
		release.signal()
		XCTAssertEqual(finished.wait(timeout: .now() + 1), .success)
		XCTAssertEqual(invalidated.wait(timeout: .now() + 1), .success)
		XCTAssertFalse(router.performIfActive(controllerID, meaningful: true) {})
	}

	@MainActor
	func testClearingConnectedControllerInvalidatesTouchpadRoute() {
		let service = ControllerService(enableHardwareMonitoring: false)
		let controller = GCController.withExtendedGamepad()
		service.connectedController = controller
		service.activeTouchpadRouting.activate(ObjectIdentifier(controller))
		service.connectedController = nil
		XCTAssertFalse(service.activeTouchpadRouting.performIfActive(
			ObjectIdentifier(controller), meaningful: true
		) {})
		service.cleanup()
	}
}
