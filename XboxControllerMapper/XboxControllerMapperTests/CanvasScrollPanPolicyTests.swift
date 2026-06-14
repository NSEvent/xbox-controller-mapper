import XCTest
@testable import ControllerKeys

final class CanvasScrollPanPolicyTests: XCTestCase {
	func testContentBaseSizeUsesFallbackUntilMeasuredSizeArrives() {
		let fallback = CGSize(width: 980, height: 620)

		XCTAssertEqual(
			CanvasScrollPanPolicy.contentBaseSize(measuredSize: .zero, fallbackSize: fallback),
			fallback
		)
	}

	func testContentBaseSizeUsesMeasuredTallControllerLayout() {
		let fallback = CGSize(width: 980, height: 620)
		let measured = CGSize(width: 980, height: 840)

		XCTAssertEqual(
			CanvasScrollPanPolicy.contentBaseSize(measuredSize: measured, fallbackSize: fallback),
			measured
		)
	}

	func testTallMeasuredContentAllowsEnoughVerticalPan() {
		let clamped = CanvasScrollPanPolicy.clampedPan(
			CGSize(width: 0, height: 500),
			viewportSize: CGSize(width: 980, height: 620),
			contentSize: CGSize(width: 980, height: 840)
		)

		XCTAssertEqual(clamped.height, 110)
	}

	func testClampedPanLocksCenteredWhenContentFitsViewport() {
		let clamped = CanvasScrollPanPolicy.clampedPan(
			CGSize(width: 500, height: -500),
			viewportSize: CGSize(width: 800, height: 600),
			contentSize: CGSize(width: 700, height: 500)
		)

		XCTAssertEqual(clamped, .zero)
	}

	func testClampedPanLimitsEmptyOverscrollToContentOverflow() {
		let clamped = CanvasScrollPanPolicy.clampedPan(
			CGSize(width: 500, height: -500),
			viewportSize: CGSize(width: 800, height: 600),
			contentSize: CGSize(width: 1000, height: 900)
		)

		XCTAssertEqual(clamped.width, 100)
		XCTAssertEqual(clamped.height, -150)
	}

	func testClampedPanAllowsAxisIndependently() {
		let clamped = CanvasScrollPanPolicy.clampedPan(
			CGSize(width: -80, height: 200),
			viewportSize: CGSize(width: 800, height: 600),
			contentSize: CGSize(width: 960, height: 580)
		)

		XCTAssertEqual(clamped.width, -80)
		XCTAssertEqual(clamped.height, 0)
	}

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
