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

    func testEveryStickModeMapsToAStrategy() {
        // Defensive: if someone adds a StickMode case without wiring a strategy,
        // this catches it before the dispatch hits a runtime crash.
        for mode in StickMode.allCases {
            _ = mode.strategy
        }
    }
}
