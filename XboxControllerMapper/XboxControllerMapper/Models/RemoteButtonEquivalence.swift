import Foundation

/// A one-to-one bridge between the 13 physical buttons. Apple clickpad touch
/// is an additional gesture, not another physical key, and has no counterpart.
nonisolated enum RemoteButtonEquivalence {
	static let pairs: [(xiaomi: ControllerButton, apple: ControllerButton)] = [
		(.xiaomiOK, .touchpadButton), (.xiaomiBack, .view),
		(.xiaomiHome, .menu), (.xiaomiMenu, .appleTVRemoteMute),
		(.xiaomiTV, .xbox), (.xiaomiMicrophone, .siri),
		(.xiaomiPower, .appleTVRemotePower),
		(.xiaomiVolumeUp, .appleTVRemoteVolumeUp),
		(.xiaomiVolumeDown, .appleTVRemoteVolumeDown),
	]

	static func counterpart(of button: ControllerButton) -> ControllerButton? {
		for pair in pairs {
			if button == pair.xiaomi { return pair.apple }
			if button == pair.apple { return pair.xiaomi }
		}
		return nil
	}

	static func bindingButton(for button: ControllerButton, profile: Profile?, layerId: UUID?) -> ControllerButton {
		guard let profile else { return button }
		let activators = Dictionary(profile.layers.compactMap { layer in
			layer.activatorButton.map { ($0, layer.id) }
		}, uniquingKeysWith: { _, last in last })
		return ButtonMappingResolutionPolicy.resolvedButton(button: button, profile: profile,
			activeLayerIds: layerId.map { [$0] } ?? [], layerActivatorMap: activators, remoteContext: true)
	}
}
