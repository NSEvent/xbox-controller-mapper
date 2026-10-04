import Combine
import Foundation

/// Observe raw button transitions without resolving chords or executing actions.
@MainActor
final class PhysicalButtonReviewSession: ObservableObject {
	@Published private(set) var held: Set<ControllerButton> = []
	@Published private(set) var seen: Set<ControllerButton> = []
	private weak var controller: ControllerService?
	private var observerId: UUID?
	private var generation = UUID()
	private var connection: AnyCancellable?

	func start(controller: ControllerService) {
		stop()
		self.controller = controller
		let current = UUID()
		generation = current
		let registration = controller.observePhysicalButtons { [weak self] buttons in
			guard let self, self.generation == current else { return }
			let eligible = ControllerInputCapture.eligible(buttons)
			if self.held != eligible { self.held = eligible }
			let visited = self.seen.union(eligible)
			if visited != self.seen { self.seen = visited }
		}
		observerId = registration.id
		held = ControllerInputCapture.eligible(registration.held)
		connection = controller.$isConnected.dropFirst().sink { [weak self] _ in
			self?.held = []; self?.seen = []
		}
	}
	func stop() {
		generation = UUID()
		if let observerId { controller?.removePhysicalButtonObserver(observerId) }
		observerId = nil; connection = nil; held = []; seen = []
	}
}
