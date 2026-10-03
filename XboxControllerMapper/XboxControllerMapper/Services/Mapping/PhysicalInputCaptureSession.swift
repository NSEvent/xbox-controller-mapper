import Combine
import Foundation

@MainActor
final class PhysicalInputCaptureSession: ObservableObject {
	@Published private(set) var capture: ControllerInputCapture?
	@Published private(set) var result: Set<ControllerButton>?
	@Published private(set) var message = ""
	@Published private(set) var interrupted = false
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
		updateMessage()
		controller.$isConnected.dropFirst().sink { [weak self] _ in self?.interrupt() }.store(in: &subscriptions)
		engine.profileManager.$activeProfileId.removeDuplicates().dropFirst().sink { [weak self] _ in self?.interrupt() }.store(in: &subscriptions)
		timeout = Task { [weak self] in
			try? await Task.sleep(for: .seconds(30))
			guard !Task.isCancelled, let self, self.isListening else { return }
			self.cancel()
			self.message = "Capture timed out. Try again when you're ready."
		}
	}

	private func receive(_ buttons: Set<ControllerButton>) {
		guard var next = capture else { return }
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
			message = capture.mode == .button
				? "Press the control you want to edit. Mapped actions are paused."
				: "Hold the chord together, then release. Mapped actions are paused."
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
		message = ""
	}

	private func interrupt() {
		cancel()
		interrupted = true
	}
}
