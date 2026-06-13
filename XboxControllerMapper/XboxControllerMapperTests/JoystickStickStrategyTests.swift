import XCTest
@testable import ControllerKeys

final class JoystickStickStrategyTests: XCTestCase {

    // MARK: - StickMode → Strategy lookup

    func testStickMode_none_returnsNoOpStrategy() {
        XCTAssertTrue(StickMode.none.strategy is NoOpStickStrategy)
    }

    func testStickMode_mouse_returnsMouseStrategy() {
        XCTAssertTrue(StickMode.mouse.strategy is MouseStickStrategy)
    }

    func testStickMode_scroll_returnsScrollStrategy() {
        XCTAssertTrue(StickMode.scroll.strategy is ScrollStickStrategy)
    }

    func testStickMode_wasdKeys_returnsDirectionKeyStrategyWithWasdMode() throws {
        let strategy = try XCTUnwrap(StickMode.wasdKeys.strategy as? DirectionKeyStickStrategy)
        XCTAssertEqual(strategy.mode, .wasdKeys)
    }

    func testStickMode_arrowKeys_returnsDirectionKeyStrategyWithArrowsMode() throws {
        let strategy = try XCTUnwrap(StickMode.arrowKeys.strategy as? DirectionKeyStickStrategy)
        XCTAssertEqual(strategy.mode, .arrowKeys)
    }

    func testStickMode_custom_returnsCustomDirectionStrategy() {
        XCTAssertTrue(StickMode.custom.strategy is CustomDirectionStickStrategy)
    }

    func testStickMode_dpad_returnsDPadStrategy() {
        XCTAssertTrue(StickMode.dpad.strategy is DPadStickStrategy)
    }

    // MARK: - D-Pad mode UI exposure

    func testStickMode_dpad_isVisibleInUI() {
        // The D-Pad mode must appear in the stick-mode dropdown alongside
        // Mouse / Scroll / Custom — it's how a stickless 8BitDo pad opts into
        // driving real d-pad buttons instead of the mouse.
        XCTAssertTrue(StickMode.visibleModes.contains(.dpad))
        XCTAssertTrue(StickMode.dpad.isVisibleInUI)
    }

    func testStickMode_dpad_doesNotExposeCustomJoystickDirections() {
        // D-Pad mode drives the controller's own .dpad* buttons, not the
        // user-defined custom direction mappings — so it must not be treated as
        // a custom-direction source (which would double-bind the directions).
        XCTAssertFalse(StickMode.dpad.exposesJoystickDirections)
    }

    func testEveryStickModeMapsToAStrategy() {
        // Defensive: if someone adds a StickMode case without wiring a strategy,
        // this catches it before the dispatch hits a runtime crash.
        for mode in StickMode.allCases {
            _ = mode.strategy
        }
    }
}
