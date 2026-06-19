import CoreGraphics

enum LayoutMeasurementPolicy {
	static let pointTolerance: CGFloat = 0.5

	static func normalizedDimension(_ value: CGFloat) -> CGFloat {
		guard value.isFinite, value > 0 else { return 0 }
		return value.rounded(.toNearestOrAwayFromZero)
	}

	static func normalizedSize(_ size: CGSize) -> CGSize {
		CGSize(
			width: normalizedDimension(size.width),
			height: normalizedDimension(size.height)
		)
	}

	static func shouldUpdate(current: CGFloat, proposed: CGFloat, tolerance: CGFloat = pointTolerance) -> Bool {
		abs(current - proposed) > tolerance
	}

	static func shouldUpdate(current: CGSize, proposed: CGSize, tolerance: CGFloat = pointTolerance) -> Bool {
		shouldUpdate(current: current.width, proposed: proposed.width, tolerance: tolerance) ||
			shouldUpdate(current: current.height, proposed: proposed.height, tolerance: tolerance)
	}
}
