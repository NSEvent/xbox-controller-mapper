import Foundation

/// Resolves the effective button mapping for the current profile + layer context.
enum ButtonMappingResolutionPolicy {
    static func resolve(
        button: ControllerButton,
        profile: Profile,
        activeLayerIds: [UUID],
        layerActivatorMap: [ControllerButton: UUID]
    ) -> KeyMapping? {
        // Layer activators only switch layers and do not emit output mappings.
        if layerActivatorMap[button] != nil {
            return nil
        }

        // Only the most recently activated layer is considered active.
        if let activeLayerId = activeLayerIds.last,
           let layer = profile.layers.first(where: { $0.id == activeLayerId }),
           let mapping = layer.buttonMappings[button], !mapping.isEmpty {
            return mapping
        }

        if let mapping = profile.buttonMappings[button], !mapping.isEmpty {
            return mapping
        }

        return defaultMapping(for: button)
    }

    private static func defaultMapping(for button: ControllerButton) -> KeyMapping? {
        switch button {
        case .touchpadButton:
            // DualSense touchpad click defaults to left mouse click.
            return KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true)
        case .touchpadTwoFingerButton:
            // DualSense touchpad two-finger click defaults to right mouse click.
            return KeyMapping(keyCode: KeyCodeMapping.mouseRightClick, isHoldModifier: true)
        case .touchpadTap:
            // DualSense touchpad single tap defaults to left mouse click.
            return KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true)
        case .touchpadTwoFingerTap:
            // DualSense touchpad two-finger tap defaults to right mouse click.
            return KeyMapping(keyCode: KeyCodeMapping.mouseRightClick, isHoldModifier: true)
        default:
            return nil
        }
    }
}
