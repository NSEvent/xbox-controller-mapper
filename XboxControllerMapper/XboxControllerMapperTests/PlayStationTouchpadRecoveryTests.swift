import XCTest
@preconcurrency import GameController
@testable import ControllerKeys

/// Replays the stale secondary contact captured from a hot-plugged DualSense
/// Edge. Uses the installed callbacks and mapping engine, with mock OS output.
final class PlayStationTouchpadRecoveryTests: MappingEngineTestCase {
	@MainActor
	private func installTouchpad() -> GCController {
		var profile = Profile(name: "Hot-plug touchpad", buttonMappings: [
			.touchpadButton: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true),
			.touchpadTwoFingerButton: KeyMapping(keyCode: KeyCodeMapping.mouseRightClick, isHoldModifier: true),
			.touchpadTap: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)
		])
		profile.joystickSettings.touchpadSmoothing = 0
		profile.joystickSettings.touchpadDeadzone = 0.00001
		profileManager.installTestProfile(profile)

		let controller = GCController.withExtendedGamepad()
		let pad = controller.extendedGamepad!
		controllerService.connectedController = controller
		controllerService.storage.lock.withLock {
			controllerService.storage.applyControllerTypeLocked(.dualSenseEdge)
			controllerService.storage.touchpadInputMode = .wholePad
		}
		// Snapshot controllers have no Sony touchpad, so use their two sticks
		// and A button as the three GameController elements to bind.
		controllerService.setupTouchpadHandlers(
			for: controller, primary: pad.leftThumbstick,
			secondary: pad.rightThumbstick, button: pad.buttonA
		)
		return controller
	}

	@MainActor
	private func leaveStaleSecondaryContact(on controller: GCController) async {
		let secondary = controller.extendedGamepad!.rightThumbstick
		secondary.valueChangedHandler!(secondary, -0.8, 0.8)
		secondary.valueChangedHandler!(secondary, -1, 1)
		// GameController touchpad callbacks reach storage through the main actor.
		await waitForTasks(0.1)
		controllerService.storage.lock.withLock {
			XCTAssertTrue(controllerService.storage.isTouchpadSecondaryTouching)
			controllerService.storage.touchpadSecondaryLastTouchTime = CFAbsoluteTimeGetCurrent() - 1
		}
		reportContacts(0)
	}

	@MainActor
	private func reportContacts(_ count: Int) {
		// Full Bluetooth report: contact bit 7 means NOT touching. The raw
		// report continues even when GameController stops changing an axis.
		var bytes = [UInt8](repeating: 0, count: 78)
		bytes[0] = 0x31
		bytes[34] = count > 0 ? 1 : 0x81
		bytes[38] = count > 1 ? 2 : 0x82
		bytes.withUnsafeMutableBufferPointer {
			controllerService.handleHIDReport(reportID: 0x31, report: $0.baseAddress!, length: $0.count)
		}
	}

	@MainActor
	private func swipe(on controller: GCController) {
		let primary = controller.extendedGamepad!.leftThumbstick
		for sample in 1...12 {
			primary.valueChangedHandler!(primary, Float(sample) * 0.06, 0.2)
		}
	}

	private var hasMouseMovement: Bool {
		mockInputSimulator.events.contains {
			if case .moveMouse(let dx, _) = $0 { return dx > 0 }
			return false
		}
	}

	@MainActor
	func testHotPlugStaleSecondaryContactRecoversMovementAndClick() async {
		let controller = installTouchpad()
		await leaveStaleSecondaryContact(on: controller)
		swipe(on: controller)
		let moved = await waitForCondition { self.hasMouseMovement }
		XCTAssertTrue(moved, "An old nonzero secondary position must not suppress every later swipe")

		let button = controller.extendedGamepad!.buttonA
		button.pressedChangedHandler!(button, 1, true)
		let clicked = await waitForCondition {
			self.mockInputSimulator.events.contains {
				if case .startHoldMapping(let mapping) = $0 {
					return mapping.keyCode == KeyCodeMapping.mouseLeftClick
				}
				return false
			}
		}
		XCTAssertTrue(clicked, "A single-finger click must still map to left mouse down")
		button.pressedChangedHandler!(button, 0, false)
		let released = await waitForCondition {
			self.mockInputSimulator.events.contains {
				if case .stopHoldMapping(let mapping) = $0 {
					return mapping.keyCode == KeyCodeMapping.mouseLeftClick
				}
				return false
			}
		}
		XCTAssertTrue(released)
		controllerService.clearGameControllerHandlers(for: controller)
	}

	@MainActor
	func testExpiredSecondaryEndsLatchedGestureBeforeMouseMovement() async {
		let controller = installTouchpad()
		swipe(on: controller)
		let secondary = controller.extendedGamepad!.rightThumbstick
		secondary.valueChangedHandler!(secondary, -0.8, 0.8)
		secondary.valueChangedHandler!(secondary, -1, 1)
		let gestureStarted = await waitForCondition {
			self.mappingEngine.state.lock.withLock { self.mappingEngine.state.isTouchpadGestureActive }
		}
		XCTAssertTrue(gestureStarted)
		mockInputSimulator.clearEvents()
		controllerService.storage.lock.withLock {
			controllerService.storage.touchpadSecondaryLastTouchTime = CFAbsoluteTimeGetCurrent() - 1
		}
		reportContacts(1)
		swipe(on: controller)
		let moved = await waitForCondition { self.hasMouseMovement }
		XCTAssertTrue(moved, "Recovery must also end the mapping engine's two-finger gesture latch")
		XCTAssertFalse(mappingEngine.state.lock.withLock { mappingEngine.state.isTouchpadGestureActive })
		controllerService.clearGameControllerHandlers(for: controller)
	}

	@MainActor
	func testFreshSecondaryContactStillOwnsTwoFingerGesture() async {
		let controller = installTouchpad()
		let primary = controller.extendedGamepad!.leftThumbstick
		primary.valueChangedHandler!(primary, 0.1, 0.2)
		primary.valueChangedHandler!(primary, 0.2, 0.2)
		let secondary = controller.extendedGamepad!.rightThumbstick
		secondary.valueChangedHandler!(secondary, -0.8, 0.8)
		secondary.valueChangedHandler!(secondary, -0.7, 0.7)
		swipe(on: controller)
		let gestureStarted = await waitForCondition {
			self.mappingEngine.state.lock.withLock { self.mappingEngine.state.isTouchpadGestureActive }
		}
		XCTAssertTrue(gestureStarted)
		XCTAssertFalse(hasMouseMovement, "A fresh two-finger gesture must not leak mouse movement")
		controllerService.clearGameControllerHandlers(for: controller)
	}

	@MainActor
	func testStationaryRealSecondFingerIsNotExpiredByAge() async {
		let controller = installTouchpad()
		reportContacts(2)
		let primary = controller.extendedGamepad!.leftThumbstick
		primary.valueChangedHandler!(primary, 0.1, 0.2)
		primary.valueChangedHandler!(primary, 0.2, 0.2)
		let secondary = controller.extendedGamepad!.rightThumbstick
		secondary.valueChangedHandler!(secondary, -0.8, 0.8)
		secondary.valueChangedHandler!(secondary, -0.7, 0.7)
		await waitForTasks(0.1)
		controllerService.storage.lock.withLock {
			controllerService.storage.touchpadSecondaryLastTouchTime = CFAbsoluteTimeGetCurrent() - 1
		}
		swipe(on: controller)
		await waitForTasks(0.1)
		XCTAssertTrue(controllerService.storage.lock.withLock { controllerService.storage.isTouchpadSecondaryTouching })
		XCTAssertFalse(hasMouseMovement, "Raw contact bits, not axis-change age, determine whether a real second finger lifted")
		controllerService.clearGameControllerHandlers(for: controller)
	}

	@MainActor
	func testNewSecondaryContactSurvivesEarlierNoContactReport() async {
		let controller = installTouchpad()
		reportContacts(0)
		let secondary = controller.extendedGamepad!.rightThumbstick
		secondary.valueChangedHandler!(secondary, -0.8, 0.8)
		secondary.valueChangedHandler!(secondary, -1, 1)
		// GC can deliver a new finger before the raw HID queue catches up.
		swipe(on: controller)
		await waitForTasks(0.1)
		XCTAssertTrue(controllerService.storage.lock.withLock { controllerService.storage.isTouchpadSecondaryTouching })
		reportContacts(2)
		await waitForTasks(0.1)
		XCTAssertFalse(hasMouseMovement)
		controllerService.clearGameControllerHandlers(for: controller)
	}

	@MainActor
	func testOldHIDReportCannotReleaseAStationarySecondFinger() async {
		let controller = installTouchpad()
		await leaveStaleSecondaryContact(on: controller)
		controllerService.storage.lock.withLock {
			controllerService.storage.dualSenseTouchpadContactTime = CFAbsoluteTimeGetCurrent() - 2
		}
		swipe(on: controller)
		await waitForTasks(0.1)
		XCTAssertTrue(controllerService.storage.lock.withLock { controllerService.storage.isTouchpadSecondaryTouching })
		controllerService.clearGameControllerHandlers(for: controller)
	}

	@MainActor
	func testRecoveryPreservesHeldTwoFingerClickRelease() async {
		let controller = installTouchpad()
		reportContacts(2)
		swipe(on: controller)
		let secondary = controller.extendedGamepad!.rightThumbstick
		secondary.valueChangedHandler!(secondary, -0.8, 0.8)
		secondary.valueChangedHandler!(secondary, -0.7, 0.7)
		let button = controller.extendedGamepad!.buttonA
		button.pressedChangedHandler!(button, 1, true)
		let pressed = await waitForCondition {
			self.mockInputSimulator.events.contains {
				if case .startHoldMapping(let mapping) = $0 { return mapping.keyCode == KeyCodeMapping.mouseRightClick }
				return false
			}
		}
		XCTAssertTrue(pressed)
		reportContacts(1)
		button.pressedChangedHandler!(button, 0, false)
		let released = await waitForCondition {
			self.mockInputSimulator.events.contains {
				if case .stopHoldMapping(let mapping) = $0 { return mapping.keyCode == KeyCodeMapping.mouseRightClick }
				return false
			}
		}
		XCTAssertTrue(released, "Recovery must not turn a held right click's release into a left-click release")
		controllerService.clearGameControllerHandlers(for: controller)
	}

	@MainActor
	func testConnectionResetClearsHardwareContactEvidence() {
		let controller = installTouchpad()
		reportContacts(0)
		controllerService.storage.lock.withLock {
			XCTAssertEqual(controllerService.storage.dualSenseTouchpadContactCount, 0)
			controllerService.resetTouchpadStateLocked()
			XCTAssertNil(controllerService.storage.dualSenseTouchpadContactCount)
		}
		controllerService.clearGameControllerHandlers(for: controller)
	}
}
