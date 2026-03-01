import XCTest
import CoreGraphics
@testable import ControllerKeys

final class OverlayPositionPolicyTests: XCTestCase {

    // Standard test screen: 1920×1080, origin at (0,0) in NS coords
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    // MARK: - Flashing bug exposure tests
    //
    // These tests demonstrate WHY system APIs can't be used during zoom.
    // NSEvent.mouseLocation oscillates between the virtual (absolute) and visual
    // (physical) cursor positions during Accessibility Zoom, causing overlays to
    // flash between two locations. The policy must ignore the fallback entirely
    // when zoom is active and a tracked position is available.

    func testZoomActive_positionIsIndependentOfFallback() {
        // The flashing bug: NSEvent.mouseLocation returns different values on
        // alternating reads. If the policy uses it, overlays flash between positions.
        let tracked = CGPoint(x: 500, y: 300)

        // Simulate two different fallback readings (the bug)
        let absoluteFallback = CGPoint(x: 500, y: 780)  // Virtual position in NS coords
        let visualFallback = CGPoint(x: 960, y: 540)    // Physical/visual position

        let result1 = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 2.0,
            trackedCursorPosition: tracked,
            fallbackCursorLocation: absoluteFallback,
            screenFrame: screen
        )

        let result2 = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 2.0,
            trackedCursorPosition: tracked,
            fallbackCursorLocation: visualFallback,
            screenFrame: screen
        )

        XCTAssertEqual(result1, result2,
            "When zoom is active with a tracked position, the result must NOT depend on " +
            "fallbackCursorLocation — using it causes the flashing bug")
    }

    func testZoomActive_multipleCallsReturnConsistentPosition() {
        // The policy must be deterministic — same inputs always produce same output.
        // This is what prevents flashing: no system API reads, pure computation.
        let tracked = CGPoint(x: 700, y: 400)
        let fallback = CGPoint(x: 123, y: 456) // irrelevant during zoom

        var results: [CGPoint] = []
        for _ in 0..<10 {
            results.append(OverlayPositionPolicy.cursorScreenPosition(
                zoomActive: true, zoomLevel: 3.0,
                trackedCursorPosition: tracked,
                fallbackCursorLocation: fallback,
                screenFrame: screen
            ))
        }

        let first = results[0]
        for (i, result) in results.enumerated() {
            XCTAssertEqual(result, first,
                "Call \(i) returned different position — would cause flashing")
        }
    }

    // MARK: - Cursor at screen center (zoom viewport centered on cursor)

    func testZoomActive_cursorAtCenter_appearsAtScreenCenter() {
        // When cursor is at virtual center, zoom viewport centers perfectly.
        // Cursor should appear at physical center of display.
        let center = CGPoint(x: 960, y: 540)

        let result = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 2.0,
            trackedCursorPosition: center,
            fallbackCursorLocation: .zero,
            screenFrame: screen
        )

        // Physical center in NS coords: (960, 540)
        XCTAssertEqual(result.x, 960, accuracy: 0.01)
        XCTAssertEqual(result.y, 540, accuracy: 0.01)
    }

    func testZoomActive_cursorAtCenter_variousZoomLevels() {
        let center = CGPoint(x: 960, y: 540)

        for zoom: CGFloat in [1.5, 2.0, 3.0, 5.0, 10.0] {
            let result = OverlayPositionPolicy.cursorScreenPosition(
                zoomActive: true, zoomLevel: zoom,
                trackedCursorPosition: center,
                fallbackCursorLocation: .zero,
                screenFrame: screen
            )
            XCTAssertEqual(result.x, 960, accuracy: 0.01,
                "At zoom \(zoom)×, centered cursor should appear at screen center X")
            XCTAssertEqual(result.y, 540, accuracy: 0.01,
                "At zoom \(zoom)×, centered cursor should appear at screen center Y")
        }
    }

    // MARK: - Cursor at screen edges (viewport clamps)

    func testZoomActive_cursorAtTopLeftCorner() {
        let topLeft = CGPoint(x: 0, y: 0) // CG coords: top-left

        let result = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 2.0,
            trackedCursorPosition: topLeft,
            fallbackCursorLocation: .zero,
            screenFrame: screen
        )

        // At 2× zoom, viewport is 960×540. At top-left corner, viewport clamps
        // so its center is at (480, 270). Cursor at (0,0):
        //   physicalX = (0 - 480) × 2 + 960 = 0
        //   physicalY = (0 - 270) × 2 + 540 = 0
        //   nsY = 1080 - 0 = 1080
        XCTAssertEqual(result.x, 0, accuracy: 0.01,
            "Cursor at left edge should appear at physical left edge")
        XCTAssertEqual(result.y, 1080, accuracy: 0.01,
            "Cursor at CG top (y=0) should map to NS top (y=screenHeight)")
    }

    func testZoomActive_cursorAtBottomRightCorner() {
        let bottomRight = CGPoint(x: 1920, y: 1080) // CG coords

        let result = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 2.0,
            trackedCursorPosition: bottomRight,
            fallbackCursorLocation: .zero,
            screenFrame: screen
        )

        // At 2× zoom, viewport center clamps to (1440, 810).
        //   physicalX = (1920 - 1440) × 2 + 960 = 1920
        //   physicalY = (1080 - 810) × 2 + 540 = 1080
        //   nsY = 1080 - 1080 = 0
        XCTAssertEqual(result.x, 1920, accuracy: 0.01,
            "Cursor at right edge should appear at physical right edge")
        XCTAssertEqual(result.y, 0, accuracy: 0.01,
            "Cursor at CG bottom (y=screenH) should map to NS bottom (y=0)")
    }

    func testZoomActive_cursorNearLeftEdge_shiftsFromCenter() {
        // Cursor near left edge but not at corner
        let nearLeft = CGPoint(x: 100, y: 540)

        let result = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 2.0,
            trackedCursorPosition: nearLeft,
            fallbackCursorLocation: .zero,
            screenFrame: screen
        )

        // Cursor should appear to the left of center on physical display
        XCTAssertLessThan(result.x, 960,
            "Cursor near left edge should appear left of physical center")
        XCTAssertGreaterThanOrEqual(result.x, 0,
            "Cursor should not appear off-screen")
    }

    // MARK: - Zoom at 1× (effectively no zoom)

    func testZoomActive_zoomLevel1_usesFallback() {
        let tracked = CGPoint(x: 500, y: 300)
        let fallback = CGPoint(x: 742, y: 500)

        let result = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 1.0,
            trackedCursorPosition: tracked,
            fallbackCursorLocation: fallback,
            screenFrame: screen
        )

        // At zoom 1×, system APIs are reliable — use fallback
        XCTAssertEqual(result, fallback,
            "At zoom level 1.0, should use fallback (system APIs are reliable)")
    }

    // MARK: - Zoom not active

    func testZoomNotActive_alwaysUsesFallback() {
        let tracked = CGPoint(x: 500, y: 300)
        let fallback = CGPoint(x: 742, y: 500)

        let result = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: false, zoomLevel: 2.0,
            trackedCursorPosition: tracked,
            fallbackCursorLocation: fallback,
            screenFrame: screen
        )

        XCTAssertEqual(result, fallback,
            "When zoom is not active, should always use fallback regardless of tracked position")
    }

    func testZoomNotActive_nilTrackedPosition_usesFallback() {
        let fallback = CGPoint(x: 200, y: 800)

        let result = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: false, zoomLevel: 1.0,
            trackedCursorPosition: nil,
            fallbackCursorLocation: fallback,
            screenFrame: screen
        )

        XCTAssertEqual(result, fallback)
    }

    // MARK: - No tracked position during zoom (fallback to center)

    func testZoomActive_noTrackedPosition_returnsScreenCenter() {
        let result = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 2.0,
            trackedCursorPosition: nil,
            fallbackCursorLocation: CGPoint(x: 100, y: 100),
            screenFrame: screen
        )

        XCTAssertEqual(result.x, 960, accuracy: 0.01,
            "Without tracked position during zoom, should approximate at screen center X")
        XCTAssertEqual(result.y, 540, accuracy: 0.01,
            "Without tracked position during zoom, should approximate at screen center Y")
    }

    func testZoomActive_noTrackedPosition_ignoresFallback() {
        let result1 = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 3.0,
            trackedCursorPosition: nil,
            fallbackCursorLocation: CGPoint(x: 0, y: 0),
            screenFrame: screen
        )

        let result2 = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 3.0,
            trackedCursorPosition: nil,
            fallbackCursorLocation: CGPoint(x: 1920, y: 1080),
            screenFrame: screen
        )

        XCTAssertEqual(result1, result2,
            "Even without tracked position, zoom should not use unreliable fallback")
    }

    // MARK: - Different screen sizes

    func testDifferentScreenSizes() {
        for (width, height): (CGFloat, CGFloat) in [(2560, 1440), (1440, 900), (3840, 2160)] {
            let screenFrame = CGRect(x: 0, y: 0, width: width, height: height)
            let center = CGPoint(x: width / 2, y: height / 2)

            let result = OverlayPositionPolicy.cursorScreenPosition(
                zoomActive: true, zoomLevel: 2.0,
                trackedCursorPosition: center,
                fallbackCursorLocation: .zero,
                screenFrame: screenFrame
            )

            XCTAssertEqual(result.x, width / 2, accuracy: 0.01,
                "Centered cursor on \(Int(width))×\(Int(height)) screen")
            XCTAssertEqual(result.y, height / 2, accuracy: 0.01,
                "Centered cursor on \(Int(width))×\(Int(height)) screen")
        }
    }

    // MARK: - Multi-display (screen with non-zero origin)

    func testScreenWithNonZeroOrigin() {
        // Secondary display to the right of the main display
        let secondaryScreen = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let center = CGPoint(x: 960, y: 540) // Center of the secondary display in CG

        let result = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 2.0,
            trackedCursorPosition: center,
            fallbackCursorLocation: .zero,
            screenFrame: secondaryScreen
        )

        // Physical center of secondary display in NS coords:
        // nsX = 1920 + 960 = 2880, nsY = 0 + 1080 - 540 = 540
        XCTAssertEqual(result.x, 2880, accuracy: 0.01,
            "Should account for screen origin X offset")
        XCTAssertEqual(result.y, 540, accuracy: 0.01,
            "Should account for screen origin in NS coords")
    }

    // MARK: - High zoom levels

    func testHighZoomLevel_cursorStillAtCenter() {
        let tracked = CGPoint(x: 960, y: 540)

        let result = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 20.0,
            trackedCursorPosition: tracked,
            fallbackCursorLocation: .zero,
            screenFrame: screen
        )

        XCTAssertEqual(result.x, 960, accuracy: 0.01)
        XCTAssertEqual(result.y, 540, accuracy: 0.01)
    }

    func testHighZoomLevel_cursorAtEdge() {
        let tracked = CGPoint(x: 50, y: 50)

        let result = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 10.0,
            trackedCursorPosition: tracked,
            fallbackCursorLocation: .zero,
            screenFrame: screen
        )

        // At 10× zoom, viewport is 192×108. Center clamps to (96, 54).
        //   physicalX = (50 - 96) × 10 + 960 = -460 + 960 = 500
        //   physicalY = (50 - 54) × 10 + 540 = -40 + 540 = 500
        //   nsY = 1080 - 500 = 580
        XCTAssertEqual(result.x, 500, accuracy: 0.01)
        XCTAssertEqual(result.y, 580, accuracy: 0.01)
    }

    // MARK: - Symmetry

    func testSymmetricPositions_produceMirroredResults() {
        // Cursor equidistant from center in opposite directions should produce
        // mirrored physical positions
        let left = CGPoint(x: 460, y: 540)
        let right = CGPoint(x: 1460, y: 540)

        let leftResult = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 2.0,
            trackedCursorPosition: left,
            fallbackCursorLocation: .zero,
            screenFrame: screen
        )

        let rightResult = OverlayPositionPolicy.cursorScreenPosition(
            zoomActive: true, zoomLevel: 2.0,
            trackedCursorPosition: right,
            fallbackCursorLocation: .zero,
            screenFrame: screen
        )

        // Both are within the non-clamped range, so they should be symmetric around center
        let leftOffset = 960 - leftResult.x
        let rightOffset = rightResult.x - 960
        XCTAssertEqual(leftOffset, rightOffset, accuracy: 0.01,
            "Symmetric virtual positions should produce symmetric physical positions")
    }
}
