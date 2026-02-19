import Foundation
import CoreGraphics

struct MouseClickLocationPolicy {
    static func resolve(
        zoomActive: Bool,
        trackedCursorPosition: CGPoint?,
        lastControllerMoveTime: Date,
        fallbackMouseLocation: CGPoint,
        primaryDisplayHeight: CGFloat,
        now: Date,
        trackedCursorMaxAge: TimeInterval
    ) -> CGPoint {
        if zoomActive,
           let tracked = trackedCursorPosition,
           now.timeIntervalSince(lastControllerMoveTime) <= trackedCursorMaxAge {
            return tracked
        }

        return CGPoint(
            x: fallbackMouseLocation.x,
            y: primaryDisplayHeight - fallbackMouseLocation.y
        )
    }
}
