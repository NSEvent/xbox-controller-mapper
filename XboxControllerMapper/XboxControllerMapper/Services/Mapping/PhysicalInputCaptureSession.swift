import Combine
import Foundation

@MainActor
final class PhysicalInputCaptureSession: ObservableObject {
	@Published private(set) var capture: ControllerInputCapture?
	@Published private(set) var result: Set<ControllerButton>?
	@Published private(set) var message = ""
	@Published private(set) var interrupted = false
	@Published private(set) var sequence: ControllerSequenceCapture?
	@Published private(set) var sequenceResult: [ControllerButton]?
	private var observerId: UUID?
	private var previewId: UUID?
	private weak var controller: ControllerService?
	private weak var engine: MappingEngine?
	private var timeout: Task<Void, Never>?
	private var subscriptions = Set<AnyCancellable>()
	private var generation = UUID()

	var isActive: Bool { previewId != nil }
	var isListening: Bool { capture?.phase == .listening || capture?.phase == .waitingForRelease }

	func start(mode: ControllerInputCapture.Mode, controller: ControllerService, engine: MappingEngine) {
		cancel()
		interrupted = false
		guard controller.isConnected else { message = "Connect a controller to capture input."; return }
		self.controller = controller
		self.engine = engine
		let currentGeneration = UUID()
		generation = currentGeneration
		previewId = engine.beginInputPreview()
		let registration = controller.observePhysicalButtons { [weak self] buttons in
			guard let self, self.generation == currentGeneration else { return }
			self.receive(buttons)
		}
		observerId = registration.id
		capture = ControllerInputCapture(mode: mode, initiallyHeld: registration.held)
		if mode == .sequence { sequence = ControllerSequenceCapture(initiallyHeld: registration.held) }
		updateMessage()
		controller.$isConnected.dropFirst().sink { [weak self] _ in self?.interrupt("Controller changed or disconnected. Retry capture with the current controller.") }.store(in: &subscriptions)
		engine.profileManager.$activeProfileId.removeDuplicates().dropFirst().sink { [weak self] _ in self?.interrupt("Profile changed. Retry capture in the profile you want to edit.") }.store(in: &subscriptions)
		timeout = Task { [weak self] in
			try? await Task.sleep(for: .seconds(30))
			guard !Task.isCancelled, let self, self.isListening else { return }
			self.cancel()
			self.message = "Capture timed out. Try again when you're ready."
		}
	}

	private func receive(_ buttons: Set<ControllerButton>) {
		guard var next = capture else { return }
		if next.mode == .sequence, next.phase != .captured, var sequence {
			sequence.receive(buttons)
			self.sequence = sequence
			if sequence.ambiguous {
				message = "Two buttons arrived together. Retry and press one at a time to record their order."
			} else if sequence.waitingForRelease {
				message = "Release held controls before recording."
			} else {
				message = sequence.steps.count == sequence.limit ? "Maximum steps reached. Choose Use Sequence or retry." : "Press buttons in order, then choose Use Sequence. Mapped actions are paused."
			}
			return
		}
		let selected = next.receive(buttons)
		capture = next
		updateMessage()
		if let selected {
			timeout?.cancel()
			result = selected
		}
	}

	private func updateMessage() {
		guard let capture else { return }
		switch capture.phase {
		case .waitingForRelease: message = "Release the controls you're holding, then try your input."
		case .listening:
			switch capture.mode {
			case .button: message = "Press the control you want to edit. Mapped actions are paused."
			case .chord: message = "Hold the chord together, then release. Mapped actions are paused."
			case .sequence: message = "Press buttons in order, then choose Use Sequence. Mapped actions are paused."
			}
		case .captured: message = "Input captured. Mapped actions stay paused while you edit."
		case .ambiguous: message = "Different chords overlapped. Retry and hold one combination together."
		}
	}

	func cancel() {
		generation = UUID()
		timeout?.cancel()
		timeout = nil
		subscriptions.removeAll()
		if let observerId { controller?.removePhysicalButtonObserver(observerId) }
		if let previewId { engine?.endInputPreview(previewId) }
		observerId = nil
		previewId = nil
		capture = nil
		result = nil
		sequence = nil
		sequenceResult = nil
		message = ""
	}

	func finishSequence() {
		guard let sequence, !sequence.ambiguous, sequence.steps.count >= 2 else { return }
		timeout?.cancel()
		sequenceResult = sequence.steps
		// Keep the preview lease while the user edits the captured sequence.
		capture = nil
		message = "Sequence captured. Mapped actions stay paused while you edit."
	}

	private func interrupt(_ reason: String) {
		cancel()
		message = reason
		interrupted = true
	}
}
