import Foundation
import CoreGraphics

/// Button-timer machinery: long-hold detection timers, repeat-while-held timers,
/// hold-repeat (key-repeat) timers, and smooth-scroll timers with acceleration ramping.
///
/// Extracted from MappingEngine to reduce its responsibilities.
extension MappingEngine {

    // MARK: - Smooth Scroll Timers

    /// Starts continuous smooth scrolling for scroll marker mappings that have per-action tuning.
    /// - Precondition: Must be called on inputQueue.
    nonisolated func handleSmoothScrollMapping(_ button: ControllerButton, mapping: KeyMapping) {
		dispatchPrecondition(condition: .onQueue(inputQueue))
		guard let keyCode = mapping.keyCode,
			  KeyCodeMapping.isScrollAction(keyCode),
			  let settings = mapping.scrollActionSettings else {
			return
		}

		stopSmoothScrollTimer(for: button)

		let startTime = CFAbsoluteTimeGetCurrent()
		let timer = DispatchSource.makeTimerSource(queue: inputQueue)
		timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
		timer.setEventHandler { [weak self] in
			guard let self else { return }
			let elapsed = CFAbsoluteTimeGetCurrent() - startTime
			let amount = self.smoothScrollAmount(settings: settings, elapsed: elapsed)
			let delta = KeyCodeMapping.scrollDelta(for: keyCode, amount: amount)
			guard delta.dx != 0 || delta.dy != 0 else { return }

			let flags = self.inputSimulator.getHeldModifiers().union(mapping.modifiers.cgEventFlags)
			self.inputSimulator.scroll(
				event: ScrollEvent(
					dx: delta.dx,
					dy: delta.dy,
					phase: nil,
					momentumPhase: nil,
					isContinuous: true,
					flags: flags
				)
			)
			self.usageStatsService?.recordScrollDistance(dx: Double(delta.dx), dy: Double(delta.dy))
		}

		state.lock.withLock {
			state.smoothScrollMappings[button] = mapping
			state.smoothScrollTimers[button] = timer
		}
		timer.resume()

		playActionHaptic(style: mapping.hapticStyle)
		inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.feedbackString, isHeld: true)
    }

    nonisolated private func stopSmoothScrollTimer(for button: ControllerButton) {
		state.lock.withLock {
			if let timer = state.smoothScrollTimers.removeValue(forKey: button) {
				timer.cancel()
			}
			state.smoothScrollMappings.removeValue(forKey: button)
		}
    }

    nonisolated private func smoothScrollAmount(settings: ScrollActionSettings, elapsed: TimeInterval) -> CGFloat {
		guard settings.scrollMultiplier > 0 else { return 0 }

		if settings.acceleration <= 0.001 {
			return CGFloat(settings.scrollMultiplier)
		}

		let rampDuration = 0.15 + settings.acceleration * 0.85
		let normalized = min(1.0, max(0.0, elapsed / rampDuration))
		let ramp = 0.2 + 0.8 * pow(normalized, settings.accelerationExponent)
		return CGFloat(settings.scrollMultiplier * ramp)
    }

    // MARK: - Long-Hold / Repeat / Hold-Repeat Timers

    /// Sets up a timer for long-hold detection
    nonisolated func setupLongHoldTimer(for button: ControllerButton, mapping: LongHoldMapping) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.handleLongHoldTriggered(button, mapping: mapping)
        }
        do {
            state.lock.lock()
            defer { state.lock.unlock() }
            state.longHoldTimers[button] = workItem
        }
        inputQueue.asyncAfter(deadline: .now() + mapping.threshold, execute: workItem)
    }

    nonisolated func startRepeatTimer(for button: ControllerButton, mapping: KeyMapping, interval: TimeInterval) {
        stopRepeatTimer(for: button)

        inputSimulator.executeMapping(mapping)
        if let keyCode = mapping.keyCode {
            OnScreenKeyboardManager.shared.notifyControllerKeyPress(
                keyCode: keyCode, modifiers: mapping.modifiers.cgEventFlags
            )
        }
        inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.feedbackString)

        let timer = DispatchSource.makeTimerSource(queue: inputQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.inputSimulator.executeMapping(mapping)
            if let keyCode = mapping.keyCode {
                OnScreenKeyboardManager.shared.notifyControllerKeyPress(
                    keyCode: keyCode, modifiers: mapping.modifiers.cgEventFlags
                )
            }
        }
        timer.resume()

        state.lock.lock()
        defer { state.lock.unlock() }
        state.repeatTimers[button] = timer
    }

    nonisolated func stopRepeatTimer(for button: ControllerButton) {
        state.lock.lock()
        defer { state.lock.unlock() }
        if let timer = state.repeatTimers[button] {
            timer.cancel()
            state.repeatTimers.removeValue(forKey: button)
        }
    }

    /// Starts a timer that re-posts keyDown events while a hold mapping is active.
    /// Unlike `startRepeatTimer` which does full press-release cycles, this only
    /// re-posts keyDown to simulate the OS key-repeat behavior for physical keys.
    nonisolated func startHoldRepeatTimer(for button: ControllerButton, mapping: KeyMapping) {
        guard let keyCode = mapping.keyCode else { return }
        let interval = max(mapping.holdRepeatInterval, 0.01)
        let modifiers = mapping.modifiers.cgEventFlags

        // Cancel any existing hold repeat timer for this button
        state.lock.lock()
        if let existing = state.holdRepeatTimers.removeValue(forKey: button) {
            existing.cancel()
        }
        state.lock.unlock()

        let timer = DispatchSource.makeTimerSource(queue: inputQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.inputSimulator.keyDown(keyCode, modifiers: modifiers)
        }
        timer.resume()

        state.lock.lock()
        defer { state.lock.unlock() }
        state.holdRepeatTimers[button] = timer
    }

    // MARK: - Release Timer Cleanup

    nonisolated func cleanupReleaseTimers(for button: ControllerButton) -> ReleaseCleanupResult? {
        state.lock.lock()
        defer { state.lock.unlock() }

        if let timer = state.longHoldTimers[button] {
            timer.cancel()
            state.longHoldTimers.removeValue(forKey: button)
        }

		if let scrollMapping = state.smoothScrollMappings.removeValue(forKey: button) {
			if let timer = state.smoothScrollTimers.removeValue(forKey: button) {
				timer.cancel()
			}
			state.activeChordButtons.remove(button)
			return .smoothScrollMapping(scrollMapping)
		}

        guard state.isEnabled, state.activeProfile != nil else { return nil }

        if let heldMapping = state.heldButtons[button] {
            state.heldButtons.removeValue(forKey: button)
            state.activeChordButtons.remove(button)
            if let timer = state.holdRepeatTimers[button] {
                timer.cancel()
                state.holdRepeatTimers.removeValue(forKey: button)
            }
            return .heldMapping(heldMapping)
        }

        if state.activeChordButtons.contains(button) {
            state.activeChordButtons.remove(button)
            return .chordButton
        }

        return nil
    }
}
