import XCTest
@testable import ControllerKeys

// MARK: - SwipeTypingEngine Thread Safety Tests

final class SwipeTypingEngineThreadSafetyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SwipeTypingEngine.shared.deactivateMode()
    }

    override func tearDown() {
        SwipeTypingEngine.shared.deactivateMode()
        super.tearDown()
    }

    /// Stress-test concurrent reads of threadSafeState and threadSafeCursorPosition
    /// while another thread is mutating state through the normal API.
    func testConcurrentStateReads_NoCrash() {
        let iterations = 1000

        // Activate so we have a non-trivial state
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.beginSwipe()

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            // Mix of reads and writes
            if i % 4 == 0 {
                _ = SwipeTypingEngine.shared.threadSafeState
            } else if i % 4 == 1 {
                _ = SwipeTypingEngine.shared.threadSafeCursorPosition
            } else if i % 4 == 2 {
                SwipeTypingEngine.shared.setCursorPosition(CGPoint(x: Double(i) * 0.001, y: 0.5))
            } else {
                SwipeTypingEngine.shared.addSample(x: Double(i) * 0.001, y: 0.5)
            }
        }

        // If we reach here without a crash, the test passes
        let state = SwipeTypingEngine.shared.threadSafeState
        XCTAssertTrue(state == .swiping || state == .idle || state == .active,
                      "State should be valid after concurrent access")
    }

    /// Stress-test concurrent updateCursorFromJoystick calls.
    func testConcurrentJoystickUpdates_NoCrash() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.beginSwipe()

        DispatchQueue.concurrentPerform(iterations: 500) { i in
            SwipeTypingEngine.shared.updateCursorFromJoystick(
                x: Double(i % 10) * 0.1 - 0.5,
                y: Double(i % 7) * 0.1 - 0.3,
                sensitivity: 1.0
            )
        }

        // No crash = success
        let pos = SwipeTypingEngine.shared.threadSafeCursorPosition
        XCTAssertFalse(pos.x.isNaN, "Cursor X should not be NaN")
        XCTAssertFalse(pos.y.isNaN, "Cursor Y should not be NaN")
    }

    /// Stress-test concurrent updateCursorFromTouchpadDelta calls.
    /// This specifically targets the previously racy _smoothedDx/_smoothedDy access
    /// that was outside the lock in the original code.
    func testConcurrentTouchpadDeltaUpdates_NoCrash() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.beginSwipe()

        DispatchQueue.concurrentPerform(iterations: 500) { i in
            SwipeTypingEngine.shared.updateCursorFromTouchpadDelta(
                dx: Double(i % 10) * 0.01 - 0.05,
                dy: Double(i % 7) * 0.01 - 0.03,
                sensitivity: 1.0
            )
        }

        let pos = SwipeTypingEngine.shared.threadSafeCursorPosition
        XCTAssertFalse(pos.x.isNaN, "Cursor X should not be NaN after concurrent touchpad updates")
        XCTAssertFalse(pos.y.isNaN, "Cursor Y should not be NaN after concurrent touchpad updates")
    }

    /// Stress-test concurrent activate/deactivate cycles.
    func testConcurrentActivateDeactivate_NoCrash() {
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            if i % 2 == 0 {
                SwipeTypingEngine.shared.activateMode()
            } else {
                SwipeTypingEngine.shared.deactivateMode()
            }
        }

        let state = SwipeTypingEngine.shared.threadSafeState
        XCTAssertTrue(state == .idle || state == .active,
                      "State should be idle or active after concurrent activate/deactivate")
    }

    /// Stress-test the full swipe lifecycle from multiple threads.
    func testConcurrentFullLifecycle_NoCrash() {
        DispatchQueue.concurrentPerform(iterations: 100) { i in
            switch i % 6 {
            case 0:
                SwipeTypingEngine.shared.activateMode()
            case 1:
                SwipeTypingEngine.shared.beginSwipe()
            case 2:
                SwipeTypingEngine.shared.addSample(x: Double(i) * 0.01, y: 0.5)
            case 3:
                SwipeTypingEngine.shared.endSwipe()
            case 4:
                SwipeTypingEngine.shared.setCursorPosition(CGPoint(x: 0.3, y: 0.7))
            case 5:
                SwipeTypingEngine.shared.deactivateMode()
            default:
                break
            }
        }

        // No crash = success
        let state = SwipeTypingEngine.shared.threadSafeState
        XCTAssertNotNil(state)
    }

    /// Test that mixed touchpad and joystick updates from concurrent threads don't crash.
    func testConcurrentMixedInputUpdates_NoCrash() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.beginSwipe()

        DispatchQueue.concurrentPerform(iterations: 500) { i in
            if i % 2 == 0 {
                SwipeTypingEngine.shared.updateCursorFromJoystick(
                    x: 0.5, y: -0.3, sensitivity: 1.0
                )
            } else {
                SwipeTypingEngine.shared.updateCursorFromTouchpadDelta(
                    dx: 0.02, dy: -0.01, sensitivity: 1.0
                )
            }
        }

        let pos = SwipeTypingEngine.shared.threadSafeCursorPosition
        XCTAssertFalse(pos.x.isNaN)
        XCTAssertFalse(pos.y.isNaN)
    }
}
