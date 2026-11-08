import Foundation

/// Release-delimited sequences are independent of the legacy press recognizer.
/// Call under the engine lock. Multiple mappings may complete on one release.
final class ReleasedSequenceDetector {
	nonisolated deinit { }
	struct Progress {
		var count: Int
		var releasedAt: TimeInterval
	}
	enum Feedback: Equatable { case ready, progress(Int), matched, wrongStep, timedOut, ambiguous }
	private var sequences: [SequenceMapping] = []
	private(set) var progress: [UUID: Progress] = [:]
	private(set) var feedback: Feedback = .ready
	private(set) var assembler = SequenceStepAssembler(chordWindow: 0.15)
	var chordWindow: TimeInterval {
		get { assembler.chordWindow }
		set { assembler.chordWindow = newValue }
	}

	func configure(_ sequences: [SequenceMapping]) {
		self.sequences = sequences.filter { $0.usesReleaseSteps && $0.isValid }
		reset()
	}

	func reset(initiallyHeld: Set<ControllerButton>? = nil) {
		assembler = SequenceStepAssembler(initiallyHeld: initiallyHeld ?? assembler.held, chordWindow: chordWindow)
		progress = [:]
		feedback = .ready
	}

	func expire(at time: TimeInterval) {
		guard assembler.candidate.isEmpty else { return } // Long holds are allowed.
		let before = progress.count
		progress = progress.filter { id, value in
			guard let sequence = sequences.first(where: { $0.id == id }) else { return false }
			return time - value.releasedAt <= sequence.stepTimeout
		}
		if progress.count < before { feedback = .timedOut }
	}

	func receive(_ buttons: Set<ControllerButton>, at time: TimeInterval) -> [SequenceMapping] {
		// Expire before the first press, using its original timestamp.
		if assembler.candidate.isEmpty { expire(at: time) }
		guard let event = assembler.receive(buttons, at: time) else { return [] }
		switch event {
		case .began: return []
		case .invalid:
			progress = [:]; feedback = .ambiguous
			return []
		case .completed(let step, _, let releasedAt):
			var completed: [SequenceMapping] = []
			var next: [UUID: Progress] = [:]
			for sequence in sequences {
				let count = progress[sequence.id]?.count ?? 0
				if sequence.inputSteps[count].matches(step) {
					if count + 1 == sequence.inputSteps.count {
						completed.append(sequence)
					} else { next[sequence.id] = Progress(count: count + 1, releasedAt: releasedAt) }
				}
				// A wrong step or a completed suffix can also start a new match.
				if next[sequence.id] == nil, sequence.inputSteps[0].matches(step) {
					next[sequence.id] = Progress(count: 1, releasedAt: releasedAt)
				}
			}
			progress = next
			if !completed.isEmpty { feedback = .matched }
			else if let count = next.values.map(\.count).max() { feedback = .progress(count) }
			else if feedback != .timedOut { feedback = .wrongStep }
			return completed
		}
	}
}
