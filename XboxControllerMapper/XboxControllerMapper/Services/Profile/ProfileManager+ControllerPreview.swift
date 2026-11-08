import Combine

extension ProfileManager {
	/// The profile's Buttons selection is canonical for all mapping editors.
	/// Own this subscription at app lifetime, not window lifetime.
	func bindControllerPreview(to controller: ControllerService) {
		controllerPreviewSelection = controller.latestPreviewLayout ?? activeProfile?.controllerPreviewLayout
		controllerPreviewSubscription = controller.previewActivity.sink { [weak self] layout in
			self?.setControllerPreviewLayout(layout)
		}
		if let layout = controllerPreviewSelection { setControllerPreviewLayout(layout) }
	}
}
