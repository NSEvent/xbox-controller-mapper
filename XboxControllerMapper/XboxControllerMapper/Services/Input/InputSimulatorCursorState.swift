import AppKit
import CoreGraphics
import Foundation
import ApplicationServices.HIServices

enum InputSimulatorCursorState {
	private static var sharedTrackedPosition: CGPoint?
	private static var sharedLastMoveTime: CFAbsoluteTime = 0
	private static let sharedLock = NSLock()

	private static var accumulatedDelta: CGPoint = .zero

	private static var cachedZoomActive: Bool = false
	private static var cachedZoomCheckTime: CFAbsoluteTime = 0
	private static let zoomCacheInterval: CFAbsoluteTime = 0.5
	private static let zoomCacheLock = NSLock()

	static func trackedPositionIfZoomEnabled() -> CGPoint? {
		guard UAZoomEnabled() else { return nil }
		sharedLock.lock()
		defer { sharedLock.unlock() }
		return sharedTrackedPosition
	}

	static func isCursorBeingMoved() -> Bool {
		sharedLock.lock()
		defer { sharedLock.unlock() }
		return CFAbsoluteTimeGetCurrent() - sharedLastMoveTime < 0.05
	}

	static func consumeMovementDelta() -> CGPoint {
		sharedLock.lock()
		let delta = accumulatedDelta
		accumulatedDelta = .zero
		sharedLock.unlock()
		return delta
	}

	static func resetMovementDelta() {
		sharedLock.lock()
		accumulatedDelta = .zero
		sharedLock.unlock()
	}

	static func zoomLevel() -> CGFloat {
		CGFloat(UserDefaults(suiteName: "com.apple.universalaccess")?.double(forKey: "closeViewZoomFactor") ?? 1.0)
	}

	static func isZoomCurrentlyActive() -> Bool {
		let now = CFAbsoluteTimeGetCurrent()
		zoomCacheLock.lock()
		if now - cachedZoomCheckTime < zoomCacheInterval {
			let cached = cachedZoomActive
			zoomCacheLock.unlock()
			return cached
		}
		cachedZoomCheckTime = now
		zoomCacheLock.unlock()

		// UserDefaults read is thread-safe and potentially slow -- do it outside the lock.
		let defaults = UserDefaults(suiteName: "com.apple.universalaccess")
		let active = (defaults?.bool(forKey: "closeViewZoomedIn") ?? false)
			&& (defaults?.double(forKey: "closeViewZoomFactor") ?? 1.0) > 1.0

		zoomCacheLock.lock()
		cachedZoomActive = active
		zoomCacheLock.unlock()
		return active
	}

	static func lastTrackedPosition() -> CGPoint? {
		sharedLock.lock()
		defer { sharedLock.unlock() }
		return sharedTrackedPosition
	}

	static func lastTrackedPositionSnapshot() -> (position: CGPoint?, lastMoveTime: CFAbsoluteTime) {
		sharedLock.lock()
		defer { sharedLock.unlock() }
		return (sharedTrackedPosition, sharedLastMoveTime)
	}

	static func updateTrackedPosition(_ point: CGPoint?, delta: CGPoint = .zero) {
		sharedLock.lock()
		sharedTrackedPosition = point
		sharedLastMoveTime = CFAbsoluteTimeGetCurrent()
		accumulatedDelta.x += delta.x
		accumulatedDelta.y += delta.y
		sharedLock.unlock()
	}
}
