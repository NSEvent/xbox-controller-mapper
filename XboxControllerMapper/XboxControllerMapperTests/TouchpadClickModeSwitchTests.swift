import XCTest
@testable import ControllerKeys

/// A touchpad click must release the button its press dispatched even when
/// the touchpad input mode changes mid-click (e.g. the click switches profile).
@MainActor
final class TouchpadClickModeSwitchTests: XCTestCase {
	private var controllerService: ControllerService!

	override func setUp() async throws {
		try await super.setUp()
		controllerService = ControllerService(enableHardwareMonitoring: false)
		controllerService.chordWindow = 0.05
	}

	override func tearDown() async throws {
		controllerService?.cleanup()
		controllerService = nil
		try await super.tearDown()
	}

	private func setMode(_ mode: TouchpadInputMode) {
		controllerService.storage.lock.withLock { controllerService.storage.touchpadInputMode = mode }
	}

	private func activeButtons() -> Set<ControllerButton> {
		controllerService.storage.lock.withLock { controllerService.storage.activeButtons }
	}

	func testWholePadClickReleasesAfterSwitchToQuadrants() async {
		setMode(.wholePad)
		controllerService.updateTouchpadClick(pressed: true)
		let pressed = await waitForCondition { self.activeButtons().contains(.touchpadButton) }
		XCTAssertTrue(pressed)

		setMode(.quadrants)
		controllerService.updateTouchpadClick(pressed: false)
		let released = await waitForCondition { !self.activeButtons().contains(.touchpadButton) }
		XCTAssertTrue(released, "the whole-pad click must still be released after the mode change")
	}

	func testRegionClickReleasesAfterSwitchToWholePad() async throws {
		setMode(.quadrants)
		controllerService.storage.lock.withLock {
			controllerService.storage.isTouchpadTouching = true
			controllerService.storage.touchpadPosition = CGPoint(x: 0.5, y: 0.5)
			controllerService.storage.touchpadTouchStartPosition = CGPoint(x: 0.5, y: 0.5)
		}
		controllerService.updateTouchpadClick(pressed: true)
		let regionButton = try XCTUnwrap(
			controllerService.storage.lock.withLock { controllerService.storage.activeTouchpadClickButton }
		)
		let pressed = await waitForCondition { self.activeButtons().contains(regionButton) }
		XCTAssertTrue(pressed)

		setMode(.wholePad)
		controllerService.updateTouchpadClick(pressed: false)
		let released = await waitForCondition { !self.activeButtons().contains(regionButton) }
		XCTAssertTrue(released, "the region click must still be released after the mode change")
		XCTAssertFalse(activeButtons().contains(.touchpadButton))
	}
}
