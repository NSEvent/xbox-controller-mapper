import XCTest
@testable import ControllerKeys

final class ButtonPressOrchestrationPolicyTests: XCTestCase {
    func testResolveInterceptsDpadNavigationWhenKeyboardVisible() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadUp,
            mapping: .key(1),
            keyboardVisible: true,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )

        XCTAssertEqual(outcome, .interceptDpadNavigation)
    }

    func testResolveReturnsUnmappedWhenNoMappingAndNoDpadIntercept() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )

        XCTAssertEqual(outcome, .unmapped)
    }

    func testResolveInterceptsKeyboardActivationInNavigationMode() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick),
            keyboardVisible: true,
            navigationModeActive: true,
            isChordPart: false,
            lastTap: nil
        )

        XCTAssertEqual(outcome, .interceptKeyboardActivation)
    }

    func testResolveInterceptsOnScreenKeyboardAction() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.showOnScreenKeyboard, isHoldModifier: true),
            keyboardVisible: false,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: nil
        )

        XCTAssertEqual(outcome, .interceptOnScreenKeyboard(holdMode: true))
    }

    func testResolveCreatesMappingContextWithHoldPath() {
        let lastTap = Date()
        let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: mapping,
            keyboardVisible: false,
            navigationModeActive: false,
            isChordPart: false,
            lastTap: lastTap
        )

        XCTAssertEqual(
            outcome,
            .mapping(
                ButtonPressOrchestrationPolicy.MappingContext(
                    mapping: mapping,
                    lastTap: lastTap,
                    shouldTreatAsHold: true
                )
            )
        )
    }

    func testResolveCreatesMappingContextWithoutHoldPathForChordPart() {
        let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: mapping,
            keyboardVisible: false,
            navigationModeActive: false,
            isChordPart: true,
            lastTap: nil
        )

        XCTAssertEqual(
            outcome,
            .mapping(
                ButtonPressOrchestrationPolicy.MappingContext(
                    mapping: mapping,
                    lastTap: nil,
                    shouldTreatAsHold: false
                )
            )
        )
    }
}
