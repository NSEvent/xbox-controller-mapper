import Foundation

enum OuraTapSequenceImmediateAction: Equatable {
	case pending(Int)
	case duplicate
	case tripleTap
}

enum OuraTapSequenceResolvedAction: Equatable {
	case singleTap
	case doubleTap
}

struct OuraTapSequenceRecognizer {
	static let sequenceWindow: CFTimeInterval = 0.34
	private static let duplicateWindow: CFTimeInterval = 0.09

	private var tapCount = 0
	private var lastTapTime: CFAbsoluteTime?
	private var lastAcceptedTapTime: CFAbsoluteTime?

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

		if tapCount >= 3 {
			tapCount = 0
			lastTapTime = nil
			return .tripleTap
		}
		return .pending(tapCount)
	}

	mutating func resolvePending(at timestamp: CFAbsoluteTime) -> OuraTapSequenceResolvedAction? {
		guard let lastTapTime, timestamp - lastTapTime >= Self.sequenceWindow else { return nil }

		let resolvedCount = tapCount
		tapCount = 0
		self.lastTapTime = nil

		switch resolvedCount {
		case 1:
			return .singleTap
		case 2:
			return .doubleTap
		default:
			return nil
		}
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
