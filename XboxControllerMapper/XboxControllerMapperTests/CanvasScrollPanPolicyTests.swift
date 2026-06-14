import XCTest
@testable import ControllerKeys

final class CanvasScrollPanPolicyTests: XCTestCase {
    func testHandlesScrollInsideCanvasWindow() {
        XCTAssertTrue(CanvasScrollPanPolicy.shouldHandleScroll(
            pointerInCanvas: true,
            eventWindowNumber: 12,
            canvasWindowNumber: 12,
            eventWindowHasAttachedSheet: false,
            eventWindowIsSheet: false
        ))
    }

    func testIgnoresScrollOutsideCanvas() {
        XCTAssertFalse(CanvasScrollPanPolicy.shouldHandleScroll(
            pointerInCanvas: false,
            eventWindowNumber: 12,
            canvasWindowNumber: 12,
            eventWindowHasAttachedSheet: false,
            eventWindowIsSheet: false
        ))
    }

    func testIgnoresScrollFromSheetWindowEvenWhenCoordinatesOverlap() {
        XCTAssertFalse(CanvasScrollPanPolicy.shouldHandleScroll(
            pointerInCanvas: true,
            eventWindowNumber: 99,
            canvasWindowNumber: 12,
            eventWindowHasAttachedSheet: false,
            eventWindowIsSheet: true
        ))
    }

    func testIgnoresParentWindowWhileAttachedSheetIsOpen() {
        XCTAssertFalse(CanvasScrollPanPolicy.shouldHandleScroll(
            pointerInCanvas: true,
            eventWindowNumber: 12,
            canvasWindowNumber: 12,
            eventWindowHasAttachedSheet: true,
            eventWindowIsSheet: false
        ))
    }
}
