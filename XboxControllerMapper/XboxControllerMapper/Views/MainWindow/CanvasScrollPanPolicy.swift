import Foundation

enum CanvasScrollPanPolicy {
	static func contentBaseSize(measuredSize: CGSize, fallbackSize: CGSize) -> CGSize {
		guard measuredSize.width > 0, measuredSize.height > 0 else {
			return fallbackSize
		}
		return measuredSize
	}

	static func clampedPan(
		_ pan: CGSize,
		viewportSize: CGSize,
		contentSize: CGSize
	) -> CGSize {
		let maxX = max(0, (contentSize.width - viewportSize.width) / 2)
		let maxY = max(0, (contentSize.height - viewportSize.height) / 2)
		return CGSize(
			width: min(max(pan.width, -maxX), maxX),
			height: min(max(pan.height, -maxY), maxY)
		)
	}

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
