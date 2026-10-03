import XCTest
@testable import ControllerKeys

final class ControllerInputCaptureTests: XCTestCase {
	func testPreHeldButtonMustReleaseAndPressAgain() {
		var capture = ControllerInputCapture(mode: .button, initiallyHeld: [.a])
		XCTAssertNil(capture.receive([.a, .b]))
		XCTAssertNil(capture.receive([]))
		XCTAssertEqual(capture.receive([.b]), [.b])
		XCTAssertNil(capture.receive([.x]))
	}
	func testSequentialTapsAreNotAChord() {
		var capture = ControllerInputCapture(mode: .chord, initiallyHeld: [])
		XCTAssertNil(capture.receive([.a]))
		XCTAssertNil(capture.receive([]))
		XCTAssertNil(capture.receive([.b]))
		XCTAssertNil(capture.receive([]))
		XCTAssertEqual(capture.phase, .listening)
	}
	func testFourButtonChordUsesPeakOverlap() {
		var capture = ControllerInputCapture(mode: .chord, initiallyHeld: [])
		_ = capture.receive([.a, .b])
		_ = capture.receive([.a, .b, .x, .y])
		_ = capture.receive([.b, .x])
		XCTAssertEqual(capture.receive([]), [.a, .b, .x, .y])
	}
	func testCompetingChordsRequireRetry() {
		var capture = ControllerInputCapture(mode: .chord, initiallyHeld: [])
		_ = capture.receive([.a, .b])
		_ = capture.receive([.b])
		_ = capture.receive([.b, .x])
		XCTAssertNil(capture.receive([]))
		XCTAssertEqual(capture.phase, .ambiguous)
	}
	func testMotionGesturesCannotSelectPhysicalButton() {
		var capture = ControllerInputCapture(mode: .button, initiallyHeld: [])
		XCTAssertNil(capture.receive([.gestureTiltBack]))
		XCTAssertEqual(capture.receive([.a]), [.a])
	}
}

@MainActor
final class PhysicalInputCaptureSessionTests: MappingEngineTestCase {
	func testPhysicalCaptureSuppressesMappedOutputAndWaitsForRelease() async {
		profileManager.setActiveProfile(Profile(name: "Capture", buttonMappings: [.a: KeyMapping(keyCode: 0)]))
		controllerService.isConnected = true
		let session = PhysicalInputCaptureSession()
		session.start(mode: .button, controller: controllerService, engine: mappingEngine)
		mockInputSimulator.clearEvents()
		controllerService.buttonPressed(.a)
		await waitForTasks(0.1)
		XCTAssertEqual(session.result, [.a])
		XCTAssertFalse(mockInputSimulator.events.contains { if case .startHoldMapping = $0 { return true }; return false })
		session.cancel()
		XCTAssertEqual(mappingEngine.inputPreviewCount, 1)
		controllerService.buttonReleased(.a)
		await waitForTasks(0.15)
		XCTAssertEqual(mappingEngine.inputPreviewCount, 0)
		XCTAssertTrue(mappingEngine.isEnabled)
	}
	func testPreviewPreservesPausedAndLockedPreferences() async {
		mappingEngine.disable()
		mappingEngine.isLocked = true
		let first = mappingEngine.beginInputPreview()
		let second = mappingEngine.beginInputPreview()
		mappingEngine.endInputPreview(first)
		XCTAssertEqual(mappingEngine.inputPreviewCount, 1)
		mappingEngine.endInputPreview(second)
		XCTAssertEqual(mappingEngine.inputPreviewCount, 0)
		XCTAssertFalse(mappingEngine.isEnabled)
		XCTAssertTrue(mappingEngine.isLocked)
	}
	func testProfileChangeInvalidatesCapturedEditorContext() async {
		controllerService.isConnected = true
		let session = PhysicalInputCaptureSession()
		session.start(mode: .button, controller: controllerService, engine: mappingEngine)
		profileManager.setActiveProfile(Profile(name: "Other"))
		XCTAssertTrue(session.interrupted)
		XCTAssertFalse(session.isActive)
		XCTAssertNil(session.result)
	}
	func testRawObserverReceivesOverlapBeforeChordResolution() async {
		controllerService.isConnected = true
		let session = PhysicalInputCaptureSession()
		session.start(mode: .chord, controller: controllerService, engine: mappingEngine)
		controllerService.buttonPressed(.a)
		controllerService.buttonPressed(.b)
		controllerService.buttonPressed(.x)
		controllerService.buttonReleased(.a)
		controllerService.buttonReleased(.b)
		controllerService.buttonReleased(.x)
		await waitForTasks(0.1)
		XCTAssertEqual(session.result, [.a, .b, .x])
		session.cancel()
	}
}
