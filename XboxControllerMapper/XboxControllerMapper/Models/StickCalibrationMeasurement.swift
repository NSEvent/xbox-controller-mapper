import Foundation
import CoreGraphics

/// Measurements use raw normalized input, before profile response curves.
nonisolated struct StickCalibrationMeasurement {
	private(set) var restSamples = 0
	private(set) var restPeak = 0.0
	private(set) var rangePeaks = Array(repeating: 0.0, count: 8)

	mutating func recordRest(_ point: CGPoint) {
		let radius = hypot(Double(point.x), Double(point.y))
		guard radius.isFinite else { return }
		restSamples += 1
		restPeak = max(restPeak, radius)
	}

	mutating func recordRange(_ point: CGPoint) {
		let radius = hypot(Double(point.x), Double(point.y))
		guard radius.isFinite else { return }
		let angle = atan2(Double(point.y), Double(point.x)) + .pi
		let sector = min(7, Int(angle / (2 * .pi) * 8))
		rangePeaks[sector] = max(rangePeaks[sector], radius)
	}

	var suggestedInner: Double? {
		guard restSamples >= 45, restPeak < 0.4 else { return nil }
		return min(0.45, max(0.02, restPeak + 0.03))
	}
	var suggestedOuter: Double? {
		guard rangePeaks.allSatisfy({ $0 >= 0.5 }) else { return nil }
		return min(1, max(0.5, (rangePeaks.min() ?? 1) - 0.02))
	}
	var directionsMeasured: Int { rangePeaks.filter { $0 >= 0.5 }.count }

	static func normalized(_ point: CGPoint, outerRange: Double) -> CGPoint {
		guard outerRange < 1 else { return point }
		let radius = hypot(Double(point.x), Double(point.y))
		guard radius > 0, radius.isFinite else { return .zero }
		let scale = min(radius / max(0.5, min(1, outerRange)), 1) / radius
		return CGPoint(x: Double(point.x) * scale, y: Double(point.y) * scale)
	}
}
