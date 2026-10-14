import Foundation

extension MappingEngine {
	/// A second press inside the tap interval owns the gesture immediately.
	/// Waiting for its release lets the first single fire while that press is held.
	/// Hold/repeat mappings and long-hold precedence keep their existing paths.
	nonisolated func consumePendingDoubleTapOnPress(
		_ button: ControllerButton,
		mapping: KeyMapping,
		profile: Profile
	) -> Bool {
		guard !(mapping.repeatMapping?.enabled ?? false),
			mapping.longHoldMapping?.isEmpty ?? true,
			let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty else { return false }
		let (pendingSingle, lastTap) = getPendingTapInfo(for: button)
		let now = CFAbsoluteTimeGetCurrent()
		guard pendingSingle != nil, let lastTap,
			now - lastTap <= doubleTap.threshold else { return false }
		guard handleDoubleTapIfReady(button, mapping: mapping, pendingSingle: pendingSingle,
			lastTap: lastTap, doubleTapMapping: doubleTap, profile: profile, tapTime: now) else {
			return false
		}
		state.lock.withLock { state.pressConsumedByAction.insert(button) }
		return true
	}
}
