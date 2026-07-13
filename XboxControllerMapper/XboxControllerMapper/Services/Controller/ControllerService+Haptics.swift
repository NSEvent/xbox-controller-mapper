import Foundation
import GameController
import CoreHaptics

// MARK: - Haptic Feedback

@MainActor
extension ControllerService {

    func setupHaptics(for controller: GCController) {
        guard let haptics = controller.haptics else {
            return
        }

        // Try multiple localities - Xbox controllers may respond to different ones
        let localities: [GCHapticsLocality] = [.default, .handles, .leftHandle, .rightHandle, .leftTrigger, .rightTrigger]

        var newEngines: [CHHapticEngine] = []
        for locality in localities {
            if let engine = haptics.createEngine(withLocality: locality) {
                engine.resetHandler = { [weak engine] in
                    // Restart engine if it stops
                    try? engine?.start()
                }
                do {
                    try engine.start()
                    newEngines.append(engine)
                } catch {
                    // Engine startup failed, continue to next locality
                }
            }
        }
        hapticLock.lock()
		hapticSessionGeneration += 1
        hapticEngines = newEngines
        hapticLock.unlock()
    }

    func stopHaptics() {
		let stop = { [self] in
			hapticLock.lock()
			hapticSessionGeneration += 1
			let engines = hapticEngines
			let players = activeHapticPlayers
			hapticEngines.removeAll()
			activeHapticPlayers.removeAll()
			hapticLock.unlock()

			for player in players {
				try? player.player.stop(atTime: CHHapticTimeImmediate)
			}
			for engine in engines {
				engine.stop()
			}
		}

		if DispatchQueue.getSpecific(key: hapticQueueSpecificKey) != nil {
			stop()
		} else {
			hapticQueue.sync(execute: stop)
		}
    }

	nonisolated func currentHapticSessionGeneration() -> UInt64 {
		hapticLock.lock()
		defer { hapticLock.unlock() }
		return hapticSessionGeneration
	}

	nonisolated func isCurrentHapticSession(_ generation: UInt64) -> Bool {
		currentHapticSessionGeneration() == generation
	}

	#if DEBUG
	nonisolated func invalidateHapticSessionForTesting() {
		hapticLock.lock()
		hapticSessionGeneration += 1
		hapticLock.unlock()
	}
	#endif

    /// Plays a haptic pulse on the controller
    /// - Parameters:
    ///   - intensity: Haptic intensity from 0.0 to 1.0
    ///   - duration: Duration in seconds
    nonisolated func playHaptic(intensity: Float = 0.5, sharpness: Float = 0.5, duration: TimeInterval = 0.1, transient: Bool = false) {
		let sessionGeneration = currentHapticSessionGeneration()
        hapticQueue.async { [weak self] in
            guard let self = self else { return }
			guard self.isCurrentHapticSession(sessionGeneration) else { return }
			#if DEBUG
			self.hapticSessionAcceptedForTesting?(sessionGeneration)
			#endif

            if self.readStorage(\.isSteamController) {
                self.steamHIDControllerLock.lock()
                let steamController = self.activeSteamHIDController
                self.steamHIDControllerLock.unlock()
                steamController?.playHaptic(
                    intensity: intensity,
                    sharpness: sharpness,
                    duration: duration,
                    transient: transient
                )
            }

            // Snapshot engines under lock
            self.hapticLock.lock()
            let engines = self.hapticEngines
			let sessionStillCurrent = self.hapticSessionGeneration == sessionGeneration
            self.hapticLock.unlock()
			guard sessionStillCurrent, !engines.isEmpty else { return }

            // Prune expired players to avoid truncating overlapping haptics
            let now = CFAbsoluteTimeGetCurrent()
            self.hapticLock.lock()
			guard self.hapticSessionGeneration == sessionGeneration else {
				self.hapticLock.unlock()
				return
			}
            self.activeHapticPlayers.removeAll { $0.endTime <= now }
            self.hapticLock.unlock()

            do {
                let event: CHHapticEvent
                if transient {
                    // Transient: single-shot pulse, more reliable for brief feedback
                    event = CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                        ],
                        relativeTime: 0
                    )
                } else {
                    // Continuous: sustained haptic for longer feedback
                    event = CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                        ],
                        relativeTime: 0,
                        duration: duration
                    )
                }
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let estimatedDuration = transient ? max(duration, 0.06) : max(duration, 0.01)
                let endTime = CFAbsoluteTimeGetCurrent() + estimatedDuration + 0.02

                // Play on all available engines for maximum effect
                // Retain players so they aren't deallocated before playback completes
                var newPlayers: [ActiveHapticPlayer] = []
                for engine in engines {
					guard self.isCurrentHapticSession(sessionGeneration) else { break }
                    do {
                        let player = try engine.makePlayer(with: pattern)
                        newPlayers.append(ActiveHapticPlayer(player: player, endTime: endTime))
						guard self.isCurrentHapticSession(sessionGeneration) else { break }
                        try player.start(atTime: CHHapticTimeImmediate)
                    } catch {
                        // Try to restart engine and retry once
						guard self.isCurrentHapticSession(sessionGeneration) else { break }
                        try? engine.start()
                        if let player = try? engine.makePlayer(with: pattern) {
                            newPlayers.append(ActiveHapticPlayer(player: player, endTime: endTime))
							guard self.isCurrentHapticSession(sessionGeneration) else { break }
                            try? player.start(atTime: CHHapticTimeImmediate)
                        }
                    }
                }
                self.hapticLock.lock()
				guard self.hapticSessionGeneration == sessionGeneration else {
					self.hapticLock.unlock()
					for player in newPlayers {
						try? player.player.stop(atTime: CHHapticTimeImmediate)
					}
					return
				}
                self.activeHapticPlayers.append(contentsOf: newPlayers)
                if self.activeHapticPlayers.count > 12 {
                    self.activeHapticPlayers.removeFirst(self.activeHapticPlayers.count - 12)
                }
                self.hapticLock.unlock()
            } catch {
                // Haptic pattern error, continue silently
            }
        }
    }

    nonisolated func playSteamTouchpadHaptic(
        side: SteamTouchpadSide,
        intensity: Float,
        sharpness: Float,
        duration: TimeInterval,
        transient: Bool
    ) {
        hapticQueue.async { [weak self] in
            guard let self, self.readStorage(\.isSteamController) else { return }
            self.steamHIDControllerLock.lock()
            let steamController = self.activeSteamHIDController
            self.steamHIDControllerLock.unlock()
            steamController?.playTouchpadHaptic(
                side: side,
                intensity: intensity,
                sharpness: sharpness,
                duration: duration,
                transient: transient
            )
        }
    }
}
