import Combine

extension ControllerService {
	/// Accepted physical presses, carrying their source at event time. Published
	/// on main even if HID callbacks arrive on a background queue. Unlike the
	/// aggregate held-button state, this cannot confuse simultaneous devices.
	nonisolated var previewActivity: AnyPublisher<ControllerPreviewLayout, Never> {
		storage.previewActivity.eraseToAnyPublisher()
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
}
