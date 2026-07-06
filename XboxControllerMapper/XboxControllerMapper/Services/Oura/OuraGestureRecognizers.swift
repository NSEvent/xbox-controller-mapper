import CoreGraphics
import Foundation

enum OuraDirectionalFlick: Equatable {
	case up
	case down
	case left
	case right

	var button: ControllerButton {
		switch self {
		case .up: return .ouraFlickUp
		case .down: return .ouraFlickDown
		case .left: return .ouraFlickLeft
		case .right: return .ouraFlickRight
		}
	}

	var diagnosticName: String {
		switch self {
		case .up: return "up"
		case .down: return "down"
		case .left: return "left"
		case .right: return "right"
		}
	}
}

// holdDuration/settleDuration/drift/step tuned offline against the 2026-07-05
// labeled session (Tools/oura-calibration/tune_gestures.py), same pass as the
// OuraTapDetector thresholds.
struct OuraTapHoldRecognizer {
	// 0.36 → 0.6 (2026-07-06): a tap followed by the hand naturally resting
	// was firing as a hold; 0.6s of stillness makes holds deliberate. Must
	// stay under the tap-sequence resolution (~0.77s) or the hold can never
	// fire — resolution cancels the candidate.
	private static let holdDuration: CFTimeInterval = 0.6
	private static let settleDuration: CFTimeInterval = 0.09
	// Stillness tightened 2026-07-06 (live: 42% of taps fired as holds): the
	// tuner's loose 0.44/0.45 drift bounds tolerated a gently MOVING hand.
	// 0.25g + 0.35s of real stillness keeps prompted holds at 11/12 while
	// zeroing spurious holds in tap trials (v2 replay 197→199/214).
	private static let minimumStillDuration: CFTimeInterval = 0.35
	private static let maximumHoldDuration: CFTimeInterval = 1.2
	private static let maximumAnchorDrift = 0.25
	private static let maximumSampleStep = 0.25

	private var candidate: Candidate?
	private var previousSample: OuraMotionSample?

	mutating func reset() {
		candidate = nil
		previousSample = nil
	}

	mutating func registerTap(at timestamp: CFAbsoluteTime, sample: OuraMotionSample?) {
		guard let sample else {
			reset()
			return
		}
		candidate = Candidate(startTime: timestamp)
		previousSample = sample
	}

	mutating func cancel() {
		candidate = nil
	}

	mutating func registerMotion(_ sample: OuraMotionSample) -> Bool {
		defer { previousSample = sample }
		guard var candidate else { return false }

		let elapsed = sample.timestamp - candidate.startTime
		guard elapsed >= 0 else { return false }
		guard elapsed <= Self.maximumHoldDuration else {
			self.candidate = nil
			return false
		}

		guard elapsed >= Self.settleDuration else {
			self.candidate = candidate
			return false
		}

		if candidate.anchor == nil {
			candidate.anchor = sample
			candidate.anchorTime = sample.timestamp
			self.candidate = candidate
			return false
		}

		guard let anchor = candidate.anchor, let anchorTime = candidate.anchorTime else {
			self.candidate = nil
			return false
		}

		if distance(sample, anchor) > Self.maximumAnchorDrift {
			self.candidate = nil
			return false
		}
		if let previousSample, previousSample.timestamp >= anchorTime,
		   distance(sample, previousSample) > Self.maximumSampleStep {
			self.candidate = nil
			return false
		}

		guard elapsed >= Self.holdDuration,
		      sample.timestamp - anchorTime >= Self.minimumStillDuration else {
			self.candidate = candidate
			return false
		}
		self.candidate = nil
		return true
	}

	private func distance(_ a: OuraMotionSample, _ b: OuraMotionSample) -> Double {
		let x = a.x - b.x
		let y = a.y - b.y
		let z = a.z - b.z
		return sqrt(x * x + y * y + z * z)
	}

	private struct Candidate {
		let startTime: CFAbsoluteTime
		var anchor: OuraMotionSample?
		var anchorTime: CFAbsoluteTime?
	}
}

struct OuraDirectionalFlickRecognizer {
	private static let returnDistanceThreshold = 0.24
	private static let minimumSnapDistance = 0.48
	private static let minimumSnapVelocity = 2.4
	private static let axisDominanceRatio = 1.55
	private static let maximumSnapDuration: CFTimeInterval = 0.32
	private static let maximumReturnDuration: CFTimeInterval = 0.45
	private static let cooldown: CFTimeInterval = 0.65

	private var previousPoint: CGPoint?
	private var previousTimestamp: CFAbsoluteTime?
	private var candidate: Candidate?
	private var cooldownUntil: CFAbsoluteTime = 0

	mutating func reset() {
		previousPoint = nil
		previousTimestamp = nil
		candidate = nil
		cooldownUntil = 0
	}

	mutating func register(projectedInput point: CGPoint, timestamp: CFAbsoluteTime) -> OuraDirectionalFlick? {
		defer {
			previousPoint = point
			previousTimestamp = timestamp
		}

		guard timestamp >= cooldownUntil else { return nil }
		if let candidate {
			return update(candidate: candidate, point: point, timestamp: timestamp)
		}
		guard let previousPoint, let previousTimestamp else { return nil }

		let dt = timestamp - previousTimestamp
		guard dt > 0, dt <= Self.maximumSnapDuration else { return nil }

		let dx = point.x - previousPoint.x
		let dy = point.y - previousPoint.y
		let snapDistance = hypot(dx, dy)
		guard snapDistance >= Self.minimumSnapDistance,
			  snapDistance / dt >= Self.minimumSnapVelocity,
			  let direction = dominantDirection(dx: dx, dy: dy) else {
			return nil
		}

		self.candidate = Candidate(
			direction: direction,
			startTime: previousTimestamp,
			peakTime: timestamp,
			start: previousPoint,
			peak: point
		)
		return nil
	}

	private mutating func update(
		candidate: Candidate,
		point: CGPoint,
		timestamp: CFAbsoluteTime
	) -> OuraDirectionalFlick? {
		let elapsedSincePeak = timestamp - candidate.peakTime
		guard elapsedSincePeak <= Self.maximumReturnDuration else {
			self.candidate = nil
			return nil
		}

		let currentCandidate: Candidate
		if distance(point, candidate.start) > distance(candidate.peak, candidate.start) {
			currentCandidate = Candidate(
				direction: candidate.direction,
				startTime: candidate.startTime,
				peakTime: timestamp,
				start: candidate.start,
				peak: point
			)
			self.candidate = currentCandidate
		} else {
			currentCandidate = candidate
		}

		guard distance(point, currentCandidate.start) <= Self.returnDistanceThreshold else { return nil }
		self.candidate = nil
		cooldownUntil = timestamp + Self.cooldown
		return currentCandidate.direction
	}

	private func dominantDirection(dx: CGFloat, dy: CGFloat) -> OuraDirectionalFlick? {
		let absX = abs(dx)
		let absY = abs(dy)
		if absX > absY * Self.axisDominanceRatio {
			return dx > 0 ? .right : .left
		}
		if absY > absX * Self.axisDominanceRatio {
			return dy > 0 ? .up : .down
		}
		return nil
	}

	private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
		hypot(Double(a.x - b.x), Double(a.y - b.y))
	}

	private struct Candidate {
		let direction: OuraDirectionalFlick
		let startTime: CFAbsoluteTime
		let peakTime: CFAbsoluteTime
		let start: CGPoint
		let peak: CGPoint
	}
}
