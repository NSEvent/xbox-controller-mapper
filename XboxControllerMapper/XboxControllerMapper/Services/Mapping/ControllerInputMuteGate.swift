import Foundation

/// Admission state for discrete controller input across pause/resume boundaries.
/// Owned by EngineState; all access must hold its lock.
struct ControllerInputMuteGate {
	enum Decision: Equatable {
		case forward
		case ignore
		case cancelRelease
	}

	private(set) var generation: UInt64 = 0
	private(set) var isEnabled = true
	private var mutedButtons: Set<ControllerButton> = []

	mutating func setEnabled(_ enabled: Bool, pendingButtons: Set<ControllerButton>) {
		guard enabled != isEnabled else { return }
		generation &+= 1
		isEnabled = enabled
		// Includes the controller's chord window: a raw press may not have
		// reached the engine yet, even if it was already released physically.
		mutedButtons.formUnion(pendingButtons)
	}

	mutating func resetForDisconnect() {
		generation &+= 1
		mutedButtons.removeAll()
	}

	mutating func decision(for event: ControllerInputEvent, generation emittedGeneration: UInt64) -> Decision {
		if case .controllerDisconnected = event { return .forward }
		let blocked = !isEnabled || emittedGeneration != generation
		switch event {
		case .buttonPressed(let button):
			if blocked {
				if emittedGeneration == generation { mutedButtons.insert(button) }
				return .ignore
			}
			return mutedButtons.contains(button) ? .ignore : .forward
		case .chordDetected(let buttons):
			if blocked {
				if emittedGeneration == generation { mutedButtons.formUnion(buttons) }
				return .ignore
			}
			if !mutedButtons.isDisjoint(with: buttons) {
				// Do not reinterpret a partial muted chord as another action.
				mutedButtons.formUnion(buttons)
				return .ignore
			}
			return .forward
		case .buttonReleased(let button, _):
			let wasMuted = mutedButtons.remove(button) != nil
			return blocked || wasMuted ? .cancelRelease : .forward
		default:
			return blocked ? .ignore : .forward
		}
	}
}
