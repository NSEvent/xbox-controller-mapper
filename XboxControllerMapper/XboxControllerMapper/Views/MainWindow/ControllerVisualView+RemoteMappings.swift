import Foundation

extension ControllerVisualView {
	/// Keep anchors/icons physical while displaying the same binding the input
	/// engine will execute. The editor opens its existing source binding.
	func remoteReferenceButton(for button: ControllerButton) -> ControllerButton {
		guard isXiaomiRemote || isAppleTVRemote else { return button }
		return RemoteButtonEquivalence.bindingButton(for: button, profile: profileManager.activeProfile, layerId: selectedLayerId)
	}
}
