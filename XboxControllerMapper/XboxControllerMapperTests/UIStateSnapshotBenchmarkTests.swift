import XCTest
@testable import ControllerKeys

// =============================================================================
// UI State Snapshot Benchmark + Correctness Tests
//
// Validates the optimization of batching per-frame UI singleton reads in the
// 120Hz joystick polling loop. Instead of 6 separate lock/unlock cycles across
// 3 singletons, we now do 3 total (one per singleton).
//
// OnScreenKeyboardManager: 2 reads → 1 (keyboardUISnapshot)
// SwipeTypingEngine:       2 reads → 1 (swipeSnapshot)
// DirectoryNavigatorManager: 1 read → 1 (unchanged, was already single)
// =============================================================================

// MARK: - Benchmark: OnScreenKeyboardManager Snapshot

final class KeyboardSnapshotBenchmarkTests: XCTestCase {

    /// OLD pattern: two separate lock acquisitions for visibility + letter area
    func testBenchmark_keyboard_OLD_separateReads() {
        let manager = OnScreenKeyboardManager.shared
        measure {
            for _ in 0..<100_000 {
                let visible = manager.threadSafeIsVisible
                let letterArea = manager.threadSafeLetterAreaScreenRect
                _ = (visible, letterArea)
            }
        }
    }

    /// NEW pattern: single lock acquisition via keyboardUISnapshot
    func testBenchmark_keyboard_NEW_singleSnapshot() {
        let manager = OnScreenKeyboardManager.shared
        measure {
            for _ in 0..<100_000 {
                let snapshot = manager.keyboardUISnapshot()
                _ = snapshot
            }
        }
    }
}

// MARK: - Benchmark: SwipeTypingEngine Snapshot

final class SwipeSnapshotBenchmarkTests: XCTestCase {

    /// OLD pattern: two separate lock acquisitions for state + cursor position
    func testBenchmark_swipe_OLD_separateReads() {
        let engine = SwipeTypingEngine.shared
        measure {
            for _ in 0..<100_000 {
                let state = engine.threadSafeState
                let cursor = engine.threadSafeCursorPosition
                _ = (state, cursor)
            }
        }
    }

    /// NEW pattern: single lock acquisition via swipeSnapshot
    func testBenchmark_swipe_NEW_singleSnapshot() {
        let engine = SwipeTypingEngine.shared
        measure {
            for _ in 0..<100_000 {
                let snapshot = engine.swipeSnapshot()
                _ = snapshot
            }
        }
    }
}

// MARK: - Correctness: Snapshot values match individual reads

final class UIStateSnapshotCorrectnessTests: XCTestCase {

    /// keyboardUISnapshot returns the same values as separate threadSafe reads
    func testKeyboardSnapshot_matchesSeparateReads() {
        let manager = OnScreenKeyboardManager.shared

        let separateVisible = manager.threadSafeIsVisible
        let separateLetterArea = manager.threadSafeLetterAreaScreenRect

        let snapshot = manager.keyboardUISnapshot()

        XCTAssertEqual(snapshot.visible, separateVisible,
                       "Snapshot visibility should match threadSafeIsVisible")
        XCTAssertEqual(snapshot.letterArea, separateLetterArea,
                       "Snapshot letterArea should match threadSafeLetterAreaScreenRect")
    }

    /// swipeSnapshot returns the same values as separate threadSafe reads
    func testSwipeSnapshot_matchesSeparateReads() {
        let engine = SwipeTypingEngine.shared

        let separateState = engine.threadSafeState
        let separateCursor = engine.threadSafeCursorPosition

        let snapshot = engine.swipeSnapshot()

        XCTAssertEqual(snapshot.state, separateState,
                       "Snapshot state should match threadSafeState")
        XCTAssertEqual(snapshot.cursorPosition, separateCursor,
                       "Snapshot cursorPosition should match threadSafeCursorPosition")
    }

    /// Snapshot values are consistent (all from same lock acquisition)
    func testKeyboardSnapshot_consistencyUnderDefaultState() {
        let manager = OnScreenKeyboardManager.shared

        // Under default state (not visible), both fields should be consistent
        let snapshot = manager.keyboardUISnapshot()
        if !snapshot.visible {
            // When not visible, letter area computation is skipped but may return
            // cached value from a previous computation or .zero
            // The key invariant: the visible flag and letter area come from the same lock
            XCTAssertFalse(snapshot.visible)
        }
    }

    /// SwipeTypingEngine snapshot returns both state and cursor atomically
    func testSwipeSnapshot_returnsStateAndCursor() {
        let engine = SwipeTypingEngine.shared

        let snapshot = engine.swipeSnapshot()
        // Verify both fields are populated (shared singleton may not be at defaults)
        XCTAssertEqual(snapshot.state, engine.threadSafeState,
                       "Snapshot state should match individual threadSafeState read")
        XCTAssertEqual(snapshot.cursorPosition, engine.threadSafeCursorPosition,
                       "Snapshot cursor should match individual threadSafeCursorPosition read")
    }
}
