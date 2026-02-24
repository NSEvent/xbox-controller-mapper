import XCTest
import CoreGraphics
@testable import ControllerKeys

final class MouseClickLocationPolicyTests: XCTestCase {

    // Shared test constants
    private let primaryHeight: CGFloat = 1080
    private let maxAge: TimeInterval = 2.0

    // MARK: - Zoom active with fresh tracked position → use tracked

    func testZoomActive_freshTrackedPosition_returnsTrackedPosition() {
        let tracked = CGPoint(x: 700, y: 420)
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now.addingTimeInterval(-0.1),
            fallbackMouseLocation: CGPoint(x: 999, y: 999),
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        XCTAssertEqual(result, tracked,
            "When zoom is active and tracked position is recent, should return the tracked absolute position")
    }

    func testZoomActive_trackedPosition_ignoreFallbackEntirely() {
        // Verify the fallback mouse location and display height are irrelevant
        // when the tracked position path is taken
        let tracked = CGPoint(x: 100, y: 200)
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now,
            fallbackMouseLocation: CGPoint(x: 0, y: 0),
            primaryDisplayHeight: 0,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        XCTAssertEqual(result, tracked,
            "Tracked path should not use fallbackMouseLocation or primaryDisplayHeight at all")
    }

    func testZoomActive_moveTimeExactlyAtMaxAge_returnsTrackedPosition() {
        // Boundary: moveTime is exactly maxAge seconds ago (<=, not <)
        let tracked = CGPoint(x: 500, y: 300)
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now.addingTimeInterval(-maxAge),
            fallbackMouseLocation: CGPoint(x: 0, y: 0),
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        XCTAssertEqual(result, tracked,
            "Tracked position age exactly at maxAge should still be accepted (<=)")
    }

    // MARK: - Zoom active but tracked position stale → fallback

    func testZoomActive_trackedPositionJustOverMaxAge_fallsBackToSystem() {
        let tracked = CGPoint(x: 500, y: 300)
        let fallback = CGPoint(x: 200, y: 100)
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now.addingTimeInterval(-maxAge - 0.001),
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        let expected = CGPoint(x: fallback.x, y: primaryHeight - fallback.y)
        XCTAssertEqual(result, expected,
            "Tracked position just over maxAge should fall back to system position")
    }

    func testZoomActive_trackedPositionVeryStale_fallsBackToSystem() {
        let tracked = CGPoint(x: 900, y: 700)
        let fallback = CGPoint(x: 480, y: 330)
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now.addingTimeInterval(-60.0),
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        let expected = CGPoint(x: fallback.x, y: primaryHeight - fallback.y)
        XCTAssertEqual(result, expected,
            "Very stale tracked position should fall back to system position")
    }

    // MARK: - Zoom active but no tracked position → fallback

    func testZoomActive_nilTrackedPosition_fallsBackToSystem() {
        let fallback = CGPoint(x: 320, y: 640)
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: nil,
            lastControllerMoveTime: now,
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        let expected = CGPoint(x: fallback.x, y: primaryHeight - fallback.y)
        XCTAssertEqual(result, expected,
            "Nil tracked position with zoom active should fall back to system position")
    }

    // MARK: - Zoom not active → always fallback (ignores tracked)

    func testZoomNotActive_withFreshTrackedPosition_stillFallsBackToSystem() {
        let tracked = CGPoint(x: 700, y: 420)
        let fallback = CGPoint(x: 150, y: 200)
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: false,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now,
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        let expected = CGPoint(x: fallback.x, y: primaryHeight - fallback.y)
        XCTAssertEqual(result, expected,
            "When zoom is not active, tracked position should be ignored even if fresh")
    }

    func testZoomNotActive_nilTrackedPosition_fallsBackToSystem() {
        let fallback = CGPoint(x: 100, y: 50)
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: false,
            trackedCursorPosition: nil,
            lastControllerMoveTime: now,
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        let expected = CGPoint(x: fallback.x, y: primaryHeight - fallback.y)
        XCTAssertEqual(result, expected)
    }

    // MARK: - Y-coordinate flipping in fallback path

    func testFallback_yCoordinateFlipsFromNSToCS() {
        // NSEvent.mouseLocation uses bottom-left origin (y=0 at bottom).
        // CG coordinates use top-left origin (y=0 at top).
        // The policy must convert: cgY = primaryDisplayHeight - nsY
        let now = Date()

        // Cursor at bottom of screen in NS coords (y near 0)
        let bottomResult = MouseClickLocationPolicy.resolve(
            zoomActive: false,
            trackedCursorPosition: nil,
            lastControllerMoveTime: now,
            fallbackMouseLocation: CGPoint(x: 100, y: 0),
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )
        XCTAssertEqual(bottomResult.y, primaryHeight,
            "NS y=0 (bottom of screen) should map to CG y=displayHeight (bottom)")

        // Cursor at top of screen in NS coords (y = displayHeight)
        let topResult = MouseClickLocationPolicy.resolve(
            zoomActive: false,
            trackedCursorPosition: nil,
            lastControllerMoveTime: now,
            fallbackMouseLocation: CGPoint(x: 100, y: primaryHeight),
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )
        XCTAssertEqual(topResult.y, 0,
            "NS y=displayHeight (top of screen) should map to CG y=0 (top)")
    }

    func testFallback_xCoordinatePassedThrough() {
        // X coordinate should be identical between NS and CG (both origin at left)
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: false,
            trackedCursorPosition: nil,
            lastControllerMoveTime: now,
            fallbackMouseLocation: CGPoint(x: 742, y: 500),
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        XCTAssertEqual(result.x, 742,
            "Fallback path should pass X coordinate through unchanged")
    }

    // MARK: - Different display sizes

    func testFallback_differentDisplayHeights() {
        let now = Date()
        let fallback = CGPoint(x: 100, y: 300)

        for height: CGFloat in [900, 1080, 1440, 2160] {
            let result = MouseClickLocationPolicy.resolve(
                zoomActive: false,
                trackedCursorPosition: nil,
                lastControllerMoveTime: now,
                fallbackMouseLocation: fallback,
                primaryDisplayHeight: height,
                now: now,
                trackedCursorMaxAge: maxAge
            )
            XCTAssertEqual(result.y, height - fallback.y,
                "Y flip should work correctly for display height \(height)")
        }
    }

    // MARK: - Edge coordinates

    func testTrackedPosition_atOrigin() {
        let now = Date()
        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: CGPoint(x: 0, y: 0),
            lastControllerMoveTime: now,
            fallbackMouseLocation: CGPoint(x: 999, y: 999),
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )
        XCTAssertEqual(result, CGPoint(x: 0, y: 0),
            "Tracked position at origin should be returned as-is")
    }

    func testTrackedPosition_atMaxScreenBounds() {
        let now = Date()
        let tracked = CGPoint(x: 2559, y: 1439) // e.g. bottom-right of a 2560x1440 display
        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now,
            fallbackMouseLocation: CGPoint(x: 0, y: 0),
            primaryDisplayHeight: 1440,
            now: now,
            trackedCursorMaxAge: maxAge
        )
        XCTAssertEqual(result, tracked,
            "Tracked position at screen edge should be returned as-is")
    }

    // MARK: - maxAge = 0 (instant expiry)

    func testZeroMaxAge_simultaneousMoveAndClick_returnsTracked() {
        let now = Date()
        let tracked = CGPoint(x: 400, y: 400)

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now,
            fallbackMouseLocation: CGPoint(x: 0, y: 0),
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: 0
        )
        XCTAssertEqual(result, tracked,
            "With maxAge=0, move at same instant as click should still use tracked (0 <= 0)")
    }

    func testZeroMaxAge_anyDelay_fallsBackToSystem() {
        let now = Date()
        let fallback = CGPoint(x: 100, y: 100)

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: CGPoint(x: 400, y: 400),
            lastControllerMoveTime: now.addingTimeInterval(-0.001),
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: 0
        )

        let expected = CGPoint(x: fallback.x, y: primaryHeight - fallback.y)
        XCTAssertEqual(result, expected,
            "With maxAge=0, even tiny delay should fall back to system")
    }

    // MARK: - Tracked position is CG coordinates (not NS)

    func testTrackedPosition_isReturnedWithoutYFlip() {
        // The tracked position is already in CG coordinate space (top-left origin).
        // It must NOT be Y-flipped when returned.
        let now = Date()
        let tracked = CGPoint(x: 500, y: 100)  // Near top of screen in CG

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now,
            fallbackMouseLocation: CGPoint(x: 0, y: 0),
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        XCTAssertEqual(result.y, 100,
            "Tracked position should be returned as-is without Y coordinate flipping")
    }
}
