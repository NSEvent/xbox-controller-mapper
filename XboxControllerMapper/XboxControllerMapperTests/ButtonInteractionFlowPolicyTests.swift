import XCTest
@testable import ControllerKeys

final class ButtonInteractionFlowPolicyTests: XCTestCase {
    func testShouldUseHoldPathReturnsTrueForHoldModifier() {
        let mapping = KeyMapping(modifiers: ModifierFlags(command: true), isHoldModifier: true)

        XCTAssertTrue(ButtonInteractionFlowPolicy.shouldUseHoldPath(mapping: mapping, isChordPart: false))
    }

    func testShouldUseHoldPathReturnsTrueForMouseClickOutsideChordWithoutDoubleTap() {
        let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)

        XCTAssertTrue(ButtonInteractionFlowPolicy.shouldUseHoldPath(mapping: mapping, isChordPart: false))
    }

    func testShouldUseHoldPathReturnsFalseForMouseClickWhenButtonIsChordPart() {
        let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)

        XCTAssertFalse(ButtonInteractionFlowPolicy.shouldUseHoldPath(mapping: mapping, isChordPart: true))
    }

    func testShouldUseHoldPathReturnsFalseForMouseClickWithDoubleTapMapping() {
        let mapping = KeyMapping(
            keyCode: KeyCodeMapping.mouseLeftClick,
            doubleTapMapping: DoubleTapMapping(keyCode: KeyCodeMapping.mouseRightClick, threshold: 0.2)
        )

        XCTAssertFalse(ButtonInteractionFlowPolicy.shouldUseHoldPath(mapping: mapping, isChordPart: false))
    }

    func testReleaseDecisionReturnsSkipForHoldModifier() {
        let mapping = KeyMapping(modifiers: ModifierFlags(command: true), isHoldModifier: true)

        XCTAssertEqual(
            ButtonInteractionFlowPolicy.releaseDecision(mapping: mapping, holdDuration: 0.1, isLongHoldTriggered: false),
            .skip
        )
    }

    func testReleaseDecisionReturnsSkipForRepeatWithoutDoubleTap() {
        let mapping = KeyMapping(keyCode: 4, repeatMapping: RepeatMapping(enabled: true, interval: 0.1))

        XCTAssertEqual(
            ButtonInteractionFlowPolicy.releaseDecision(mapping: mapping, holdDuration: 0.1, isLongHoldTriggered: false),
            .skip
        )
    }

    func testReleaseDecisionReturnsDoubleTapEvaluationForRepeatWithDoubleTap() {
        let doubleTap = DoubleTapMapping(keyCode: 9, threshold: 0.2)
        let mapping = KeyMapping(
            keyCode: 4,
            doubleTapMapping: doubleTap,
            repeatMapping: RepeatMapping(enabled: true, interval: 0.1)
        )

        XCTAssertEqual(
            ButtonInteractionFlowPolicy.releaseDecision(mapping: mapping, holdDuration: 0.1, isLongHoldTriggered: false),
            .evaluateDoubleTap(doubleTap, skipSingleTapFallback: true)
        )
    }

    func testReleaseDecisionReturnsSkipWhenLongHoldAlreadyTriggered() {
        let mapping = KeyMapping(
            keyCode: 4,
            longHoldMapping: LongHoldMapping(keyCode: 10, threshold: 0.1)
        )

        XCTAssertEqual(
            ButtonInteractionFlowPolicy.releaseDecision(mapping: mapping, holdDuration: 0.2, isLongHoldTriggered: true),
            .skip
        )
    }

    func testReleaseDecisionReturnsLongHoldWhenThresholdExceeded() {
        let longHold = LongHoldMapping(keyCode: 10, threshold: 0.15)
        let mapping = KeyMapping(keyCode: 4, longHoldMapping: longHold)

        XCTAssertEqual(
            ButtonInteractionFlowPolicy.releaseDecision(mapping: mapping, holdDuration: 0.2, isLongHoldTriggered: false),
            .executeLongHold(longHold)
        )
    }

    func testReleaseDecisionReturnsDoubleTapForStandardDoubleTapConfig() {
        let doubleTap = DoubleTapMapping(keyCode: 9, threshold: 0.2)
        let mapping = KeyMapping(keyCode: 4, doubleTapMapping: doubleTap)

        XCTAssertEqual(
            ButtonInteractionFlowPolicy.releaseDecision(mapping: mapping, holdDuration: 0.1, isLongHoldTriggered: false),
            .evaluateDoubleTap(doubleTap, skipSingleTapFallback: false)
        )
    }

    func testReleaseDecisionReturnsSingleTapForPlainMapping() {
        let mapping = KeyMapping(keyCode: 4)

        XCTAssertEqual(
            ButtonInteractionFlowPolicy.releaseDecision(mapping: mapping, holdDuration: 0.1, isLongHoldTriggered: false),
            .executeSingleTap
        )
    }
}
