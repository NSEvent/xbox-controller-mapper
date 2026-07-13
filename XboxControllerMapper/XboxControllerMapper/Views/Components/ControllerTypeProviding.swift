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
    /// True for any PlayStation controller (DualSense or DualShock) - used for PS-style labels
    var isPlayStation: Bool { controllerService.threadSafeIsPlayStation }
    var isDualSense: Bool { controllerService.threadSafeIsDualSense }
    var isDualSenseEdge: Bool { controllerService.threadSafeIsDualSenseEdge }
    var isDualShock: Bool { controllerService.threadSafeIsDualShock }
    var isXboxElite: Bool { controllerService.threadSafeIsXboxElite }
    var isSteamController: Bool { controllerService.threadSafeIsSteamController }
    var isNintendo: Bool { controllerService.threadSafeIsNintendo }
    var isAppleTVRemote: Bool { controllerService.threadSafeIsAppleTVRemote }
}
