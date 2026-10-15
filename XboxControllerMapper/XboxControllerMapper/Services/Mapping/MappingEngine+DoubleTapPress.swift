import Foundation

extension MappingEngine {
	nonisolated static func usesPhysicalDoubleTapTiming(_ mapping: KeyMapping) -> Bool {
		!mapping.isHoldModifier && mapping.midiControlChange == nil && !mapping.isSmoothScrollAction
			&& !(mapping.repeatMapping?.enabled ?? false)
			&& (mapping.longHoldMapping?.isEmpty ?? true)
			&& mapping.doubleTapMapping.map { !$0.isEmpty } == true
	}

	/// Reserve, but do not execute, an in-time physical press while chord detection
	/// still owns it. A resolved chord may consume this reservation instead.
	nonisolated func reservePhysicalDoubleTapPress(_ physicalButton: ControllerButton, at time: CFAbsoluteTime) {
		guard state.lock.withLock({ state.cancelledPhysicalTapPressCutoffs[physicalButton].map { time > $0 } ?? true }) else { return }
		guard !UniversalControlMouseRelay.shared.shouldRouteControllerInputToRemote else { return }
		let button = resolvedInputButton(for: physicalButton)
		guard let profile = state.lock.withLock({ state.isEnabled && !state.isLocked ? state.activeProfile : nil }),
			let mapping = effectiveMapping(for: button, in: profile), Self.usesPhysicalDoubleTapTiming(mapping),
			let doubleTap = mapping.doubleTapMapping else { return }
		state.lock.withLock {
			state.unresolvedPhysicalTapPresses[button] = time
			state.physicalTapPressOwners[physicalButton] = PhysicalTapPress(resolvedButton: button, time: time)
			guard state.pendingDoubleTapPressTime[button] == nil,
				let lastTap = state.lastTapTime[button], time >= lastTap,
				time - lastTap <= doubleTap.threshold,
				let pending = state.pendingSingleTap[button] else { return }
			state.pendingDoubleTapPressTime[button] = time
			pending.cancel()
		}
		flushExpiredSingleTap(button, before: time, threshold: doubleTap.threshold)
	}

	/// A delayed queue may still contain the first single when a genuinely late
	/// second press arrives. Dispatch it before a new tap replaces its state.
	nonisolated private func flushExpiredSingleTap(_ button: ControllerButton, before time: CFAbsoluteTime,
		threshold: TimeInterval) {
		let expired = state.lock.withLock { () -> DispatchWorkItem? in
			guard state.pendingDoubleTapPressTime[button] == nil,
				let last = state.lastTapTime[button], time - last > threshold else { return nil }
			return state.pendingSingleTap[button]
		}
		expired?.perform()
	}

	nonisolated func finishPhysicalTapPress(_ physicalButton: ControllerButton, at time: CFAbsoluteTime) {
		state.lock.withLock {
			guard let owner = state.physicalTapPressOwners[physicalButton], owner.time == time else { return }
			state.physicalTapPressOwners.removeValue(forKey: physicalButton)
			let button = owner.resolvedButton
			if state.unresolvedPhysicalTapPresses[button] == time {
				state.unresolvedPhysicalTapPresses.removeValue(forKey: button)
			}
		}
	}

	/// A profile/pause boundary may occur while the chord buffer owns a press.
	/// Do not let that old press become a fresh action under the new profile.
	nonisolated func discardCancelledTimedPress(_ event: ControllerInputEvent, timing: ControllerInputTiming?) -> Bool {
		let times: [ControllerButton: CFAbsoluteTime]
		switch (event, timing) {
		case (.buttonPressed(let button), .resolved(let time)): times = [button: time]
		case (.chordDetected, .chordResolved(let chordTimes)): times = chordTimes
		default: return false
		}
		return state.lock.withLock {
			guard times.contains(where: { button, time in
				state.cancelledPhysicalTapPressCutoffs[button].map { time <= $0 } ?? false
			}) else { return false }
			state.cancelledPhysicalButtonReleases.formUnion(times.keys)
			return true
		}
	}

	/// A second press inside the tap interval owns the gesture immediately.
	/// Waiting for its release lets the first single fire while that press is held.
	/// Hold/repeat mappings and long-hold precedence keep their existing paths.
	nonisolated func consumePendingDoubleTapOnPress(
		_ button: ControllerButton,
		mapping: KeyMapping,
		profile: Profile,
		pressedAt: CFAbsoluteTime? = nil
	) -> Bool {
		guard Self.usesPhysicalDoubleTapTiming(mapping),
			let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty else { return false }
		let (pendingSingle, lastTap) = getPendingTapInfo(for: button)
		let reserved = state.lock.withLock { state.pendingDoubleTapPressTime[button] }
		let now = reserved ?? pressedAt ?? CFAbsoluteTimeGetCurrent()
		flushExpiredSingleTap(button, before: now, threshold: doubleTap.threshold)
		guard pendingSingle != nil, let lastTap,
			now >= lastTap, now - lastTap <= doubleTap.threshold else { return false }
		guard handleDoubleTapIfReady(button, mapping: mapping, pendingSingle: pendingSingle,
			lastTap: lastTap, doubleTapMapping: doubleTap, profile: profile, tapTime: now) else {
			return false
		}
		state.lock.withLock { state.pressConsumedByAction.insert(button) }
		return true
	}
}
