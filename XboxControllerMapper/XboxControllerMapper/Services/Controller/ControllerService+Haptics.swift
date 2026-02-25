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
        hapticEngines = newEngines
        hapticLock.unlock()
    }

    func stopHaptics() {
        hapticLock.lock()
        let engines = hapticEngines
        hapticEngines.removeAll()
        activeHapticPlayers.removeAll()
        hapticLock.unlock()
        for engine in engines {
            engine.stop()
        }
    }

    /// Plays a haptic pulse on the controller
    /// - Parameters:
    ///   - intensity: Haptic intensity from 0.0 to 1.0
    ///   - duration: Duration in seconds
    nonisolated func playHaptic(intensity: Float = 0.5, sharpness: Float = 0.5, duration: TimeInterval = 0.1, transient: Bool = false) {
        hapticQueue.async { [weak self] in
            guard let self = self else { return }

            // Snapshot engines under lock
            self.hapticLock.lock()
            let engines = self.hapticEngines
            self.hapticLock.unlock()
            guard !engines.isEmpty else { return }

            // Prune expired players to avoid truncating overlapping haptics
            let now = CFAbsoluteTimeGetCurrent()
            self.hapticLock.lock()
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
                    do {
                        let player = try engine.makePlayer(with: pattern)
                        newPlayers.append(ActiveHapticPlayer(player: player, endTime: endTime))
                        try player.start(atTime: CHHapticTimeImmediate)
                    } catch {
                        // Try to restart engine and retry once
                        try? engine.start()
                        if let player = try? engine.makePlayer(with: pattern) {
                            newPlayers.append(ActiveHapticPlayer(player: player, endTime: endTime))
                            try? player.start(atTime: CHHapticTimeImmediate)
                        }
                    }
                }
                self.hapticLock.lock()
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
}
