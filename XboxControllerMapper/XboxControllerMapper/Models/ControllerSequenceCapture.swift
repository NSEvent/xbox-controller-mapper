import Foundation

/// Records distinct physical presses in order. Held buttons never auto-repeat.
struct ControllerSequenceCapture {
	private(set) var steps: [ControllerButton] = []
	private(set) var held: Set<ControllerButton>
	private(set) var waitingForRelease: Bool
	private(set) var ambiguous = false
	let limit: Int

	init(initiallyHeld: Set<ControllerButton>, limit: Int = Config.maxSequenceSteps) {
		held = ControllerInputCapture.eligible(initiallyHeld)
		waitingForRelease = !held.isEmpty
		self.limit = limit
	}

	mutating func receive(_ buttons: Set<ControllerButton>) {
		let next = ControllerInputCapture.eligible(buttons)
		let fresh = next.subtracting(held)
		held = next
		if waitingForRelease {
			if next.isEmpty { waitingForRelease = false }
			return
		}
		guard !ambiguous, steps.count < limit else { return }
		guard fresh.count <= 1 else { ambiguous = true; return }
		if let button = fresh.first { steps.append(button) }
	}
}
