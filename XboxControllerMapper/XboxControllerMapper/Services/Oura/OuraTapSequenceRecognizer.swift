import Foundation

enum OuraTapSequenceImmediateAction: Equatable {
	case pending(Int)
	case duplicate
	case completed(Int)
}

enum OuraTapSequenceResolvedAction: Equatable {
	case tapCount(Int)
}

struct OuraTapSequenceRecognizer {
	// 0.65 → 0.75 (2026-07-06): Kevin's live 3x/5x chains showed inter-tap
	// gaps up to ~0.7s splitting sequences; +0.1s window costs the same in
	// resolution latency.
	static let sequenceWindow: CFTimeInterval = 0.75
	private static let duplicateWindow: CFTimeInterval = 0.09
	private static let maximumTapCount = 5

	// Echo guard (2026-07-06): a tap's hand-settle rebound lands ~0.18-0.30s
	// after the real tap and is physically a second contact — across all three
	// labeled sessions it matches real chain taps on every measurable feature
	// (peak jerk, classifier confidence, inter-tap gap), so no per-tap gate can
	// separate them; even retraining with these windows as noise negatives
	// left them classifying as tap at 0.65-1.00. When enabled, at resolution
	// time a trailing tap closer than this to its predecessor is dropped as
	// settle UNLESS the preceding gap was just as fast (an established 3x/5x
	// machine-gun rhythm earns its trailing tap) — double tap then requires a
	// deliberate two-beat rhythm, like the macOS double-click-speed setting.
	// DISABLED by default: Kevin's echo misfires only occur when the motion
	// center is stale (well-centered sessions are clean), and his natural
	// doubles gap ~0.29s — inside any guard that would catch the echoes.
	// Enable to trade fast doubles for echo immunity:
	//   defaults write KevinTang.XboxControllerMapper
	//     ouraDoubleTapMinGap -float 0.35     (0 or unset = disabled)
	static let defaultEchoGuardGap: CFTimeInterval =
		UserDefaults.standard.double(forKey: "ouraDoubleTapMinGap")

	var echoGuardGap: CFTimeInterval = OuraTapSequenceRecognizer.defaultEchoGuardGap

	/// Gap of the trailing tap dropped as settle echo by the last
	/// `resolvePending` call, for diagnostics. Nil when nothing was dropped.
	private(set) var lastResolutionEchoGap: CFTimeInterval?

	private var tapTimes: [CFAbsoluteTime] = []
	private var lastAcceptedTapTime: CFAbsoluteTime?

	var hasPendingTaps: Bool {
		!tapTimes.isEmpty
	}

	var lastPendingTapTime: CFAbsoluteTime? {
		tapTimes.last
	}

	mutating func reset() {
		tapTimes = []
		lastAcceptedTapTime = nil
		lastResolutionEchoGap = nil
	}

	mutating func registerTap(at timestamp: CFAbsoluteTime) -> OuraTapSequenceImmediateAction {
		if let lastAcceptedTapTime, timestamp - lastAcceptedTapTime < Self.duplicateWindow {
			return .duplicate
		}

		if let last = tapTimes.last, timestamp - last <= Self.sequenceWindow {
			tapTimes.append(timestamp)
		} else {
			tapTimes = [timestamp]
		}
		lastAcceptedTapTime = timestamp

		if tapTimes.count >= Self.maximumTapCount {
			let completedCount = tapTimes.count
			tapTimes = []
			return .completed(completedCount)
		}
		return .pending(tapTimes.count)
	}

	mutating func resolvePending(at timestamp: CFAbsoluteTime) -> OuraTapSequenceResolvedAction? {
		lastResolutionEchoGap = nil
		guard let last = tapTimes.last, timestamp - last >= Self.sequenceWindow else { return nil }

		var times = tapTimes
		tapTimes = []

		if echoGuardGap > 0, times.count >= 2 {
			let trailingGap = times[times.count - 1] - times[times.count - 2]
			let precedingGap = times.count >= 3
				? times[times.count - 2] - times[times.count - 3]
				: CFTimeInterval.greatestFiniteMagnitude
			if trailingGap < echoGuardGap, precedingGap >= echoGuardGap {
				times.removeLast()
				lastResolutionEchoGap = trailingGap
			}
		}

		guard !times.isEmpty else { return nil }
		return .tapCount(times.count)
	}
}

struct OuraTapMotionSuppressor {
	private var suppressUntil: CFAbsoluteTime = 0

	mutating func reset() {
		suppressUntil = 0
	}

	mutating func suppress(at timestamp: CFAbsoluteTime, duration: CFTimeInterval) {
		suppressUntil = max(suppressUntil, timestamp + duration)
	}

	func isSuppressed(at timestamp: CFAbsoluteTime) -> Bool {
		timestamp < suppressUntil
	}
}
