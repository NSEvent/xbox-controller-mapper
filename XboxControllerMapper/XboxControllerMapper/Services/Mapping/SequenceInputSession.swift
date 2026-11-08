import Combine
import Foundation

/// Temporary input preview shared by recording and isolated Try Sequence.
/// No action executor is exposed here; accepting is the only draft mutation.
@MainActor
final class SequenceInputSession: ObservableObject {
	@Published private(set) var recording: SequenceRecording?
	@Published private(set) var isTrying = false
	@Published private(set) var message = ""
	@Published private(set) var matchedSteps = 0
	@Published private(set) var interrupted = false
	private var observerID: UUID?
	private var previewID: UUID?
	private weak var controller: ControllerService?
	private weak var engine: MappingEngine?
	private var subscriptions = Set<AnyCancellable>()
	private var timer: Task<Void, Never>?
	private var generation = UUID()
	private var trial: SequenceMapping?
	private let detector = SequenceDetector()
	private var held: Set<ControllerButton> = []
	private var waitingForRelease = false

	var isBusy: Bool { recording != nil || isTrying }

	func startRecording(controller: ControllerService, engine: MappingEngine) {
		guard let initiallyHeld = begin(controller: controller, engine: engine) else { return }
		recording = SequenceRecording(initiallyHeld: initiallyHeld, chordWindow: controller.threadSafeChordWindow)
		message = "Press a button or chord, then release all controls. Mapped actions are paused."
	}

	func startTrying(_ sequence: SequenceMapping, controller: ControllerService, engine: MappingEngine) {
		guard let initiallyHeld = begin(controller: controller, engine: engine) else { return }
		trial = sequence
		detector.configure(sequences: [sequence])
		detector.released.chordWindow = controller.threadSafeChordWindow
		detector.released.reset(initiallyHeld: initiallyHeld)
		held = initiallyHeld
		waitingForRelease = !held.isEmpty
		isTrying = true
		message = waitingForRelease ? "Release held controls to begin." : "Try the sequence. All actions are paused."
		timer = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .milliseconds(100))
				guard !Task.isCancelled, let self else { return }
				if self.trial?.usesReleaseSteps == true {
					self.detector.released.expire(at: CFAbsoluteTimeGetCurrent())
					if self.detector.released.feedback == .timedOut { self.updateTrialFeedback() }
				} else if let progress = self.detector.activeSequences.first,
					CFAbsoluteTimeGetCurrent() - progress.lastStepTime > progress.stepTimeout {
					self.detector.reset(); self.matchedSteps = 0
					self.message = "Timed out. Try again from the first step."
				}
			}
		}
	}

	private func begin(controller: ControllerService, engine: MappingEngine) -> Set<ControllerButton>? {
		cancel()
		interrupted = false
		guard controller.isConnected else { message = "Connect a controller first."; return nil }
		self.controller = controller; self.engine = engine
		previewID = engine.beginInputPreview()
		let token = generation
		let registration = controller.observeTimedPhysicalButtons { [weak self] buttons, time in
			guard let self, self.generation == token else { return }
			self.receive(buttons, at: time)
		}
		observerID = registration.id
		controller.$isConnected.dropFirst().sink { [weak self] _ in self?.interrupt() }.store(in: &subscriptions)
		engine.profileManager.$activeProfileId.removeDuplicates().dropFirst().sink { [weak self] _ in self?.interrupt() }.store(in: &subscriptions)
		return registration.held
	}

	private func receive(_ buttons: Set<ControllerButton>, at time: TimeInterval) {
		if recording != nil {
			recording?.receive(buttons, at: time)
			return
		}
		guard isTrying, let trial else { return }
		if trial.usesReleaseSteps {
			_ = detector.released.receive(buttons, at: time)
			updateTrialFeedback()
		} else {
			let fresh = buttons.subtracting(held)
			held = buttons
			if waitingForRelease {
				if held.isEmpty { waitingForRelease = false; message = "Ready. Press the first step." }
				return
			}
			for button in ControllerButton.allCases where fresh.contains(button) {
				if detector.process(button, at: time) != nil {
					matchedSteps = trial.inputSteps.count; message = "Matched. No action was run."
				} else {
					matchedSteps = detector.activeSequences.first?.matchedCount ?? 0
					message = matchedSteps == 0 ? "Wrong step. Try again." : "Step \(matchedSteps) matched."
				}
			}
		}
	}

	private func updateTrialFeedback() {
		switch detector.released.feedback {
		case .ready: break
		case .progress(let count): matchedSteps = count; message = "Step \(count) matched."
		case .matched: matchedSteps = trial?.inputSteps.count ?? 0; message = "Matched. No action was run."
		case .wrongStep: matchedSteps = 0; message = "Wrong step. Try again from the first step."
		case .timedOut: matchedSteps = 0; message = "Timed out. Try again from the first step."
		case .ambiguous: matchedSteps = 0; message = "Buttons must overlap within the chord window. Release all controls and retry."
		}
	}

	func retryStep() { recording?.retryStep() }
	func undo() { recording?.undo() }
	func startOver() {
		guard let recording else { return }
		self.recording = SequenceRecording(initiallyHeld: recording.assembler.held, chordWindow: recording.assembler.chordWindow)
	}
	func acceptRecording() -> [SequenceStep]? {
		guard let recording, recording.canUse else { return nil }
		self.recording = nil
		message = "Recording accepted. Mapped actions stay paused until you close this editor."
		return recording.steps
	}
	func cancel() {
		generation = UUID()
		timer?.cancel(); timer = nil
		subscriptions.removeAll()
		if let observerID { controller?.removePhysicalButtonObserver(observerID) }
		if let previewID { engine?.endInputPreview(previewID) }
		observerID = nil; previewID = nil
		recording = nil; isTrying = false; trial = nil; message = ""; matchedSteps = 0
	}
	private func interrupt() {
		cancel(); interrupted = true
		message = "Controller or profile changed. Recording cancelled."
	}
}
