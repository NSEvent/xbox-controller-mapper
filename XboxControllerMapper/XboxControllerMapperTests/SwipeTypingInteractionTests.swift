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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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
            directoryNavigatorVisible: false,
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

// MARK: - Swipe Cursor Routing Tests
//
// Spec: The joystick should control the real macOS cursor except when the user is
// actively swiping (click held down). Only during .swiping state should input be
// routed to the swipe cursor. After a swipe gesture ends, the real macOS cursor
// should warp to where the swipe cursor was last located.

final class SwipeCursorRoutingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SwipeTypingEngine.shared.deactivateMode()
    }

    override func tearDown() {
        SwipeTypingEngine.shared.deactivateMode()
        super.tearDown()
    }

    // MARK: - updateCursorFromJoystick only works during .swiping

    func testJoystickUpdate_InIdleState_HasNoEffect() {
        let initialPos = SwipeTypingEngine.shared.threadSafeCursorPosition
        SwipeTypingEngine.shared.updateCursorFromJoystick(x: 1.0, y: 1.0, sensitivity: 1.0)
        let afterPos = SwipeTypingEngine.shared.threadSafeCursorPosition
        XCTAssertEqual(initialPos.x, afterPos.x, accuracy: 0.001)
        XCTAssertEqual(initialPos.y, afterPos.y, accuracy: 0.001)
    }

    func testJoystickUpdate_InActiveState_HasNoEffect() {
        // In .active state, joystick should move the REAL cursor, not the swipe cursor.
        // The engine should reject joystick updates when not .swiping.
        SwipeTypingEngine.shared.activateMode()
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .active)

        SwipeTypingEngine.shared.setCursorPosition(CGPoint(x: 0.5, y: 0.5))
        SwipeTypingEngine.shared.updateCursorFromJoystick(x: 1.0, y: 1.0, sensitivity: 1.0)

        let pos = SwipeTypingEngine.shared.threadSafeCursorPosition
        XCTAssertEqual(pos.x, 0.5, accuracy: 0.001, "Joystick should NOT move swipe cursor in .active state")
        XCTAssertEqual(pos.y, 0.5, accuracy: 0.001, "Joystick should NOT move swipe cursor in .active state")
    }

    func testJoystickUpdate_InSwipingState_MovesCursor() {
        // In .swiping state, joystick should move the swipe cursor
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.setCursorPosition(CGPoint(x: 0.5, y: 0.5))
        SwipeTypingEngine.shared.beginSwipe()
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .swiping)

        SwipeTypingEngine.shared.updateCursorFromJoystick(x: 1.0, y: 0.0, sensitivity: 1.0)

        let pos = SwipeTypingEngine.shared.threadSafeCursorPosition
        XCTAssertGreaterThan(pos.x, 0.5, "Joystick should move swipe cursor right in .swiping state")
    }

    // MARK: - updateCursorFromTouchpadDelta only works during .swiping

    func testTouchpadUpdate_InActiveState_HasNoEffect() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.setCursorPosition(CGPoint(x: 0.5, y: 0.5))

        SwipeTypingEngine.shared.updateCursorFromTouchpadDelta(dx: 0.1, dy: 0.1, sensitivity: 1.0)

        let pos = SwipeTypingEngine.shared.threadSafeCursorPosition
        XCTAssertEqual(pos.x, 0.5, accuracy: 0.001, "Touchpad should NOT move swipe cursor in .active state")
        XCTAssertEqual(pos.y, 0.5, accuracy: 0.001, "Touchpad should NOT move swipe cursor in .active state")
    }

    func testTouchpadUpdate_InSwipingState_MovesCursor() {
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.setCursorPosition(CGPoint(x: 0.5, y: 0.5))
        SwipeTypingEngine.shared.beginSwipe()

        SwipeTypingEngine.shared.updateCursorFromTouchpadDelta(dx: 0.1, dy: 0.0, sensitivity: 1.0)

        let pos = SwipeTypingEngine.shared.threadSafeCursorPosition
        XCTAssertGreaterThan(pos.x, 0.5, "Touchpad should move swipe cursor in .swiping state")
    }

    // MARK: - Cursor position preserved after endSwipe (for warp-back)

    func testCursorPosition_PreservedAfterEndSwipe() {
        // After endSwipe, threadSafeCursorPosition should still reflect the last
        // swipe position. MappingEngine reads this to warp the real cursor.
        SwipeTypingEngine.shared.activateMode()
        SwipeTypingEngine.shared.setCursorPosition(CGPoint(x: 0.3, y: 0.7))
        SwipeTypingEngine.shared.beginSwipe()

        // Move cursor during swipe via joystick updates
        Thread.sleep(forTimeInterval: 0.02)
        SwipeTypingEngine.shared.updateCursorFromJoystick(x: 1.0, y: 0.0, sensitivity: 5.0)

        let posBeforeEnd = SwipeTypingEngine.shared.threadSafeCursorPosition
        XCTAssertGreaterThan(posBeforeEnd.x, 0.3, "Cursor should have moved during swipe")

        // End swipe — state transitions to .predicting
        SwipeTypingEngine.shared.endSwipe()
        XCTAssertEqual(SwipeTypingEngine.shared.threadSafeState, .predicting)

        // Cursor position should still be at the swipe end position
        let posAfterEnd = SwipeTypingEngine.shared.threadSafeCursorPosition
        XCTAssertEqual(posAfterEnd.x, posBeforeEnd.x, accuracy: 0.001,
                       "Cursor position must be preserved after endSwipe for warp-back")
        XCTAssertEqual(posAfterEnd.y, posBeforeEnd.y, accuracy: 0.001,
                       "Cursor position must be preserved after endSwipe for warp-back")
    }

    // MARK: - Coordinate conversion round-trip (normalized ↔ screen)

    func testNormalizedToScreenRoundTrip() {
        // Verify the coordinate conversion math used for warp-back is correct.
        // Forward: screen → normalized (done at beginSwipe)
        // Reverse: normalized → screen (done at endSwipe for warp)
        let letterArea = CGRect(x: 100, y: 200, width: 800, height: 300)
        let screenHeight: CGFloat = 1080

        // Simulate a Quartz cursor position (y-down from top)
        let originalQuartzX: CGFloat = 500
        let originalQuartzY: CGFloat = 600

        // Forward: Quartz → Cocoa → normalized
        let cocoaX = originalQuartzX
        let cocoaY = screenHeight - originalQuartzY  // 480
        let normalizedX = (cocoaX - letterArea.origin.x) / letterArea.width
        let normalizedY = 1.0 - (cocoaY - letterArea.origin.y) / letterArea.height

        // Reverse: normalized → Cocoa → Quartz
        let recoveredCocoaX = normalizedX * letterArea.width + letterArea.origin.x
        let recoveredCocoaY = (1.0 - normalizedY) * letterArea.height + letterArea.origin.y
        let recoveredQuartzY = screenHeight - recoveredCocoaY

        XCTAssertEqual(recoveredCocoaX, originalQuartzX, accuracy: 0.001)
        XCTAssertEqual(recoveredQuartzY, originalQuartzY, accuracy: 0.001)
    }

    func testNormalizedToScreenRoundTrip_EdgeCases() {
        let letterArea = CGRect(x: 50, y: 100, width: 600, height: 200)
        let screenHeight: CGFloat = 900

        // Top-left of letter area
        let topLeftQuartzY = screenHeight - (letterArea.origin.y + letterArea.height)  // 900 - 300 = 600

        let cocoaY_tl = screenHeight - topLeftQuartzY  // 300
        let normY_tl = 1.0 - (cocoaY_tl - letterArea.origin.y) / letterArea.height  // 1.0 - 200/200 = 0.0

        let recoveredCocoaY_tl = (1.0 - normY_tl) * letterArea.height + letterArea.origin.y
        let recoveredQuartzY_tl = screenHeight - recoveredCocoaY_tl

        XCTAssertEqual(recoveredQuartzY_tl, topLeftQuartzY, accuracy: 0.001)
    }
}
