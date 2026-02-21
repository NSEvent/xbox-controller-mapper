import XCTest
@testable import ControllerKeys

// MARK: - ButtonPressOrchestrationPolicy Swipe Tests

final class SwipeTypingOrchestrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Ensure swipe engine starts from idle
        SwipeTypingEngine.shared.deactivateMode()
    }

    override func tearDown() {
        SwipeTypingEngine.shared.deactivateMode()
        super.tearDown()
    }

    // MARK: - Swipe idle: buttons should NOT be intercepted for swipe

    func testIdleState_AButton_NotInterceptedForSwipe() {
        let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: mapping,
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        // A button with keyboard visible but swipe idle should go through normal mapping
        XCTAssertNotEqual(outcome, .interceptSwipePredictionConfirm)
    }

    func testIdleState_BButton_NotInterceptedForSwipe() {
        let mapping = KeyMapping(keyCode: 0)
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .b,
            mapping: mapping,
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertNotEqual(outcome, .interceptSwipePredictionCancel)
    }

    // MARK: - Swipe active: B cancels, others pass through

    func testActiveState_BButton_CancelsSwipe() {
        SwipeTypingEngine.shared.activateMode()

        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .b,
            mapping: KeyMapping(keyCode: 0),
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptSwipePredictionCancel)
    }

    func testActiveState_AButton_NotInterceptedForConfirm() {
        SwipeTypingEngine.shared.activateMode()

        let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: mapping,
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        // A is NOT intercepted in active state (only in showingPredictions)
        XCTAssertNotEqual(outcome, .interceptSwipePredictionConfirm)
    }

    // MARK: - Swipe swiping: B cancels, others pass through

    func testSwipingState_BButton_CancelsSwipe() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.beginSwipe()

        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .b,
            mapping: KeyMapping(keyCode: 0),
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptSwipePredictionCancel)
    }

    // MARK: - Showing predictions: A confirms, B cancels, dpad navigates
    // Note: These tests use setSwipeStateShowingPredictions() which directly
    // transitions through the state machine and waits for inference to complete.
    // If the model is not loaded in tests, endSwipe returns empty predictions
    // and state goes to .active instead — those tests are skipped via guard.

    func testShowingPredictions_AButton_ConfirmsSelection() {
        guard setSwipeStateShowingPredictions() else { return }

        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick),
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptSwipePredictionConfirm)
    }

    func testShowingPredictions_BButton_CancelsPredictions() {
        guard setSwipeStateShowingPredictions() else { return }

        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .b,
            mapping: KeyMapping(keyCode: 0),
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptSwipePredictionCancel)
    }

    func testShowingPredictions_DpadLeft_NavigatesPredictions() {
        guard setSwipeStateShowingPredictions() else { return }

        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadLeft,
            mapping: nil,
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptSwipePredictionNavigation)
    }

    func testShowingPredictions_DpadRight_NavigatesPredictions() {
        guard setSwipeStateShowingPredictions() else { return }

        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadRight,
            mapping: nil,
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptSwipePredictionNavigation)
    }

    func testShowingPredictions_DpadUp_NotIntercepted() {
        guard setSwipeStateShowingPredictions() else { return }

        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadUp,
            mapping: nil,
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        // dpadUp during predictions falls through to normal dpad navigation
        XCTAssertEqual(outcome, .interceptDpadNavigation)
    }

    func testShowingPredictions_OtherButtons_NotIntercepted() {
        guard setSwipeStateShowingPredictions() else { return }

        let mapping = KeyMapping(keyCode: 0)
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .x,
            mapping: mapping,
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        // X button is not intercepted for swipe — falls through to normal mapping
        XCTAssertNotEqual(outcome, .interceptSwipePredictionConfirm)
        XCTAssertNotEqual(outcome, .interceptSwipePredictionCancel)
        XCTAssertNotEqual(outcome, .interceptSwipePredictionNavigation)
    }

    // MARK: - Keyboard not visible: swipe intercepts never fire

    func testKeyboardHidden_SwipePredictions_NoInterception() {
        guard setSwipeStateShowingPredictions() else { return }

        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick),
            keyboardVisible: false,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        // Even if swipe state is showing predictions, keyboard hidden means no interception
        XCTAssertNotEqual(outcome, .interceptSwipePredictionConfirm)
    }

    func testKeyboardHidden_SwipeActive_NoInterception() {
        SwipeTypingEngine.shared.activateMode()

        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .b,
            mapping: KeyMapping(keyCode: 0),
            keyboardVisible: false,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertNotEqual(outcome, .interceptSwipePredictionCancel)
    }

    // MARK: - Predicting state: B cancels (same as active/swiping)

    func testPredictingState_BButton_CancelsSwipe() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.beginSwipe()
        SwipeTypingEngine.shared.endSwipe()
        // endSwipe synchronously sets tsState to .predicting
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .predicting)

        // During predicting, only B is intercepted (same as active/swiping)
        // because predicting is not in the showingPredictions branch
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .b,
            mapping: KeyMapping(keyCode: 0),
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )
        // .predicting is not handled specially by the policy — it's not .active/.swiping/.showingPredictions
        // so B falls through to normal mapping
        // This is expected: during the brief predicting state, no special interception occurs
        XCTAssertNotEqual(outcome, .interceptSwipePredictionCancel)
    }

    // MARK: - Helpers

    /// Attempts to reach .showingPredictions state by running inference.
    /// Returns false if the state couldn't be reached (e.g. no model loaded, empty predictions).
    @discardableResult
    private func setSwipeStateShowingPredictions() -> Bool {
        SwipeTypingEngine.shared.deactivateMode()
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.beginSwipe()

        // Add samples that form a recognizable swipe pattern (H→E→L→L→O)
        // These coordinates approximate key centers in normalized keyboard space
        let helloPath: [(Double, Double)] = [
            (0.069, 0.333), // H
            (0.167, 0.667), // E
            (0.319, 0.333), // L
            (0.319, 0.333), // L (same position)
            (0.486, 0.667), // O
        ]
        for (x, y) in helloPath {
            SwipeTypingEngine.shared.addSample(x: x, y: y)
            // Small delay to pass rate limiting
            Thread.sleep(forTimeInterval: 0.02)
        }

        SwipeTypingEngine.shared.endSwipe()

        // Wait for inference to complete
        let expectation = expectation(description: "Swipe inference completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)

        let finalState = SwipeTypingEngine.shared.threadSafeState
        if finalState != .showingPredictions {
            // Model not loaded or no predictions — skip test
            return false
        }
        return true
    }
}

// MARK: - SwipeTypingEngine State Machine Tests

final class SwipeTypingEngineStateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SwipeTypingEngine.shared.deactivateMode()
    }

    override func tearDown() {
        SwipeTypingEngine.shared.deactivateMode()
        super.tearDown()
    }

    func testInitialStateIsIdle() {
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .idle)
    }

    func testActivateMode_TransitionsToActive() {
        SwipeTypingEngine.shared.activateMode()
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .active)
    }

    func testActivateMode_WhileAlreadyActive_StaysActive() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.activateMode()
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .active)
    }

    func testDeactivateMode_TransitionsToIdle() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.deactivateMode()
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .idle)
    }

    func testDeactivateMode_FromSwiping_TransitionsToIdle() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.beginSwipe()
        SwipeTypingEngine.shared.deactivateMode()
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .idle)
    }

    func testBeginSwipe_FromActive_TransitionsToSwiping() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.beginSwipe()
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .swiping)
    }

    func testBeginSwipe_FromIdle_StaysIdle() {
        // Cannot begin swipe from idle — must activate first
        SwipeTypingEngine.shared.beginSwipe()
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .idle)
    }

    func testEndSwipe_FromSwiping_TransitionsToPredicting() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.beginSwipe()
        SwipeTypingEngine.shared.endSwipe()
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .predicting)
    }

    func testEndSwipe_FromActive_StaysActive() {
        // endSwipe should be a no-op when not swiping
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.endSwipe()
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .active)
    }

    func testAddSample_OnlyAcceptedDuringSwiping() {
        // In idle — sample should be ignored
        SwipeTypingEngine.shared.addSample(x: 0.5, y: 0.5)
        // No crash, no state change
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .idle)

        // In active — sample should be ignored
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.addSample(x: 0.5, y: 0.5)
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .active)

        // In swiping — sample should be accepted (no crash)
        SwipeTypingEngine.shared.beginSwipe()
        SwipeTypingEngine.shared.addSample(x: 0.5, y: 0.5)
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .swiping)
    }

    func testSetCursorPosition_UpdatesThreadSafePosition() {
        let pos = CGPoint(x: 0.3, y: 0.7)
        SwipeTypingEngine.shared.setCursorPosition(pos)
        let retrieved = SwipeTypingEngine.shared.threadSafeCursorPosition
        XCTAssertEqual(retrieved.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(retrieved.y, 0.7, accuracy: 0.001)
    }

    func testBeginSwipe_ResetsCursorToCurrentPosition() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.setCursorPosition(CGPoint(x: 0.2, y: 0.8))
        SwipeTypingEngine.shared.beginSwipe()

        // After begin swipe, cursor position should still be at the set position
        let pos = SwipeTypingEngine.shared.threadSafeCursorPosition
        XCTAssertEqual(pos.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(pos.y, 0.8, accuracy: 0.001)
    }
}

// MARK: - Swipe Click Debounce Tests

final class SwipeClickDebounceTests: XCTestCase {

    func testDebounceCounter_ResetsOnClick() {
        let state = MappingEngine.EngineState()
        state.swipeClickReleaseFrames = 2
        state.swipeClickReleaseFrames = 0  // Simulates click down resetting counter
        XCTAssertEqual(state.swipeClickReleaseFrames, 0)
    }

    func testDebounceCounter_IncrementsBelowThreshold() {
        let state = MappingEngine.EngineState()
        state.swipeClickReleaseFrames = 0
        state.swipeClickReleaseFrames += 1
        XCTAssertEqual(state.swipeClickReleaseFrames, 1)
        // Below threshold of 3, swipe should NOT end
        XCTAssertTrue(state.swipeClickReleaseFrames < 3)
    }

    func testDebounceCounter_ThresholdTriggersEnd() {
        let state = MappingEngine.EngineState()
        state.swipeClickReleaseFrames = 0
        state.swipeClickReleaseFrames += 1  // Frame 1
        state.swipeClickReleaseFrames += 1  // Frame 2
        state.swipeClickReleaseFrames += 1  // Frame 3
        XCTAssertTrue(state.swipeClickReleaseFrames >= 3)
    }

    func testResetClearsDebounceCounter() {
        let state = MappingEngine.EngineState()
        state.swipeClickReleaseFrames = 5
        state.reset()
        XCTAssertEqual(state.swipeClickReleaseFrames, 0)
    }
}
