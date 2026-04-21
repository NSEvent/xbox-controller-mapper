import XCTest
@testable import ControllerKeys

final class SequenceDetectorTests: XCTestCase {
    var detector: SequenceDetector!

    override func setUp() {
        detector = SequenceDetector()
    }

    override func tearDown() {
        detector = nil
    }

    func testCorrectSequenceCompletes() {
        let sequence = SequenceMapping(steps: [.a, .b], stepTimeout: 0.5, keyCode: 10)
        detector.configure(sequences: [sequence])

        let now = CFAbsoluteTimeGetCurrent()
        let result1 = detector.process(.a, at: now)
        XCTAssertNil(result1, "First step should not complete the sequence")

        let result2 = detector.process(.b, at: now + 0.1)
        XCTAssertNotNil(result2, "Second step should complete the sequence")
        XCTAssertEqual(result2?.keyCode, 10)
    }

    func testWrongSecondStepDoesNotComplete() {
        let sequence = SequenceMapping(steps: [.a, .b], stepTimeout: 0.5, keyCode: 10)
        detector.configure(sequences: [sequence])

        let now = CFAbsoluteTimeGetCurrent()
        _ = detector.process(.a, at: now)
        let result = detector.process(.x, at: now + 0.1)
        XCTAssertNil(result, "Wrong second button should not complete the sequence")
    }

    func testSequenceTimesOut() {
        let sequence = SequenceMapping(steps: [.a, .b], stepTimeout: 0.3, keyCode: 10)
        detector.configure(sequences: [sequence])

        let now = CFAbsoluteTimeGetCurrent()
        _ = detector.process(.a, at: now)

        // Press B after timeout
        let result = detector.process(.b, at: now + 0.5)
        XCTAssertNil(result, "Sequence should not complete after timeout")
    }

    func testChordWindowToleranceExtendsTimeout() {
        let sequence = SequenceMapping(steps: [.a, .b], stepTimeout: 0.3, keyCode: 10)
        detector.configure(sequences: [sequence])
        detector.chordWindowTolerance = 0.15

        let now = CFAbsoluteTimeGetCurrent()
        _ = detector.process(.a, at: now)

        // Press B after base timeout but within extended window
        let result = detector.process(.b, at: now + 0.4)
        XCTAssertNotNil(result, "Sequence should complete within extended timeout (base + chord tolerance)")
    }

    func testThreeStepSequence() {
        let sequence = SequenceMapping(steps: [.a, .b, .x], stepTimeout: 0.5, keyCode: 20)
        detector.configure(sequences: [sequence])

        let now = CFAbsoluteTimeGetCurrent()
        XCTAssertNil(detector.process(.a, at: now))
        XCTAssertNil(detector.process(.b, at: now + 0.1))
        let result = detector.process(.x, at: now + 0.2)
        XCTAssertNotNil(result, "Three-step sequence should complete on last step")
        XCTAssertEqual(result?.keyCode, 20)
    }

    func testResetClearsActiveSequences() {
        let sequence = SequenceMapping(steps: [.a, .b], stepTimeout: 0.5, keyCode: 10)
        detector.configure(sequences: [sequence])

        let now = CFAbsoluteTimeGetCurrent()
        _ = detector.process(.a, at: now)
        XCTAssertFalse(detector.activeSequences.isEmpty, "Should have active tracking after first step")

        detector.reset()
        XCTAssertTrue(detector.activeSequences.isEmpty, "Reset should clear all active tracking")

        // Now B should not complete anything (A tracking was reset)
        let result = detector.process(.b, at: now + 0.1)
        XCTAssertNil(result, "B should not complete sequence after reset")
    }

    func testRepeatedButtonSequenceCompletes() {
        let sequence = SequenceMapping(steps: [.a, .a, .a], stepTimeout: 0.5, keyCode: 30)
        detector.configure(sequences: [sequence])

        let now = CFAbsoluteTimeGetCurrent()
        XCTAssertNil(detector.process(.a, at: now), "First A should not complete")
        XCTAssertNil(detector.process(.a, at: now + 0.1), "Second A should not complete")
        let result = detector.process(.a, at: now + 0.2)
        XCTAssertNotNil(result, "Third A should complete the A->A->A sequence")
        XCTAssertEqual(result?.keyCode, 30)
    }

    func testRepeatedButtonSequenceTimesOutMidway() {
        let sequence = SequenceMapping(steps: [.a, .a, .a], stepTimeout: 0.3, keyCode: 30)
        detector.configure(sequences: [sequence])

        let now = CFAbsoluteTimeGetCurrent()
        _ = detector.process(.a, at: now)
        _ = detector.process(.a, at: now + 0.1)
        // Third press after timeout
        let result = detector.process(.a, at: now + 0.5)
        XCTAssertNil(result, "Sequence should not complete when step timeout expires between presses")
    }

    func testMultipleSequencesTrackedConcurrently() {
        let seq1 = SequenceMapping(steps: [.a, .b], stepTimeout: 0.5, keyCode: 10)
        let seq2 = SequenceMapping(steps: [.a, .x], stepTimeout: 0.5, keyCode: 20)
        detector.configure(sequences: [seq1, seq2])

        let now = CFAbsoluteTimeGetCurrent()
        _ = detector.process(.a, at: now)
        XCTAssertEqual(detector.activeSequences.count, 2, "Both sequences should be tracking after A")

        let result = detector.process(.x, at: now + 0.1)
        XCTAssertNotNil(result, "Second sequence should complete with X")
        XCTAssertEqual(result?.keyCode, 20)
    }
}
