import Foundation
import CoreGraphics

struct MouseClickLocationPolicy {
    static func resolve(
        zoomActive: Bool,
        trackedCursorPosition: CGPoint?,
        lastControllerMoveTime: CFAbsoluteTime,
        fallbackMouseLocation: CGPoint,
        primaryDisplayHeight: CGFloat,
        now: CFAbsoluteTime,
        trackedCursorMaxAge: TimeInterval
    ) -> CGPoint {
        if zoomActive,
           let tracked = trackedCursorPosition,
           now - lastControllerMoveTime <= trackedCursorMaxAge {
            return tracked
        }

        return CGPoint(
            x: fallbackMouseLocation.x,
            y: primaryDisplayHeight - fallbackMouseLocation.y
        )
    }
}
