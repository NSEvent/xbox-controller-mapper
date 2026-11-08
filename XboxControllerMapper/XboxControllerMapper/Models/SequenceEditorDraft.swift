import Foundation

struct SequenceEditorDraft {
	var steps: [SequenceStep] = []
	var usesReleaseSteps = true
	private(set) var isEditingStep = true
	private(set) var selection: Set<ControllerButton> = []
	private(set) var editingIndex: Int?

	var selectionError: String? { SequenceStep(selection).validationMessage }
	var canCommitStep: Bool {
		isEditingStep && selectionError == nil && (editingIndex != nil || steps.count < Config.maxSequenceSteps)
	}
	var canSave: Bool {
		!isEditingStep && (2...Config.maxSequenceSteps).contains(steps.count)
			&& steps.allSatisfy { $0.validationMessage == nil }
	}
	mutating func load(_ sequence: SequenceMapping) {
		steps = sequence.inputSteps
		usesReleaseSteps = sequence.usesReleaseSteps
		cancelStep()
	}
	mutating func edit(_ index: Int? = nil) {
		editingIndex = index
		selection = index.map { Set(steps[$0].buttons) } ?? []
		isEditingStep = true
	}
	mutating func toggle(_ button: ControllerButton) {
		if !selection.insert(button).inserted { selection.remove(button) }
	}
	mutating func commitStep() {
		guard canCommitStep else { return }
		let step = SequenceStep(selection)
		if let editingIndex { steps[editingIndex] = step } else { steps.append(step) }
		if step.buttons.count > 1 { usesReleaseSteps = true }
		cancelStep()
	}
	mutating func cancelStep() { isEditingStep = false; selection = []; editingIndex = nil }
	mutating func duplicate(_ index: Int) {
		guard steps.count < Config.maxSequenceSteps else { return }
		steps.insert(steps[index], at: index + 1)
	}
	mutating func move(_ index: Int, by offset: Int) {
		guard steps.indices.contains(index + offset) else { return }
		steps.swapAt(index, index + offset)
	}
	mutating func remove(_ index: Int) { steps.remove(at: index) }
	mutating func useRecording(_ recorded: [SequenceStep]) {
		guard (2...Config.maxSequenceSteps).contains(recorded.count) else { return }
		steps = recorded; usesReleaseSteps = true; cancelStep()
	}
}

struct SequenceRecording {
	private(set) var steps: [SequenceStep] = []
	private(set) var assembler: SequenceStepAssembler
	private(set) var ambiguous = false
	let limit: Int
	init(initiallyHeld: Set<ControllerButton>, chordWindow: TimeInterval, limit: Int = Config.maxSequenceSteps) {
		assembler = SequenceStepAssembler(initiallyHeld: initiallyHeld, chordWindow: chordWindow)
		self.limit = limit
	}
	var canUse: Bool { steps.count >= 2 && assembler.held.isEmpty && !ambiguous }
	mutating func receive(_ buttons: Set<ControllerButton>, at time: TimeInterval) {
		let event = assembler.receive(buttons, at: time)
		guard !ambiguous, steps.count < limit else { return }
		if case .completed(let step, _, _) = event { steps.append(step) }
		if case .invalid = event { ambiguous = true }
	}
	mutating func retryStep() {
		assembler = SequenceStepAssembler(initiallyHeld: assembler.held, chordWindow: assembler.chordWindow)
		ambiguous = false
	}
	mutating func undo() {
		guard assembler.held.isEmpty else { return }
		if ambiguous { retryStep() } else if !steps.isEmpty { steps.removeLast() }
	}
}
