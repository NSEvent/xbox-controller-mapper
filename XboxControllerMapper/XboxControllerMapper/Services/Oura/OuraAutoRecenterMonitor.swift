import Foundation

/// Detects a stale motion center and proposes a snap recenter.
///
/// Physics: at true rest the accelerometer reads pure gravity, so during raw
/// stillness the angle between the current gravity vector and the stored
/// neutral is a direct measure of center staleness. The old soft-recenter
/// path can't recover a badly stale center because its gate requires small
/// PROJECTED input — which a stale center manufactures even at dead rest.
/// This monitor gates on raw stillness only, so it engages exactly when the
/// soft path deadlocks.
///
/// Thresholds mined from the full live trace (2026-07-06, 22.9k rest
/// readings): drift-at-rest is bimodal — median 0.2° when healthy vs 50-90°
/// when stale, with almost no mass at 8-25° — and 62% of rest readings in the
/// 60s before a spurious double tap showed >15° drift (vs 17% baseline).
/// Rest |a| measured 0.995-1.023g, so the magnitude band rejects windows of
/// smooth non-gravity acceleration.
///
/// Kill switch: defaults write ~/Library/Preferences/KevinTang.XboxControllerMapper.plist \
///   ouraAutoRecenterDisabled -bool true
struct OuraAutoRecenterMonitor {
	static let defaultsDisableKey = "ouraAutoRecenterDisabled"

	var enabled: Bool = !UserDefaults.standard.bool(forKey: OuraAutoRecenterMonitor.defaultsDisableKey)
	var staleAngleDegrees: Double = 15
	var confirmDuration: CFTimeInterval = 1.5
	var cooldown: CFTimeInterval = 5.0

	private static let stillDeltaThreshold = 0.02
	private static let pairEpsilon: CFTimeInterval = 0.001
	private static let magnitudeBand = 0.90...1.10

	private var previousSample: OuraMotionSample?
	private var stillStart: CFAbsoluteTime?
	private var sumX = 0.0
	private var sumY = 0.0
	private var sumZ = 0.0
	private var sampleCount = 0
	private var lastSnapTime: CFAbsoluteTime = -.greatestFiniteMagnitude
	private var holdOffUntil: CFAbsoluteTime = -.greatestFiniteMagnitude

	mutating func reset() {
		previousSample = nil
		clearStillRun()
		lastSnapTime = -.greatestFiniteMagnitude
		holdOffUntil = -.greatestFiniteMagnitude
	}

	/// Defer snapping until after gesture activity settles — tap ring-down is
	/// not rest, and a snap inside the suppression window would fight the
	/// gesture pipeline.
	mutating func holdOff(until timestamp: CFAbsoluteTime) {
		holdOffUntil = max(holdOffUntil, timestamp)
	}

	/// Feed every raw sample. Returns a replacement neutral (mean gravity over
	/// the still window) plus the measured drift when the center is provably
	/// stale; nil otherwise.
	mutating func register(
		_ sample: OuraMotionSample,
		neutral: OuraMotionSample?
	) -> (neutral: OuraMotionSample, driftDegrees: Double)? {
		defer { previousSample = sample }
		guard enabled, let neutral else {
			clearStillRun()
			return nil
		}
		guard let previous = previousSample else { return nil }

		// Both samples of one BLE frame share a near-identical timestamp —
		// they contribute to the gravity mean but not to stillness timing.
		guard sample.timestamp - previous.timestamp >= Self.pairEpsilon else {
			if stillStart != nil {
				accumulate(sample)
			}
			return nil
		}

		let delta = distance(sample, previous)
		guard delta < Self.stillDeltaThreshold else {
			clearStillRun()
			return nil
		}

		if stillStart == nil {
			stillStart = sample.timestamp
		}
		accumulate(sample)

		guard let stillStart,
		      sample.timestamp - stillStart >= confirmDuration,
		      sample.timestamp >= holdOffUntil,
		      sample.timestamp - lastSnapTime >= cooldown,
		      sampleCount > 0 else {
			return nil
		}

		let mean = OuraMotionSample(
			x: sumX / Double(sampleCount),
			y: sumY / Double(sampleCount),
			z: sumZ / Double(sampleCount),
			timestamp: sample.timestamp
		)
		guard Self.magnitudeBand.contains(magnitude(mean)) else { return nil }
		guard let drift = angleDegrees(mean, neutral), drift >= staleAngleDegrees else { return nil }

		lastSnapTime = sample.timestamp
		clearStillRun()
		return (mean, drift)
	}

	private mutating func clearStillRun() {
		stillStart = nil
		sumX = 0
		sumY = 0
		sumZ = 0
		sampleCount = 0
	}

	private mutating func accumulate(_ sample: OuraMotionSample) {
		sumX += sample.x
		sumY += sample.y
		sumZ += sample.z
		sampleCount += 1
	}

	private func distance(_ a: OuraMotionSample, _ b: OuraMotionSample) -> Double {
		let dx = a.x - b.x
		let dy = a.y - b.y
		let dz = a.z - b.z
		return (dx * dx + dy * dy + dz * dz).squareRoot()
	}

	private func magnitude(_ sample: OuraMotionSample) -> Double {
		(sample.x * sample.x + sample.y * sample.y + sample.z * sample.z).squareRoot()
	}

	private func angleDegrees(_ a: OuraMotionSample, _ b: OuraMotionSample) -> Double? {
		let la = magnitude(a)
		let lb = magnitude(b)
		guard la > 0.0001, lb > 0.0001 else { return nil }
		let dot = (a.x * b.x + a.y * b.y + a.z * b.z) / (la * lb)
		return acos(min(1.0, max(-1.0, dot))) * 180.0 / .pi
	}
}
