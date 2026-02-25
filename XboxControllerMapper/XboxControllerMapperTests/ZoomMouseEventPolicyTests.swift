import XCTest
@testable import ControllerKeys

final class ZoomMouseEventPolicyTests: XCTestCase {

    // MARK: - Zoom not active → always CGEvent (never IOHIDPostEvent)

    func testZoomNotActive_move_useCGEvent() {
        XCTAssertFalse(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: false, category: .move),
            "Mouse move without zoom should use CGEvent")
    }

    func testZoomNotActive_drag_useCGEvent() {
        XCTAssertFalse(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: false, category: .drag),
            "Mouse drag without zoom should use CGEvent")
    }

    func testZoomNotActive_buttonDown_useCGEvent() {
        XCTAssertFalse(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: false, category: .buttonDown),
            "Mouse button down without zoom should use CGEvent")
    }

    func testZoomNotActive_buttonUp_useCGEvent() {
        XCTAssertFalse(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: false, category: .buttonUp),
            "Mouse button up without zoom should use CGEvent")
    }

    // MARK: - Zoom active, mouse move → CGEvent (no flash for .mouseMoved)

    func testZoomActive_move_useCGEvent() {
        XCTAssertFalse(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: true, category: .move),
            "Mouse move during zoom should use CGEvent (moves don't cause cursor flash)")
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

    // MARK: - All zoom-active categories summary

    func testZoomActive_onlyMoveUsesCGEvent() {
        // Comprehensive check: during zoom, only .move should use CGEvent
        let categories: [ZoomMouseEventPolicy.MouseEventCategory] = [
            .move, .drag, .buttonDown, .buttonUp
        ]

        let results = categories.map {
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: true, category: $0)
        }

        XCTAssertEqual(results, [false, true, true, true],
            "During zoom: move=CGEvent, drag/buttonDown/buttonUp=IOHIDPostEvent")
    }

    func testZoomNotActive_allCategoriesUseCGEvent() {
        let categories: [ZoomMouseEventPolicy.MouseEventCategory] = [
            .move, .drag, .buttonDown, .buttonUp
        ]

        let results = categories.map {
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: false, category: $0)
        }

        XCTAssertTrue(results.allSatisfy { !$0 },
            "Without zoom, all categories should use CGEvent")
    }
}
