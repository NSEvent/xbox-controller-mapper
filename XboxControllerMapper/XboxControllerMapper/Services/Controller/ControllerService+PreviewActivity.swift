import Combine
import Foundation

extension ControllerService {
	/// New connections and accepted presses, carrying their source at event time. Published
	/// on main even if HID callbacks arrive on a background queue. Unlike the
	/// aggregate held-button state, this cannot confuse simultaneous devices.
	nonisolated var previewActivity: AnyPublisher<ControllerPreviewLayout, Never> {
		storage.previewActivity.eraseToAnyPublisher()
	}
	var latestPreviewLayout: ControllerPreviewLayout? {
		storage.lock.withLock { storage.latestPreviewActivity?.layout }
	}

	/// One ordered stream for genuine connections and accepted input. A delayed
	/// callback must not replace a newer connection/input selection.
	func recordPreviewActivity(_ layout: ControllerPreviewLayout, at time: TimeInterval = CFAbsoluteTimeGetCurrent()) {
		let accepted = storage.lock.withLock {
			guard time >= (storage.latestPreviewActivity?.time ?? -.infinity) else { return false }
			storage.latestPreviewActivity = (layout, time)
			return true
		}
		if accepted { storage.previewActivity.send(layout) }
	}

	func recordControllerConnectionPreview(_ layout: ControllerPreviewLayout) {
		storage.lock.withLock { storage.previewSourceButtons[layout] = nil }
		recordPreviewActivity(layout)
	}

	func recordCurrentControllerConnectionPreview() {
		let descriptor = ControllerVisualDescriptor.active(using: self)
		if let layout = ControllerPreviewLayout.concreteLayouts.first(where: {
			ControllerVisualDescriptor.concrete(for: $0)?.family == descriptor.family
		}) { recordControllerConnectionPreview(layout) }
	}

	// Shared by the live HID services and source-routing integration tests.
	nonisolated func handleFootPedalInput(_ event: FootPedalReportDecoder.Event) {
		controllerQueue.async { [weak self] in
			self?.handleButton(event.button, pressed: event.pressed, source: .footPedal)
		}
	}

	nonisolated func handleXiaomiRemoteInput(_ event: XiaomiRemoteButtonEvent) {
		controllerQueue.async { [weak self] in
			self?.handleButton(event.button, pressed: event.pressed, source: .xiaomiRemote)
		}
	}
	nonisolated func handleWiimoteInput(button: ControllerButton, pressed: Bool) {
		controllerQueue.async { [weak self] in
			self?.handleButton(button, pressed: pressed, source: .wiimote)
		}
	}

}
