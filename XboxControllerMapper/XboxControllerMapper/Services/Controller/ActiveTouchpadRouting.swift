import Foundation

/// Serializes the active controller's touchpad updates with connection teardown.
/// Input callbacks must never wait for the main actor's keyboard rendering.
nonisolated final class ActiveTouchpadRouting: @unchecked Sendable {
	private let lock = NSLock()
	private var activeControllerID: ObjectIdentifier?
	private var lastInputTime: TimeInterval = 0

	func activate(_ controllerID: ObjectIdentifier) {
		lock.withLock {
			activeControllerID = controllerID
			lastInputTime = 0
		}
	}

	func invalidate() {
		lock.withLock {
			activeControllerID = nil
			lastInputTime = 0
		}
	}

	var lastActivity: TimeInterval {
		lock.withLock { lastInputTime }
	}

	/// Keep the gate locked through the update so invalidation waits for any
	/// in-flight sample before the service clears its touch/gesture state.
	func performIfActive(
		_ controllerID: ObjectIdentifier,
		meaningful: Bool,
		now: TimeInterval = CFAbsoluteTimeGetCurrent(),
		update: () -> Void
	) -> Bool {
		lock.withLock {
			guard activeControllerID == controllerID else { return false }
			if meaningful { lastInputTime = now }
			update()
			return true
		}
	}
}
