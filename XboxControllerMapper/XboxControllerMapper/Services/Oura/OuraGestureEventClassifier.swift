import CoreGraphics
import CoreML
import Foundation

// ML gesture-event path for the Oura ring: a jerk-impulse candidate detector
// feeds 0.64s windows of raw motion to a tiny Core ML classifier
// (Resources/OuraGestureClassifier.mlpackage, trained in OuraGestureModel/).
// The classifier replaces the geometric flick recognizer — ground truth from
// the 2026-07-05 labeled session showed flicks are unrecoverable by
// thresholds (the gravity projection never "returns to start", and taps shake
// px/py as hard as flicks) while the classifier separates them cleanly.
// Tap events still flow through the deterministic OuraTapSequenceRecognizer.
//
// Kill switch: defaults write ~/Library/Preferences/KevinTang.XboxControllerMapper.plist \
//   ouraGestureClassifierDisabled -bool true   (falls back to the heuristic path)

enum OuraGestureEvent: String {
	case tap
	case flickUp = "flick-up"
	case flickDown = "flick-down"
	case flickLeft = "flick-left"
	case flickRight = "flick-right"
	case noise

	// Must match OuraGestureModel/model.py CLASSES order.
	static let classOrder: [OuraGestureEvent] = [.tap, .flickUp, .flickDown, .flickLeft, .flickRight, .noise]

	var directionalFlick: OuraDirectionalFlick? {
		switch self {
		case .flickUp: return .up
		case .flickDown: return .down
		case .flickLeft: return .left
		case .flickRight: return .right
		case .tap, .noise: return nil
		}
	}
}

// Mirrors OuraGestureModel/build_dataset.py jerk_peaks: local maxima of the
// inter-sample |Δxyz| (samples <1ms apart are frame pairs and skipped),
// confirmed one jerk-series entry later, with a minimum peak separation.
struct OuraImpulseDetector {
	static let threshold = 0.35
	static let minimumSeparation: CFTimeInterval = 0.18

	private var previousSample: OuraMotionSample?
	private var jerkPrevious: (time: CFAbsoluteTime, jerk: Double)?
	private var jerkBefore: (time: CFAbsoluteTime, jerk: Double)?
	private var lastPeakTime: CFAbsoluteTime = -.greatestFiniteMagnitude

	mutating func reset() {
		previousSample = nil
		jerkPrevious = nil
		jerkBefore = nil
		lastPeakTime = -.greatestFiniteMagnitude
	}

	/// Returns the timestamp of a newly confirmed impulse peak, if any.
	mutating func register(_ sample: OuraMotionSample) -> CFAbsoluteTime? {
		guard let previous = previousSample else {
			previousSample = sample
			return nil
		}
		// Frame pairs (<1ms apart) contribute no jerk entry, but the cursor
		// still advances — the next jerk is measured against the pair's
		// second sample, matching build_dataset.py's extraction.
		previousSample = sample
		guard sample.timestamp - previous.timestamp >= 0.001 else { return nil }

		let dx = sample.x - previous.x
		let dy = sample.y - previous.y
		let dz = sample.z - previous.z
		let entry = (time: sample.timestamp, jerk: (dx * dx + dy * dy + dz * dz).squareRoot())

		var confirmed: CFAbsoluteTime?
		if let candidate = jerkPrevious, let before = jerkBefore,
		   candidate.jerk >= Self.threshold,
		   candidate.jerk >= before.jerk,
		   candidate.jerk >= entry.jerk,
		   candidate.time - lastPeakTime >= Self.minimumSeparation {
			lastPeakTime = candidate.time
			confirmed = candidate.time
		}
		jerkBefore = jerkPrevious
		jerkPrevious = entry
		return confirmed
	}
}

// Rolling history of raw motion, resampled into the classifier's fixed
// window. Mirrors OuraGestureModel/build_dataset.py extract_window.
struct OuraMotionWindowBuffer {
	struct Entry {
		let timestamp: CFAbsoluteTime
		let x: Double
		let y: Double
		let z: Double
		let px: Double
		let py: Double
	}

	static let preSpan: CFTimeInterval = 0.26
	// 0.38 → 0.24 (overnight search 2026-07-06): the shorter window scored
	// BETTER (v1 98%, v2 94% end-to-end) and cuts every gesture's
	// classification latency by 0.14s. Must match OuraGestureModel
	// build_dataset.WINDOW_POST.
	static let postSpan: CFTimeInterval = 0.24
	static let steps = 32
	private static let retention: CFTimeInterval = 3.0
	private static let minimumCoverage = 0.6

	private(set) var entries: [Entry] = []

	mutating func reset() {
		entries.removeAll()
	}

	mutating func append(_ sample: OuraMotionSample, projected: CGPoint) {
		entries.append(Entry(timestamp: sample.timestamp, x: sample.x, y: sample.y, z: sample.z,
			px: Double(projected.x), py: Double(projected.y)))
		if let newest = entries.last?.timestamp,
		   let oldest = entries.first?.timestamp,
		   newest - oldest > Self.retention * 2 {
			let cutoff = newest - Self.retention
			entries.removeAll { $0.timestamp < cutoff }
		}
	}

	func entriesAfter(_ time: CFAbsoluteTime) -> ArraySlice<Entry> {
		guard let start = entries.firstIndex(where: { $0.timestamp >= time }) else { return [] }
		return entries[start...]
	}

	/// 32×5 window of [x, y, z, px, py] resampled around `center`, or nil when
	/// the buffer covers less than 60% of the span.
	func window(around center: CFAbsoluteTime) -> [[Double]]? {
		let lo = center - Self.preSpan
		let hi = center + Self.postSpan
		guard let firstInside = entries.firstIndex(where: { $0.timestamp >= lo }) else { return nil }
		let inside = entries[firstInside...].prefix { $0.timestamp <= hi }
		guard let coverageStart = inside.first?.timestamp,
		      let coverageEnd = inside.last?.timestamp,
		      min(coverageEnd, hi) - max(coverageStart, lo) >= Self.minimumCoverage * (hi - lo) else {
			return nil
		}

		var window: [[Double]] = []
		window.reserveCapacity(Self.steps)
		var j = max(firstInside, 1)
		for step in 0..<Self.steps {
			let target = lo + (hi - lo) * Double(step) / Double(Self.steps - 1)
			while j < entries.count - 1, entries[j].timestamp < target {
				j += 1
			}
			let a = entries[j - 1]
			let b = entries[j]
			let span = b.timestamp - a.timestamp
			let fraction = span <= 0 ? 0.0 : min(1.0, max(0.0, (target - a.timestamp) / span))
			window.append([
				a.x + (b.x - a.x) * fraction,
				a.y + (b.y - a.y) * fraction,
				a.z + (b.z - a.z) * fraction,
				a.px + (b.px - a.px) * fraction,
				a.py + (b.py - a.py) * fraction
			])
		}
		return window
	}
}

// nonisolated: internally NSLock-synchronized, loads on a background queue,
// and must not inherit the project's default MainActor isolation — the
// isolated-deinit executor hop crashes (bad free in the back-deploy shim)
// when an instance deallocates off the main actor, as XCTest teardown does.
nonisolated final class OuraGestureEventClassifier {
	private var model: MLModel?
	private var loadAttempted = false
	private let lock = NSLock()

	var isAvailable: Bool {
		lock.lock()
		defer { lock.unlock() }
		return model != nil
	}

	/// Loads the compiled model off the calling thread; safe to call repeatedly.
	func loadIfNeeded() {
		lock.lock()
		let shouldLoad = model == nil && !loadAttempted
		loadAttempted = true
		lock.unlock()
		guard shouldLoad else { return }

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let self else { return }
			guard let url = Self.locateCompiledModel() else {
				NSLog("[OuraGestureEventClassifier] OuraGestureClassifier.mlmodelc missing from bundle — heuristic path stays active")
				return
			}
			let configuration = MLModelConfiguration()
			configuration.computeUnits = .cpuOnly
			do {
				let loaded = try MLModel(contentsOf: url, configuration: configuration)
				self.lock.lock()
				self.model = loaded
				self.lock.unlock()
				NSLog("[OuraGestureEventClassifier] model loaded")
			} catch {
				NSLog("[OuraGestureEventClassifier] model load failed: %@", error.localizedDescription)
			}
		}
	}

	// In the app, Bundle.main resolves directly. Under the direct `xcrun
	// xctest` gate on kmacstudio the host process is xctest, so Bundle.main
	// is useless — but the test bundle lives inside
	// ControllerKeys.app/Contents/PlugIns/, so walk up to the app bundle.
	private static func locateCompiledModel() -> URL? {
		var candidates: [Bundle] = [.main, Bundle(for: OuraGestureEventClassifier.self)]
		for bundle in Bundle.allBundles where bundle.bundleURL.pathExtension == "xctest" {
			let appBundleURL = bundle.bundleURL
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.deletingLastPathComponent()
			if let appBundle = Bundle(url: appBundleURL) {
				candidates.append(appBundle)
			}
		}
		for bundle in candidates {
			if let url = bundle.url(forResource: "OuraGestureClassifier", withExtension: "mlmodelc") {
				return url
			}
		}
		return nil
	}

	func classify(window: [[Double]]) -> (event: OuraGestureEvent, confidence: Double, tapProbability: Double)? {
		lock.lock()
		let model = self.model
		lock.unlock()
		guard let model,
		      window.count == OuraMotionWindowBuffer.steps,
		      window.allSatisfy({ $0.count == 5 }) else {
			return nil
		}
		guard let input = try? MLMultiArray(shape: [1, NSNumber(value: OuraMotionWindowBuffer.steps), 5],
			dataType: .float32) else { return nil }
		for (step, row) in window.enumerated() {
			for (channel, value) in row.enumerated() {
				input[step * 5 + channel] = NSNumber(value: Float(value))
			}
		}
		guard let output = try? model.prediction(
			from: MLDictionaryFeatureProvider(dictionary: ["window": MLFeatureValue(multiArray: input)])),
			let logits = output.featureValue(for: "logits")?.multiArrayValue else {
			return nil
		}
		var bestIndex = 0
		var bestValue = -Double.infinity
		var expSum = 0.0
		var values: [Double] = []
		for index in 0..<logits.count {
			let value = logits[index].doubleValue
			values.append(value)
			if value > bestValue {
				bestValue = value
				bestIndex = index
			}
		}
		for value in values {
			expSum += exp(value - bestValue)
		}
		guard bestIndex < OuraGestureEvent.classOrder.count, !values.isEmpty, expSum > 0 else { return nil }
		// classOrder[0] == .tap — its softmax probability drives the tap-lean
		// rule (borderline windows where noise narrowly outranks tap).
		let tapProbability = exp(values[0] - bestValue) / expSum
		return (OuraGestureEvent.classOrder[bestIndex], 1.0 / expSum, tapProbability)
	}
}
