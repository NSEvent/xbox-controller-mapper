import Foundation

/// Capture physical overlap, independently of the mapping engine's chord window.
struct ControllerInputCapture {
	enum Mode { case button, chord, sequence }
	enum Phase: Equatable { case waitingForRelease, listening, captured, ambiguous }

	let mode: Mode
	private(set) var phase: Phase
	private(set) var held: Set<ControllerButton>
	private(set) var candidate: Set<ControllerButton> = []
	private var competingCandidate = false

	init(mode: Mode, initiallyHeld: Set<ControllerButton>) {
		self.mode = mode
		held = Self.eligible(initiallyHeld)
		phase = held.isEmpty ? .listening : .waitingForRelease
	}

	static func eligible(_ buttons: Set<ControllerButton>) -> Set<ControllerButton> {
		Set(buttons.filter { !$0.isJoystickDirection && !$0.isGestureButton })
	}

	mutating func receive(_ buttons: Set<ControllerButton>) -> Set<ControllerButton>? {
		let next = Self.eligible(buttons)
		let fresh = next.subtracting(held)
		held = next
		if phase == .waitingForRelease {
			if next.isEmpty { phase = .listening }
			return nil
		}
		guard phase == .listening else { return nil }
		switch mode {
		case .sequence: return nil // Ordered capture lives in ControllerSequenceCapture.
		case .button:
			guard let button = fresh.sorted(by: { $0.rawValue < $1.rawValue }).first else { return nil }
			candidate = [button]
			phase = .captured
			return candidate
		case .chord:
			if next.count > candidate.count {
				candidate = next
				competingCandidate = false
			} else if next.count == candidate.count, next.count >= 2, next != candidate {
				competingCandidate = true
			}
			guard next.isEmpty else { return nil }
			if competingCandidate {
				phase = .ambiguous
				return nil
			}
			guard candidate.count >= 2 else {
				candidate = []
				return nil
			}
			phase = .captured
			return candidate
		}
	}
}
