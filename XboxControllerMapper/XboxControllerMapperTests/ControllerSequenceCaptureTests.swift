import XCTest
@testable import ControllerKeys

final class ControllerSequenceCaptureTests: XCTestCase {
	func testRepeatedTapRecordsTwiceAndHeldInputNeverRepeats() {
		var capture = ControllerSequenceCapture(initiallyHeld: [])
		capture.receive([.a]); capture.receive([.a]); capture.receive([])
		capture.receive([.a]); capture.receive([]); capture.receive([.b])
		XCTAssertEqual(capture.steps, [.a, .a, .b])
	}
	func testPreHeldButtonsMustReleaseBeforeRecording() {
		var capture = ControllerSequenceCapture(initiallyHeld: [.a])
		capture.receive([.a, .b]); capture.receive([]); capture.receive([.x])
		XCTAssertEqual(capture.steps, [.x])
	}
	func testSimultaneousPressDoesNotInventOrder() {
		var capture = ControllerSequenceCapture(initiallyHeld: [])
		capture.receive([.a]); capture.receive([]); capture.receive([.b, .x])
		capture.receive([]); capture.receive([.y])
		XCTAssertTrue(capture.ambiguous)
		XCTAssertEqual(capture.steps, [.a])
	}
	func testStaggeredOverlappingPressPreservesOrder() {
		var capture = ControllerSequenceCapture(initiallyHeld: [], limit: 3)
		capture.receive([.a]); capture.receive([.a, .b]); capture.receive([.a, .b, .x])
		capture.receive([]); capture.receive([.y])
		XCTAssertEqual(capture.steps, [.a, .b, .x])
	}
	func testGestureAndStickNoiseCannotBecomeSequenceSteps() {
		var capture = ControllerSequenceCapture(initiallyHeld: [])
		capture.receive([.gestureTiltBack, .a]); capture.receive([])
		XCTAssertEqual(capture.steps, [.a])
	}
}

@MainActor
final class PhysicalSequenceSessionTests: MappingEngineTestCase {
	func testRecordingPausesOutputAndKeepsOrderUntilEditorCloses() async {
		controllerService.isConnected = true
		let session = PhysicalInputCaptureSession()
		session.start(mode: .sequence, controller: controllerService, engine: mappingEngine)
		defer { session.cancel() }
		controllerService.buttonPressed(.b); controllerService.buttonReleased(.b)
		controllerService.buttonPressed(.a); controllerService.buttonReleased(.a)
		controllerService.buttonPressed(.b); controllerService.buttonReleased(.b)
		await waitForTasks(0.1)
		XCTAssertEqual(session.sequence?.steps, [.b, .a, .b])
		session.finishSequence()
		XCTAssertEqual(session.sequenceResult, [.b, .a, .b])
		XCTAssertFalse(session.isListening)
		XCTAssertGreaterThan(mappingEngine.inputPreviewCount, 0)
		controllerService.buttonPressed(.x); controllerService.buttonReleased(.x)
		await waitForTasks(0.05)
		XCTAssertEqual(session.sequenceResult, [.b, .a, .b])
	}
	func testReviewHighlightsPhysicalOverlapAndStopsObservingOnClose() async {
		let lease = mappingEngine.beginInputPreview()
		defer { mappingEngine.endInputPreview(lease) }
		let review = PhysicalButtonReviewSession()
		review.start(controller: controllerService)
		controllerService.buttonPressed(.a); controllerService.buttonPressed(.b)
		await waitForTasks(0.05)
		XCTAssertEqual(review.held, [.a, .b]); XCTAssertEqual(review.seen, [.a, .b])
		controllerService.buttonReleased(.a); controllerService.buttonReleased(.b)
		await waitForTasks(0.05)
		XCTAssertEqual(review.held, []); XCTAssertEqual(review.seen, [.a, .b])
		review.stop()
		controllerService.buttonPressed(.x); controllerService.buttonReleased(.x)
		await waitForTasks(0.05)
		XCTAssertEqual(review.held, []); XCTAssertEqual(review.seen, [])
	}
}
