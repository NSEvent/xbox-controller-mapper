import Foundation

extension ControllerService {
	nonisolated func observeTimedPhysicalButtons(
		_ observer: @escaping @MainActor (Set<ControllerButton>, TimeInterval) -> Void
	) -> (id: UUID, held: Set<ControllerButton>) {
		storage.lock.withLock {
			let id = UUID()
			storage.timedPhysicalButtonObservers[id] = observer
			return (id, storage.activeButtons)
		}
	}

	/// Registration and its initial snapshot are atomic. Do not replace onInputEvent.
	nonisolated func observePhysicalButtons(
		_ observer: @escaping @MainActor (Set<ControllerButton>) -> Void
	) -> (id: UUID, held: Set<ControllerButton>) {
		storage.lock.withLock {
			let id = UUID()
			storage.physicalButtonObservers[id] = observer
			return (id, storage.activeButtons)
		}
	}

	nonisolated func removePhysicalButtonObserver(_ id: UUID) {
		storage.lock.withLock {
			storage.physicalButtonObservers.removeValue(forKey: id)
			storage.timedPhysicalButtonObservers.removeValue(forKey: id)
		}
	}
}

extension ControllerStorage {
	/// Called under the storage lock, before chord resolution. Queue snapshots in
	/// transition order so quick press/release pairs cannot disappear in UI coalescing.
	func publishPhysicalButtonsLocked() {
		let buttons = activeButtons
		let time = CFAbsoluteTimeGetCurrent()
		for observer in timedPhysicalButtonObservers.values {
			DispatchQueue.main.async { observer(buttons, time) }
		}
		for observer in physicalButtonObservers.values {
			DispatchQueue.main.async { observer(buttons) }
		}
	}
}
