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

    // MARK: - In-place filtering correctness

    func testMultipleActiveSequencesSomeTimeOutSomeAdvance() {
        // seq1: A -> B (short timeout), seq2: A -> B (long timeout), seq3: A -> X (long timeout)
        let seq1 = SequenceMapping(steps: [.a, .b], stepTimeout: 0.1, keyCode: 10)
        let seq2 = SequenceMapping(steps: [.a, .b], stepTimeout: 1.0, keyCode: 20)
        let seq3 = SequenceMapping(steps: [.a, .x], stepTimeout: 1.0, keyCode: 30)
        detector.configure(sequences: [seq1, seq2, seq3])

        let now: TimeInterval = 1000.0
        _ = detector.process(.a, at: now)
        XCTAssertEqual(detector.activeSequences.count, 3, "All three should be tracking")

        // Press B at 0.5s — seq1 times out, seq2 advances, seq3 doesn't match B
        let result = detector.process(.b, at: now + 0.5)
        XCTAssertNotNil(result, "seq2 should complete (A->B with 1.0s timeout)")
        XCTAssertEqual(result?.keyCode, 20)
        // seq1 timed out, seq2 completed and removed, seq3 didn't match B so pruned.
        // But a new seq1 tracker is NOT started (B is not first step of any sequence).
        // A new seq2 tracker is NOT started either. Only new trackers for sequences starting with B.
        // None start with B, so activeSequences should be empty (or just seq3 restart if B matches).
    }

    func testSequenceTimesOutMidProgressIsPruned() {
        let seq = SequenceMapping(steps: [.a, .b, .x], stepTimeout: 0.2, keyCode: 10)
        detector.configure(sequences: [seq])

        let now: TimeInterval = 1000.0
        _ = detector.process(.a, at: now)
        _ = detector.process(.b, at: now + 0.1)
        XCTAssertEqual(detector.activeSequences.count, 1, "Should be tracking the 2-step-matched sequence")

        // Press X after timeout — should not complete
        let result = detector.process(.x, at: now + 0.5)
        XCTAssertNil(result, "Sequence should be pruned after mid-progress timeout")
        XCTAssertTrue(detector.activeSequences.isEmpty, "No active sequences should remain")
    }

    // MARK: - No duplicate tracking

    func testSameFirstStepPressedTwiceDoesNotDuplicate() {
        let seq = SequenceMapping(steps: [.a, .b], stepTimeout: 0.5, keyCode: 10)
        detector.configure(sequences: [seq])

        let now: TimeInterval = 1000.0
        _ = detector.process(.a, at: now)
        XCTAssertEqual(detector.activeSequences.count, 1, "One tracker after first A")

        // Press A again quickly — the existing tracker doesn't match A as second step,
        // so it's pruned. A new tracker is started. Should still be exactly 1.
        _ = detector.process(.a, at: now + 0.1)
        XCTAssertEqual(detector.activeSequences.count, 1, "Should still have exactly one tracker, not two")
    }

    func testAlreadyTrackedSequenceNotDuplicated() {
        // A->A->B: after first A, tracker is active. Second A advances it.
        // The duplicate check prevents a second tracker from being created for the same sequence.
        let seq = SequenceMapping(steps: [.a, .a, .b], stepTimeout: 0.5, keyCode: 10)
        detector.configure(sequences: [seq])

        let now: TimeInterval = 1000.0
        _ = detector.process(.a, at: now)
        XCTAssertEqual(detector.activeSequences.count, 1, "One tracker after first A")

        _ = detector.process(.a, at: now + 0.1)
        // The existing tracker advanced (matched count 2). The duplicate check sees this
        // sequence is already tracked, so no second tracker is created.
        XCTAssertEqual(detector.activeSequences.count, 1,
                       "Should still have one tracker — duplicate suppressed")

        let result = detector.process(.b, at: now + 0.2)
        XCTAssertNotNil(result, "Should complete after A->A->B")
        XCTAssertEqual(result?.keyCode, 10)
    }

    // MARK: - Reconfigure clears progress

    func testReconfigureClearsOldProgress() {
        let seq1 = SequenceMapping(steps: [.a, .b], stepTimeout: 0.5, keyCode: 10)
        detector.configure(sequences: [seq1])

        let now: TimeInterval = 1000.0
        _ = detector.process(.a, at: now)
        XCTAssertEqual(detector.activeSequences.count, 1)

        // Reconfigure with different sequences
        let seq2 = SequenceMapping(steps: [.x, .y], stepTimeout: 0.5, keyCode: 20)
        detector.configure(sequences: [seq2])
        XCTAssertTrue(detector.activeSequences.isEmpty, "Reconfigure should clear all active tracking")

        // Old sequence should not complete
        let result = detector.process(.b, at: now + 0.1)
        XCTAssertNil(result, "Old sequence should not complete after reconfigure")
    }

    // MARK: - Edge cases

    func testProcessWithEmptySequencesArray() {
        detector.configure(sequences: [])
        let result = detector.process(.a, at: 1000.0)
        XCTAssertNil(result, "Should return nil with no configured sequences")
        XCTAssertTrue(detector.activeSequences.isEmpty)
    }

    func testAllActiveSequencesTimeOutSimultaneously() {
        let seq1 = SequenceMapping(steps: [.a, .b], stepTimeout: 0.2, keyCode: 10)
        let seq2 = SequenceMapping(steps: [.a, .x], stepTimeout: 0.2, keyCode: 20)
        detector.configure(sequences: [seq1, seq2])

        let now: TimeInterval = 1000.0
        _ = detector.process(.a, at: now)
        XCTAssertEqual(detector.activeSequences.count, 2)

        // Press B well after both timeouts
        let result = detector.process(.b, at: now + 1.0)
        XCTAssertNil(result, "Both should have timed out")
        // A new tracker for seq1 should NOT start because B is not its first step.
        // Actually neither seq starts with B, so empty.
        XCTAssertTrue(detector.activeSequences.isEmpty, "All timed out, no new trackers for B")
    }

    func testVeryRapidButtonPresses() {
        let seq = SequenceMapping(steps: [.a, .b, .x], stepTimeout: 0.5, keyCode: 10)
        detector.configure(sequences: [seq])

        let now: TimeInterval = 1000.0
        XCTAssertNil(detector.process(.a, at: now))
        XCTAssertNil(detector.process(.b, at: now + 0.0001))
        let result = detector.process(.x, at: now + 0.0002)
        XCTAssertNotNil(result, "Near-zero time deltas should still complete")
        XCTAssertEqual(result?.keyCode, 10)
    }

    func testSingleStepSequenceIsInvalid() {
        // isValid requires steps.count >= 2, so a single-step sequence is filtered out
        let seq = SequenceMapping(steps: [.a], stepTimeout: 0.5, keyCode: 10)
        XCTAssertFalse(seq.isValid, "Single-step sequence should be invalid")
        detector.configure(sequences: [seq])

        let result = detector.process(.a, at: 1000.0)
        XCTAssertNil(result, "Invalid sequence should never be tracked or completed")
        XCTAssertTrue(detector.activeSequences.isEmpty)
    }

    // MARK: - Capacity stability

    func testActiveSequencesCapacityDoesNotGrowUnbounded() {
        // Configure 10 sequences all starting with A, each A->B with different keyCodes
        var sequences: [SequenceMapping] = []
        for i in 0..<10 {
            sequences.append(SequenceMapping(steps: [.a, .b], stepTimeout: 0.5, keyCode: CGKeyCode(i)))
        }
        detector.configure(sequences: sequences)

        let now: TimeInterval = 1000.0
        var maxCount = 0

        // Process 100 button presses alternating A and wrong-button (X)
        for press in 0..<100 {
            let button: ControllerButton = (press % 2 == 0) ? .a : .x
            _ = detector.process(button, at: now + Double(press) * 0.1)
            maxCount = max(maxCount, detector.activeSequences.count)
        }

        // With 10 sequences starting with A, after pressing A we get 10 trackers.
        // Pressing X prunes all (wrong step). So max should be 10, never growing.
        XCTAssertLessThanOrEqual(maxCount, 10,
                                 "Active sequences should not exceed the number of configured sequences")
    }
}
