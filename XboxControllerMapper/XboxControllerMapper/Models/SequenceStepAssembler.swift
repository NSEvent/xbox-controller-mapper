import Foundation

/// Used by both recording and recognition. Timestamps belong to the physical
/// transition, never to delayed main-queue delivery or chord resolution.
struct SequenceStepAssembler {
	enum Event: Equatable {
		case began(TimeInterval)
		case completed(SequenceStep, startedAt: TimeInterval, releasedAt: TimeInterval)
		case invalid
	}
	private(set) var held: Set<ControllerButton>
	private(set) var candidate: Set<ControllerButton> = []
	private(set) var waitingForRelease: Bool
	private var beganAt: TimeInterval = 0
	private var releasedMember = false
	private var invalid = false
	var chordWindow: TimeInterval

	init(initiallyHeld: Set<ControllerButton> = [], chordWindow: TimeInterval) {
		held = Self.eligible(initiallyHeld)
		waitingForRelease = !held.isEmpty
		self.chordWindow = chordWindow
	}

	static func eligible(_ buttons: Set<ControllerButton>) -> Set<ControllerButton> {
		Set(buttons.filter { !$0.isGestureButton })
	}

	mutating func receive(_ buttons: Set<ControllerButton>, at time: TimeInterval) -> Event? {
		let next = Self.eligible(buttons)
		let fresh = next.subtracting(held)
		let released = !held.subtracting(next).isEmpty
		held = next
		if waitingForRelease {
			if next.isEmpty { waitingForRelease = false }
			return nil
		}
		if candidate.isEmpty {
			guard !fresh.isEmpty else { return nil }
			candidate = next
			beganAt = time
			releasedMember = false
			invalid = false
			return .began(time)
		}
		releasedMember = releasedMember || released
		if !fresh.isEmpty && (releasedMember || time - beganAt > chordWindow) {
			let wasInvalid = invalid
			invalid = true
			if !wasInvalid { return .invalid }
		}
		candidate.formUnion(fresh)
		guard next.isEmpty else { return nil }
		defer { candidate = []; invalid = false; releasedMember = false }
		guard !invalid else { return nil }
		let step = SequenceStep(candidate)
		guard step.validationMessage == nil else { return .invalid }
		return .completed(step, startedAt: beganAt, releasedAt: time)
	}
}
