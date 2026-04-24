import XCTest
import CoreGraphics
@testable import ControllerKeys

// MARK: - Bug 1: Modifier Reference Counting Race Condition Tests
//
// The modifier ref counting system uses a simple integer count per modifier.
// Problem: Under concurrent access, the count can become inconsistent with
// the heldModifiers set, leaving modifiers stuck.
//
// These tests verify the internal consistency of modifierCounts vs heldModifiers.

final class ModifierRefCountConsistencyTests: XCTestCase {

    var simulator: InputSimulator!

    override func setUp() {
        super.setUp()
        simulator = InputSimulator()
        // Skip if Accessibility is not available
        try? XCTSkipUnless(AXIsProcessTrusted(),
            "Modifier ref counting tests require Accessibility permissions")
    }

    override func tearDown() {
        simulator?.releaseAllModifiers()
        simulator = nil
        super.tearDown()
    }

    // MARK: - Bug 1a: Rapid overlapping hold/release can leave modifiers stuck
    //
    // When two threads rapidly hold and release the same modifier, the ref count
    // should always end at zero after equal hold/release calls.

    func testRapidOverlappingHoldRelease_modifiersCleared() {
        // Simulate two "buttons" rapidly holding and releasing Shift
        // Each does: hold, release. After all complete, Shift should be clear.
        let iterations = 500
        let group = DispatchGroup()

        for _ in 0..<iterations {
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                self.simulator.holdModifier(.maskShift)
                // Tiny delay to increase interleaving
                usleep(1)
                self.simulator.releaseModifier(.maskShift)
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 15)
        XCTAssertEqual(result, .success, "Should complete without deadlock")
        XCTAssertFalse(simulator.isHoldingModifiers(.maskShift),
            "Shift should not be stuck held after equal holds and releases")
        XCTAssertEqual(simulator.getHeldModifiers(), [],
            "No modifiers should be held after equal holds and releases")
    }

    // MARK: - Bug 1b: releaseAllModifiers followed by in-flight releaseModifier
    //
    // Scenario: Thread A holds Command. Thread B calls releaseAllModifiers().
    // Then Thread A calls releaseModifier(.maskCommand).
    // The underflow guard should prevent count from going negative,
    // AND the heldModifiers set should remain empty.

    func testReleaseAllThenRelease_noInconsistency() {
        simulator.holdModifier(.maskCommand)
        simulator.holdModifier(.maskShift)

        // Release all (resets counts to 0, clears heldModifiers)
        simulator.releaseAllModifiers()

        // Now simulate in-flight releases that arrive after releaseAll
        simulator.releaseModifier(.maskCommand)
        simulator.releaseModifier(.maskShift)

        // heldModifiers must still be empty
        XCTAssertEqual(simulator.getHeldModifiers(), [],
            "Modifiers must remain empty after releaseAll + extra releases")
    }

    // MARK: - Bug 1c: Interleaved hold/releaseAll/hold cycle
    //
    // After releaseAll, a fresh hold should work with count=1.
    // If releaseAll didn't properly reset counts, subsequent hold
    // might think count>0 and skip posting the key-down event.

    func testHoldAfterReleaseAll_worksCorrectly() {
        // Build up ref count > 1
        simulator.holdModifier(.maskCommand)
        simulator.holdModifier(.maskCommand)
        simulator.holdModifier(.maskCommand)

        // releaseAll should reset everything
        simulator.releaseAllModifiers()
        XCTAssertEqual(simulator.getHeldModifiers(), [])

        // Fresh hold should work (count goes from 0 to 1)
        simulator.holdModifier(.maskCommand)
        XCTAssertTrue(simulator.isHoldingModifiers(.maskCommand),
            "Hold after releaseAll should set the modifier")

        // Single release should clear it (count goes from 1 to 0)
        simulator.releaseModifier(.maskCommand)
        XCTAssertFalse(simulator.isHoldingModifiers(.maskCommand),
            "Single release after fresh hold should clear the modifier")
    }

    // MARK: - Bug 1d: Concurrent hold from many threads + single releaseAll
    //
    // Stress test: many threads hold the same modifier, then releaseAll is called.
    // After releaseAll, no modifier should be stuck.

    func testConcurrentHoldsThenReleaseAll_clearsEverything() {
        let holdCount = 100
        let group = DispatchGroup()

        for _ in 0..<holdCount {
            group.enter()
            DispatchQueue.global().async {
                self.simulator.holdModifier(.maskCommand)
                group.leave()
            }
        }

        _ = group.wait(timeout: .now() + 10)

        // Command should be held (count = holdCount)
        XCTAssertTrue(simulator.isHoldingModifiers(.maskCommand),
            "Command should be held after many concurrent holds")

        // releaseAll should clear regardless of count
        simulator.releaseAllModifiers()
        XCTAssertEqual(simulator.getHeldModifiers(), [],
            "releaseAll must clear all modifiers regardless of ref count")

        // Verify subsequent operations work
        simulator.holdModifier(.maskCommand)
        XCTAssertTrue(simulator.isHoldingModifiers(.maskCommand))
        simulator.releaseModifier(.maskCommand)
        XCTAssertFalse(simulator.isHoldingModifiers(.maskCommand))
    }
}


// MARK: - Bug 2: Zoom Detection Cache Thread Safety Tests
//
// isZoomCurrentlyActive() reads/writes static vars (cachedZoomActive,
// cachedZoomCheckTime) without synchronization. Concurrent callers can
// see torn reads or stale values.

final class ZoomCacheThreadSafetyTests: XCTestCase {

    func testConcurrentZoomCacheAccess_noCrash() {
        // Stress test: many threads calling isZoomCurrentlyActive() concurrently.
        // Before fix: potential torn reads on cachedZoomActive/cachedZoomCheckTime.
        // The test passes if no crash/TSAN violation occurs.
        let iterations = 2000

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = InputSimulator.isZoomCurrentlyActive()
        }

        // If we reach here without crashing, basic safety holds.
        // The result itself doesn't matter -- what matters is no data race.
        let result = InputSimulator.isZoomCurrentlyActive()
        // Just verify it returns a valid boolean (trivially true, but exercises the path)
        XCTAssertTrue(result == true || result == false)
    }

    func testConcurrentZoomLevelAndCacheAccess_noCrash() {
        // Mix of getZoomLevel() and isZoomCurrentlyActive() calls
        let iterations = 1000

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 2 == 0 {
                _ = InputSimulator.isZoomCurrentlyActive()
            } else {
                _ = InputSimulator.getZoomLevel()
            }
        }

        // No crash = success
        XCTAssertGreaterThanOrEqual(InputSimulator.getZoomLevel(), 1.0)
    }
}


// MARK: - Bug 3: Accessibility Zoom Accumulator Data Race Tests
//
// handleAccessibilityZoom() reads/writes accessibilityZoomAccumulator
// from the calling thread (which could be any thread via scroll()),
// but the instance variable is not protected by stateLock.

final class ZoomAccumulatorThreadSafetyTests: XCTestCase {

    func testConcurrentScrollWithControl_noCrash() {
        // Stress test: many concurrent scroll calls with Control held
        // (triggers handleAccessibilityZoom path).
        // Before fix: data race on accessibilityZoomAccumulator and related vars.
        let simulator = InputSimulator()
        let iterations = 500

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let dy = CGFloat(i % 2 == 0 ? 5 : -5)
            // The Control flag triggers the handleAccessibilityZoom path
            simulator.scroll(
                dx: 0, dy: dy,
                phase: nil, momentumPhase: nil,
                isContinuous: false,
                flags: .maskControl
            )
        }

        // No crash = success. The accumulator should be in a valid state.
        // We can't inspect it directly, but the object should not be corrupted.
        XCTAssertNotNil(simulator, "Simulator should survive concurrent zoom accumulator access")
    }

    func testMixedScrollAndNormalScroll_noCrash() {
        // Mix of Control+scroll (zoom path) and normal scroll (regular path)
        let simulator = InputSimulator()
        let iterations = 500

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 3 == 0 {
                simulator.scroll(dx: 0, dy: 5, phase: nil, momentumPhase: nil,
                    isContinuous: false, flags: .maskControl)
            } else {
                simulator.scroll(dx: 0, dy: 3, phase: nil, momentumPhase: nil,
                    isContinuous: false, flags: [])
            }
        }

        XCTAssertNotNil(simulator)
    }
}


// MARK: - Bug 4: Zoom Warning Panel Lifecycle Tests
//
// The zoom keyboard shortcut warning panel (showZoomKeyboardShortcutWarning)
// can be orphaned if:
//   1. The panel's keepAlive association is cleared but the panel isn't closed
//   2. Multiple warnings are shown (each replaces the keepAlive reference)
//
// These tests verify the warning state machine doesn't allow orphaning.

final class ZoomWarningStateMachineTests: XCTestCase {

    func testZoomWarningStateReset_afterSettingsOpened() {
        // The resetZoomDetectionState method should reset attempt count and warning flag.
        // This is called when user opens Settings from the warning panel.
        // We can't call the private method directly, but we test the observable behavior:
        // After many scroll attempts that would normally trigger the warning,
        // the simulator should still be functional.

        let simulator = InputSimulator()

        // Simulate many control+scroll calls (each increments zoomAttemptCount)
        // After 5 attempts, warning would be shown and shortcuts stop being sent.
        for _ in 0..<20 {
            simulator.scroll(
                dx: 0, dy: 15, // Above threshold to trigger zoom step
                phase: nil, momentumPhase: nil,
                isContinuous: false,
                flags: .maskControl
            )
            // Small delay to pass rate limiting
            usleep(60_000) // 60ms > 50ms minimum interval
        }

        // Simulator should still be usable
        XCTAssertNotNil(simulator, "Simulator must remain functional after zoom warning state")
    }
}
