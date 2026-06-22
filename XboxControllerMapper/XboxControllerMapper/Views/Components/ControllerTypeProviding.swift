import SwiftUI

/// Shared controller-type flags for views that render button labels, icons,
/// or controller-specific sections. Conform any view that holds a
/// `ControllerService` (e.g. via `@EnvironmentObject`) to get these for free
/// instead of redeclaring them per view.
///
/// Use `isPlayStation` for label/icon style decisions (PS-style labels apply
/// to DualSense, DualSense Edge, and DualShock alike). Use `isDualSense` /
/// `isDualSenseEdge` only for hardware-specific features (touchpad, mic
/// button, paddles).
protocol ControllerTypeProviding {
    var controllerService: ControllerService { get }
}

extension ControllerTypeProviding {
	var controllerPresentationState: ControllerPresentationState {
		controllerService.threadSafeControllerPresentationState
	}

	/// True for any PlayStation controller (DualSense or DualShock) - used for PS-style labels
	var isPlayStation: Bool { controllerPresentationState.isPlayStation }
	var isDualSense: Bool { controllerPresentationState.isDualSense }
	var isDualSenseEdge: Bool { controllerPresentationState.isDualSenseEdge }
	var isDualShock: Bool { controllerPresentationState.isDualShock }
	var isXboxElite: Bool { controllerPresentationState.isXboxElite }
	var isSteamController: Bool { controllerPresentationState.isSteamController }
	var isNintendo: Bool { controllerPresentationState.isNintendo }
	var isAppleTVRemote: Bool { controllerPresentationState.isAppleTVRemote }
}
