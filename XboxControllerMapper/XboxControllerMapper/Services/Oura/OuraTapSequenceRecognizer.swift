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

	private var tapCount = 0
	private var lastTapTime: CFAbsoluteTime?
	private var lastAcceptedTapTime: CFAbsoluteTime?

	var hasPendingTaps: Bool {
		tapCount > 0
	}

	var lastPendingTapTime: CFAbsoluteTime? {
		hasPendingTaps ? lastTapTime : nil
	}

	mutating func reset() {
		tapCount = 0
		lastTapTime = nil
		lastAcceptedTapTime = nil
	}

	mutating func registerTap(at timestamp: CFAbsoluteTime) -> OuraTapSequenceImmediateAction {
		if let lastAcceptedTapTime, timestamp - lastAcceptedTapTime < Self.duplicateWindow {
			return .duplicate
		}

		if let lastTapTime, timestamp - lastTapTime <= Self.sequenceWindow {
			tapCount += 1
		} else {
			tapCount = 1
		}

		lastTapTime = timestamp
		lastAcceptedTapTime = timestamp

		if tapCount >= Self.maximumTapCount {
			let completedCount = tapCount
			tapCount = 0
			lastTapTime = nil
			return .completed(completedCount)
		}
		return .pending(tapCount)
	}

	mutating func resolvePending(at timestamp: CFAbsoluteTime) -> OuraTapSequenceResolvedAction? {
		guard let lastTapTime, timestamp - lastTapTime >= Self.sequenceWindow else { return nil }

		let resolvedCount = tapCount
		tapCount = 0
		self.lastTapTime = nil

		guard resolvedCount > 0 else { return nil }
		return .tapCount(resolvedCount)
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
