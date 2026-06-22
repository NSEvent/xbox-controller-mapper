import SwiftUI

/// Shared controller presentation snapshot for views that render button labels,
/// icons, or controller-specific sections. Conform any view that holds a
/// `ControllerService` (e.g. via `@EnvironmentObject`) and capture
/// `controllerPresentationState` once per render before deriving flags from it.
///
/// Use `presentationState.isPlayStation` for label/icon style decisions
/// (PS-style labels apply to DualSense, DualSense Edge, and DualShock alike).
/// Use hardware-specific flags only for hardware-specific features.
protocol ControllerTypeProviding {
    var controllerService: ControllerService { get }
}

extension ControllerTypeProviding {
	var controllerPresentationState: ControllerPresentationState {
		controllerService.threadSafeControllerPresentationState
	}
}
