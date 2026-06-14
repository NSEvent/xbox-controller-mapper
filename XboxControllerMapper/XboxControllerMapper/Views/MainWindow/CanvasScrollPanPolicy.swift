import Foundation

enum CanvasScrollPanPolicy {
    static func shouldHandleScroll(
        pointerInCanvas: Bool,
        eventWindowNumber: Int?,
        canvasWindowNumber: Int?,
        eventWindowHasAttachedSheet: Bool,
        eventWindowIsSheet: Bool
    ) -> Bool {
        guard pointerInCanvas,
              let eventWindowNumber,
              let canvasWindowNumber,
              eventWindowNumber == canvasWindowNumber else {
            return false
        }

        return !eventWindowHasAttachedSheet && !eventWindowIsSheet
    }
}
