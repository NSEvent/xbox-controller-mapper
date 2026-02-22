import XCTest
@testable import ControllerKeys

final class DirectoryNavigatorPolicyTests: XCTestCase {

    // MARK: - D-pad interception when navigator visible

    func testDpadUp_WhenNavigatorVisible_InterceptsNavigation() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadUp,
            mapping: .key(1),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryNavigation)
    }

    func testDpadDown_WhenNavigatorVisible_InterceptsNavigation() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadDown,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryNavigation)
    }

    func testDpadLeft_WhenNavigatorVisible_InterceptsNavigation() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadLeft,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryNavigation)
    }

    func testDpadRight_WhenNavigatorVisible_InterceptsNavigation() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadRight,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryNavigation)
    }

    // MARK: - A and X confirm (cd here)

    func testAButton_WhenNavigatorVisible_InterceptsConfirm() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryConfirm)
    }

    func testXButton_WhenNavigatorVisible_InterceptsConfirm() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .x,
            mapping: KeyMapping(keyCode: 0),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryConfirm)
    }

    // MARK: - B dismisses (close without terminal)

    func testBButton_WhenNavigatorVisible_InterceptsDismiss() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .b,
            mapping: KeyMapping(keyCode: 0),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryDismiss)
    }

    // MARK: - Other buttons pass through when navigator visible

    func testYButton_WhenNavigatorVisible_NotIntercepted() {
        let mapping = KeyMapping(keyCode: 0)
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .y,
            mapping: mapping,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertNotEqual(outcome, .interceptDirectoryNavigation)
        XCTAssertNotEqual(outcome, .interceptDirectoryConfirm)
        XCTAssertNotEqual(outcome, .interceptDirectoryDismiss)
    }

    func testLeftBumper_WhenNavigatorVisible_NotIntercepted() {
        let mapping = KeyMapping(keyCode: 0)
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .leftBumper,
            mapping: mapping,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertNotEqual(outcome, .interceptDirectoryNavigation)
        XCTAssertNotEqual(outcome, .interceptDirectoryConfirm)
        XCTAssertNotEqual(outcome, .interceptDirectoryDismiss)
    }

    // MARK: - Navigator hidden: no interception

    func testDpadUp_WhenNavigatorHidden_NotInterceptedForNavigator() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadUp,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertNotEqual(outcome, .interceptDirectoryNavigation)
    }

    func testAButton_WhenNavigatorHidden_NotInterceptedForNavigator() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertNotEqual(outcome, .interceptDirectoryConfirm)
    }

    func testBButton_WhenNavigatorHidden_NotInterceptedForNavigator() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .b,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertNotEqual(outcome, .interceptDirectoryDismiss)
    }

    // MARK: - Navigator takes priority over keyboard

    func testDpadUp_WhenBothNavigatorAndKeyboardVisible_NavigatorWins() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadUp,
            mapping: .key(1),
            keyboardVisible: true,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        // Directory navigator interception is checked before keyboard
        XCTAssertEqual(outcome, .interceptDirectoryNavigation)
    }

    func testAButton_WhenBothNavigatorAndKeyboardVisible_NavigatorWins() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick),
            keyboardVisible: true,
            navigationModeActive: true,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        // Directory navigator confirm takes priority over keyboard activation
        XCTAssertEqual(outcome, .interceptDirectoryConfirm)
    }

    // MARK: - Directory Navigator special key code mapping

    func testDirectoryNavigatorMapping_InterceptsAsNavigator() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.showDirectoryNavigator, isHoldModifier: false),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryNavigator(holdMode: false))
    }

    func testDirectoryNavigatorMapping_HoldMode() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.showDirectoryNavigator, isHoldModifier: true),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryNavigator(holdMode: true))
    }

    // MARK: - A unmapped when navigator visible still confirms

    func testAButton_WhenNavigatorVisible_ConfirmsEvenWithoutMapping() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryConfirm)
    }

    func testXButton_WhenNavigatorVisible_ConfirmsEvenWithoutMapping() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .x,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryConfirm)
    }
}

// MARK: - KeyCodeMapping Directory Navigator Tests

final class KeyCodeMappingDirectoryNavigatorTests: XCTestCase {

    func testDirectoryNavigatorKeyCode_HasDisplayName() {
        XCTAssertEqual(
            KeyCodeMapping.displayName(for: KeyCodeMapping.showDirectoryNavigator),
            "Directory Navigator"
        )
    }

    func testDirectoryNavigatorKeyCode_IsSpecialAction() {
        XCTAssertTrue(KeyCodeMapping.isSpecialAction(KeyCodeMapping.showDirectoryNavigator))
    }

    func testDirectoryNavigatorKeyCode_IsSpecialMarker() {
        XCTAssertTrue(KeyCodeMapping.isSpecialMarker(KeyCodeMapping.showDirectoryNavigator))
    }

    func testDirectoryNavigatorKeyCode_IsNotMouseButton() {
        XCTAssertFalse(KeyCodeMapping.isMouseButton(KeyCodeMapping.showDirectoryNavigator))
    }

    func testDirectoryNavigatorKeyCode_IsNotMediaKey() {
        XCTAssertFalse(KeyCodeMapping.isMediaKey(KeyCodeMapping.showDirectoryNavigator))
    }

    func testDirectoryNavigatorKeyCode_InAllKeyOptions() {
        let options = KeyCodeMapping.allKeyOptions
        XCTAssertTrue(options.contains(where: { $0.name == "Directory Navigator" }))
    }
}
