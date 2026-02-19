import XCTest
import CoreGraphics
@testable import ControllerKeys

final class MouseClickLocationPolicyTests: XCTestCase {
    func testResolveUsesTrackedPositionWhenZoomEnabledAndTrackedPositionIsRecent() {
        let tracked = CGPoint(x: 700, y: 420)
        let fallback = CGPoint(x: 150, y: 200)
        let primaryHeight: CGFloat = 1000
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now.addingTimeInterval(-0.2),
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: 2.0
        )

        XCTAssertEqual(result, tracked)
    }

    func testResolveFallsBackToSystemPositionWhenZoomDisabled() {
        let tracked = CGPoint(x: 700, y: 420)
        let fallback = CGPoint(x: 150, y: 200)
        let primaryHeight: CGFloat = 1000
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: false,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now,
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: 2.0
        )

        XCTAssertEqual(result, CGPoint(x: 150, y: 800))
    }

    func testResolveFallsBackToSystemPositionWhenTrackedIsMissing() {
        let fallback = CGPoint(x: 320, y: 640)
        let primaryHeight: CGFloat = 1200
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: nil,
            lastControllerMoveTime: now,
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: 2.0
        )

        XCTAssertEqual(result, CGPoint(x: 320, y: 560))
    }

    func testResolveFallsBackToSystemPositionWhenTrackedIsStale() {
        let tracked = CGPoint(x: 900, y: 700)
        let fallback = CGPoint(x: 480, y: 330)
        let primaryHeight: CGFloat = 900
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now.addingTimeInterval(-5.0),
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: 2.0
        )

        XCTAssertEqual(result, CGPoint(x: 480, y: 570))
    }
}
