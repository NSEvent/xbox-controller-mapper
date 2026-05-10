import XCTest
@testable import ControllerKeys

final class ZoomMouseEventPolicyTests: XCTestCase {

    // MARK: - No zoom: stay on CGEvent

    func testZoomNotActive_move_usesCGEvent() {
        XCTAssertFalse(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: false, category: .move),
            "Mouse move without zoom should use CGEvent")
    }

    func testZoomNotActive_drag_usesCGEvent() {
        XCTAssertFalse(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: false, category: .drag),
            "Mouse drag without zoom should use CGEvent")
    }

    func testZoomNotActive_buttonDown_usesCGEvent() {
        XCTAssertFalse(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: false, category: .buttonDown),
            "Mouse button down without zoom should use CGEvent")
    }

    func testZoomNotActive_buttonUp_usesCGEvent() {
        XCTAssertFalse(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: false, category: .buttonUp),
            "Mouse button up without zoom should use CGEvent")
    }

    // MARK: - Zoom active, mouse move → CGEvent

    func testZoomActive_move_usesCGEvent() {
        XCTAssertFalse(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: true, category: .move),
            "Mouse move during zoom should use CGEvent")
    }

    // MARK: - Zoom active, button events → IOHIDPostEvent (avoids cursor flash)

    func testZoomActive_buttonDown_useIOHIDPostEvent() {
        XCTAssertTrue(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: true, category: .buttonDown),
            "Mouse button down during zoom must use IOHIDPostEvent to avoid cursor flash")
    }

    func testZoomActive_buttonUp_useIOHIDPostEvent() {
        XCTAssertTrue(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: true, category: .buttonUp),
            "Mouse button up during zoom must use IOHIDPostEvent to avoid cursor flash")
    }

    // MARK: - Zoom active, drag events → IOHIDPostEvent (avoids cursor flash)

    func testZoomActive_drag_useIOHIDPostEvent() {
        XCTAssertTrue(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: true, category: .drag),
            "Mouse drag during zoom must use IOHIDPostEvent to avoid cursor flash")
    }

    // MARK: - Cursor-position forcing

    func testZoomActive_onlyMoveAvoidsSetCursorPosition() {
        // Comprehensive check: during zoom, only .move should be relative-only
        let categories: [ZoomMouseEventPolicy.MouseEventCategory] = [
            .move, .drag, .buttonDown, .buttonUp
        ]

        let results = categories.map {
            ZoomMouseEventPolicy.shouldSetCursorPositionInIOHIDEvent(zoomActive: true, category: $0)
        }

        XCTAssertEqual(results, [false, true, true, true],
            "During zoom: move=CGEvent, drag/buttonDown/buttonUp=set cursor position")
    }

    func testZoomNotActive_noCategoriesSetCursorPosition() {
        let categories: [ZoomMouseEventPolicy.MouseEventCategory] = [
            .move, .drag, .buttonDown, .buttonUp
        ]

        let results = categories.map {
            ZoomMouseEventPolicy.shouldSetCursorPositionInIOHIDEvent(zoomActive: false, category: $0)
        }

        XCTAssertTrue(results.allSatisfy { !$0 },
            "Without zoom, IOHID events should not force cursor position")
    }
}
