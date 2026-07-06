import CoreGraphics
import Foundation

struct OuraMotionSample: Equatable {
	let x: Double
	let y: Double
	let z: Double
	let timestamp: CFAbsoluteTime
}

struct OuraMotionMappingResult {
	let centeredSample: OuraMotionSample
	let projectedInput: CGPoint
	let stick: CGPoint
	let didEstablishCenter: Bool
}

struct OuraMotionMapper {
	var settings: OuraMotionSettings {
		didSet {
			if oldValue.targetStick != settings.targetStick ||
				oldValue.enabled != settings.enabled ||
				oldValue.orientation != settings.orientation {
				reset()
			}
		}
	}

	private var smoothedStick: CGPoint = .zero
	private var neutralSample: OuraMotionSample?
	private var screenPlaneBasis: OuraScreenPlaneBasis?
	private var previousRawSample: OuraMotionSample?
	private var lowMotionStartTime: CFAbsoluteTime?

	private static let minimumOutputMagnitude = 0.18
	private static let softRecenterInputThreshold = 0.08
	private static let softRecenterRawDeltaThreshold = 0.020
	private static let softRecenterDelay: CFTimeInterval = 2.0
	private static let softRecenterAlpha = 0.008

	init(settings: OuraMotionSettings = .default) {
		self.settings = settings
	}

	mutating func reset() {
		smoothedStick = .zero
		neutralSample = nil
		screenPlaneBasis = nil
		previousRawSample = nil
		lowMotionStartTime = nil
	}

	mutating func stickPosition(for sample: OuraMotionSample) -> CGPoint {
		guard settings.enabled, settings.motionOutputEnabled else {
			return zeroOutput()
		}

		let input = projectedInput(for: sample)
		return stickPosition(forProjectedInput: input)
	}

	mutating func mappingResult(forRawSample sample: OuraMotionSample) -> OuraMotionMappingResult {
		guard settings.enabled else {
			smoothedStick = .zero
			return OuraMotionMappingResult(
				centeredSample: sample,
				projectedInput: .zero,
				stick: .zero,
				didEstablishCenter: false
			)
		}

		let centeredResult = centeredSample(for: sample)
		let projectedInput: CGPoint
		switch settings.orientation {
		case .screenPlane:
			projectedInput = screenPlaneInput(for: sample, centeredSample: centeredResult.sample)
			updateSoftRecenter(rawSample: sample, projectedInput: projectedInput)
		case .fingerToScreen, .legacyXY:
			projectedInput = self.projectedInput(for: centeredResult.sample)
		}

		return OuraMotionMappingResult(
			centeredSample: centeredResult.sample,
			projectedInput: projectedInput,
			stick: settings.motionOutputEnabled ? stickPosition(forProjectedInput: projectedInput) : zeroOutput(),
			didEstablishCenter: centeredResult.didEstablishCenter
		)
	}

	func projectedInput(for sample: OuraMotionSample) -> CGPoint {
		let projected: CGPoint
		switch settings.orientation {
		case .screenPlane:
			projected = CGPoint(x: sample.x, y: sample.y)
		case .fingerToScreen:
			projected = CGPoint(x: sample.x, y: sample.z)
		case .legacyXY:
			projected = CGPoint(x: sample.x, y: sample.y)
		}

		return applyInversion(to: projected)
	}

	private mutating func stickPosition(forProjectedInput input: CGPoint) -> CGPoint {
		let inputGain = 1.4 + settings.sensitivity * 4.6
		let rawX = input.x * inputGain
		let rawY = input.y * inputGain

		let magnitude = min(1.0, hypot(rawX, rawY))
		guard magnitude > settings.deadzone else {
			return smooth(.zero)
		}

		let xDirectionalBoost = rawX < 0 ? settings.leftTiltBoost : 1.0
		let x = rawX * settings.horizontalBoost * xDirectionalBoost
		let y = rawY
		let boostedMagnitude = min(1.0, hypot(x, y))
		let normalizedMagnitude = (magnitude - settings.deadzone) / (1.0 - settings.deadzone)
		let boostedNormalizedMagnitude = max(
			normalizedMagnitude,
			(boostedMagnitude - settings.deadzone) / (1.0 - settings.deadzone)
		)
		let outputMagnitude = Self.minimumOutputMagnitude + boostedNormalizedMagnitude * (1.0 - Self.minimumOutputMagnitude)
		let scale = outputMagnitude / max(hypot(x, y), 0.0001)
		return smooth(CGPoint(x: x * scale, y: y * scale))
	}

	private mutating func centeredSample(for sample: OuraMotionSample) -> (sample: OuraMotionSample, didEstablishCenter: Bool) {
		guard let neutralSample else {
			self.neutralSample = sample
			return (
				OuraMotionSample(x: 0, y: 0, z: 0, timestamp: sample.timestamp),
				true
			)
		}

		return (
			OuraMotionSample(
				x: sample.x - neutralSample.x,
				y: sample.y - neutralSample.y,
				z: sample.z - neutralSample.z,
				timestamp: sample.timestamp
			),
			false
		)
	}

	private mutating func screenPlaneInput(for sample: OuraMotionSample, centeredSample: OuraMotionSample) -> CGPoint {
		guard let current = OuraVector3(sample).normalized else {
			return .zero
		}
		if screenPlaneBasis == nil {
			screenPlaneBasis = OuraScreenPlaneBasis(neutral: current)
			return .zero
		}
		guard let screenPlaneBasis else { return .zero }

		let centered = OuraVector3(centeredSample)
		let planar = centered.projected(perpendicularTo: screenPlaneBasis.neutral)
		return applyInversion(to: CGPoint(
			x: -planar.dot(screenPlaneBasis.right),
			y: -planar.dot(screenPlaneBasis.up)
		))
	}

	private mutating func updateSoftRecenter(rawSample sample: OuraMotionSample, projectedInput: CGPoint) {
		defer { previousRawSample = sample }
		guard let previousRawSample, let neutralSample else { return }

		let inputMagnitude = Double(hypot(projectedInput.x, projectedInput.y))
		let rawDelta = hypot3(
			sample.x - previousRawSample.x,
			sample.y - previousRawSample.y,
			sample.z - previousRawSample.z
		)
		guard inputMagnitude < Self.softRecenterInputThreshold,
			  rawDelta < Self.softRecenterRawDeltaThreshold else {
			lowMotionStartTime = nil
			return
		}

		if lowMotionStartTime == nil {
			lowMotionStartTime = sample.timestamp
			return
		}
		guard let lowMotionStartTime,
			  sample.timestamp - lowMotionStartTime >= Self.softRecenterDelay else {
			return
		}

		let alpha = Self.softRecenterAlpha
		let updatedNeutral = OuraMotionSample(
			x: neutralSample.x + (sample.x - neutralSample.x) * alpha,
			y: neutralSample.y + (sample.y - neutralSample.y) * alpha,
			z: neutralSample.z + (sample.z - neutralSample.z) * alpha,
			timestamp: sample.timestamp
		)
		self.neutralSample = updatedNeutral
		if let neutral = OuraVector3(updatedNeutral).normalized {
			screenPlaneBasis = OuraScreenPlaneBasis(neutral: neutral)
		}
	}

	private func hypot3(_ x: Double, _ y: Double, _ z: Double) -> Double {
		sqrt(x * x + y * y + z * z)
	}

	private func applyInversion(to point: CGPoint) -> CGPoint {
		CGPoint(
			x: settings.invertX ? -point.x : point.x,
			y: settings.invertY ? -point.y : point.y
		)
	}

	private mutating func smooth(_ raw: CGPoint) -> CGPoint {
		let smoothing = min(1.0, max(0.0, settings.smoothing))
		let immediate = 1.0 - smoothing
		smoothedStick = CGPoint(
			x: smoothedStick.x * smoothing + raw.x * immediate,
			y: smoothedStick.y * smoothing + raw.y * immediate
		)
		return smoothedStick
	}

	private mutating func zeroOutput() -> CGPoint {
		smoothedStick = .zero
		return .zero
	}
}

private struct OuraScreenPlaneBasis {
	let neutral: OuraVector3
	let right: OuraVector3
	let up: OuraVector3

	init(neutral: OuraVector3) {
		let normalizedNeutral = neutral.normalized ?? OuraVector3(x: 0, y: 1, z: 0)
		self.neutral = normalizedNeutral

		let rightAxis = OuraVector3(x: 1, y: 0, z: 0)
		let upAxis = OuraVector3(x: 0, y: 0, z: 1)
		let fallbackAxis = OuraVector3(x: 0, y: 1, z: 0)

		let projectedRight = Self.projectedAxis(
			rightAxis,
			normal: normalizedNeutral,
			fallbacks: [upAxis, fallbackAxis]
		)
		self.right = projectedRight

		let projectedUp = (upAxis.projected(perpendicularTo: normalizedNeutral) - projectedRight * upAxis.dot(projectedRight)).normalized
		var resolvedUp: OuraVector3
		if let projectedUp {
			resolvedUp = projectedUp
		} else {
			resolvedUp = Self.projectedAxis(
				fallbackAxis,
				normal: normalizedNeutral,
				fallbacks: [upAxis, normalizedNeutral.cross(projectedRight)]
			)
		}
		// The pitch response is proportional to the neutral's y-component in
		// ring frame, which changes sign as the finger crosses level — so
		// centering with the finger level-or-raised inverted up/down (Kevin
		// 2026-07-06: cursor only correct when centering pointed slightly
		// down). Anchor the up axis to the negative-y convention so every
		// centering pose behaves like the working one.
		if normalizedNeutral.y > 0 {
			resolvedUp = resolvedUp * -1
		}
		self.up = resolvedUp
	}

	private static func projectedAxis(_ axis: OuraVector3, normal: OuraVector3, fallbacks: [OuraVector3]) -> OuraVector3 {
		let candidates = [axis] + fallbacks
		for candidate in candidates {
			if let projected = candidate.projected(perpendicularTo: normal).normalized {
				return projected
			}
		}
		return OuraVector3(x: 1, y: 0, z: 0)
	}
}

private struct OuraVector3: Equatable {
	let x: Double
	let y: Double
	let z: Double

	init(x: Double, y: Double, z: Double) {
		self.x = x
		self.y = y
		self.z = z
	}

	init(_ sample: OuraMotionSample) {
		self.init(x: sample.x, y: sample.y, z: sample.z)
	}

	var length: Double {
		sqrt(x * x + y * y + z * z)
	}

	var normalized: OuraVector3? {
		let length = length
		guard length > 0.0001 else { return nil }
		return self / length
	}

	func dot(_ other: OuraVector3) -> Double {
		x * other.x + y * other.y + z * other.z
	}

	func cross(_ other: OuraVector3) -> OuraVector3 {
		OuraVector3(
			x: y * other.z - z * other.y,
			y: z * other.x - x * other.z,
			z: x * other.y - y * other.x
		)
	}

	func projected(perpendicularTo normal: OuraVector3) -> OuraVector3 {
		self - normal * dot(normal)
	}

	static func + (lhs: OuraVector3, rhs: OuraVector3) -> OuraVector3 {
		OuraVector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
	}

	static func - (lhs: OuraVector3, rhs: OuraVector3) -> OuraVector3 {
		OuraVector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
	}

	static func * (lhs: OuraVector3, rhs: Double) -> OuraVector3 {
		OuraVector3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
	}

	static func / (lhs: OuraVector3, rhs: Double) -> OuraVector3 {
		OuraVector3(x: lhs.x / rhs, y: lhs.y / rhs, z: lhs.z / rhs)
	}
}

// Thresholds tuned offline against the 2026-07-05 labeled gesture session
// (104 prompted trials) via Tools/oura-calibration/tune_gestures.py — the
// looser quiet-lead-in gate plus the longer refractory/confirm windows took
// tap+hold accuracy from 54% to 85% on ground truth with zero false taps
// during cursor motion. Re-tune against a fresh session before hand-editing.
struct OuraTapDetector {
	private var sampleBeforePrevious: OuraMotionSample?
	private var previousSample: OuraMotionSample?
	private var pendingTap: PendingTap?
	private var lastTapTime: CFAbsoluteTime = 0

	mutating func reset() {
		sampleBeforePrevious = nil
		previousSample = nil
		pendingTap = nil
		lastTapTime = 0
	}

	mutating func register(_ sample: OuraMotionSample) -> Bool {
		defer {
			sampleBeforePrevious = previousSample
			previousSample = sample
		}
		if let pendingTap {
			if confirmsTap(candidate: pendingTap, with: sample) {
				self.pendingTap = nil
				lastTapTime = sample.timestamp
				return true
			}
			if sample.timestamp - pendingTap.sample.timestamp > 0.145 {
				self.pendingTap = nil
			}
		}

		guard let previousSample else { return false }
		guard sample.timestamp - lastTapTime > 0.18 else { return false }

		let dt = sample.timestamp - previousSample.timestamp
		guard dt > 0, dt < 0.2 else { return false }

		let delta = OuraMotionDelta(
			x: sample.x - previousSample.x,
			y: sample.y - previousSample.y,
			z: sample.z - previousSample.z
		)
		let jerk = delta.magnitude
		let magnitude = hypot3(sample.x, sample.y, sample.z)
		let previousMagnitude = hypot3(previousSample.x, previousSample.y, previousSample.z)
		let magnitudeDelta = abs(magnitude - previousMagnitude)
		guard let sampleBeforePrevious else { return false }
		let leadInJerk = OuraMotionDelta(
			x: previousSample.x - sampleBeforePrevious.x,
			y: previousSample.y - sampleBeforePrevious.y,
			z: previousSample.z - sampleBeforePrevious.z
		).magnitude
		let quietLeadIn = leadInJerk < 1.63 || jerk > max(1.35, leadInJerk * 2.0)
		let sharpPeak = jerk > 0.44 && magnitude > 1.064 && magnitudeDelta > 0.05

		if quietLeadIn && sharpPeak {
			pendingTap = PendingTap(
				previousSample: previousSample,
				sample: sample,
				delta: delta,
				peakMagnitude: magnitude
			)
		}
		return false
	}

	private func confirmsTap(candidate: PendingTap, with sample: OuraMotionSample) -> Bool {
		let dt = sample.timestamp - candidate.sample.timestamp
		guard dt > 0, dt <= 0.145 else { return false }

		let followDelta = OuraMotionDelta(
			x: sample.x - candidate.sample.x,
			y: sample.y - candidate.sample.y,
			z: sample.z - candidate.sample.z
		)
		let magnitude = hypot3(sample.x, sample.y, sample.z)
		let peakDrop = candidate.peakMagnitude - magnitude
		let reversal = candidate.delta.dot(followDelta) < -0.02
		let settledDistance = hypot3(
			sample.x - candidate.previousSample.x,
			sample.y - candidate.previousSample.y,
			sample.z - candidate.previousSample.z
		)

		return reversal &&
			(peakDrop > 0.13 || settledDistance < candidate.delta.magnitude * 0.92)
	}

	private func hypot3(_ x: Double, _ y: Double, _ z: Double) -> Double {
		sqrt(x * x + y * y + z * z)
	}

	private struct PendingTap {
		let previousSample: OuraMotionSample
		let sample: OuraMotionSample
		let delta: OuraMotionDelta
		let peakMagnitude: Double
	}

	private struct OuraMotionDelta {
		let x: Double
		let y: Double
		let z: Double

		init(x: Double, y: Double, z: Double) {
			self.x = x
			self.y = y
			self.z = z
		}

		var magnitude: Double {
			sqrt(x * x + y * y + z * z)
		}

		func dot(_ other: OuraMotionDelta) -> Double {
			x * other.x + y * other.y + z * other.z
		}
	}
}
