import SwiftUI
import GameController
import AppKit
import Combine
import CoreTransferable

// MARK: - Drag & Drop

/// Transports a `ControllerButton` across a SwiftUI drag-and-drop. Backed by the
/// enum's String rawValue, which is already its on-disk identity in the config.
extension ControllerButton: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { (button: ControllerButton) -> String in button.rawValue },
            importing: { (rawValue: String) -> ControllerButton in
                guard let button = ControllerButton(rawValue: rawValue) else {
                    throw CocoaError(.coderInvalidValue)
                }
                return button
            }
        )
    }
}

/// Marks a view as draggable for `button` and as a drop target that swaps mappings
/// between the dropped source button and `button`. While the drop target is hovered,
/// the view glows in the accent color and scales up slightly. Implemented as a
/// `ViewModifier` (not a plain extension) so we can hold `@State` for `isTargeted`.
private struct SwappableModifier: ViewModifier {
    let button: ControllerButton
    let onSwap: ((ControllerButton, ControllerButton) -> Void)?
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isTargeted ? 1.08 : 1.0)
            .shadow(
                color: Color.accentColor.opacity(isTargeted ? 0.9 : 0),
                radius: isTargeted ? 8 : 0
            )
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
            .draggable(button)
            .dropDestination(for: ControllerButton.self) { items, _ in
                guard let onSwap, let source = items.first else { return false }
                onSwap(source, button)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }
}

extension View {
    fileprivate func swappable(
        _ button: ControllerButton,
        onSwap: ((ControllerButton, ControllerButton) -> Void)?
    ) -> some View {
        modifier(SwappableModifier(button: button, onSwap: onSwap))
    }
}

// MARK: - Connector Layer Types

enum ConnectorRole {
    case controller
    case label
}

private enum DirectionClusterCenter {
    case button(ControllerButton)
    case label(String)
    case dpadPreset
}

private struct CompactActionBadge: Identifiable {
    let label: String
    let color: Color

    var id: String { label }
}

struct ConnectorEndpoint {
    let button: ControllerButton
    let role: ConnectorRole
    let anchor: Anchor<CGRect>
}

struct ControllerButtonAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [ConnectorEndpoint] = []
    static func reduce(value: inout [ConnectorEndpoint], nextValue: () -> [ConnectorEndpoint]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Reports this view's bounds as a connector endpoint for the given button.
    /// Used to draw connector lines between controller-side mini buttons and their action labels.
    func controllerAnchor(_ button: ControllerButton, role: ConnectorRole) -> some View {
        controllerAnchor([button], role: role)
    }

    /// Reports this view's bounds as a connector endpoint for each of the given buttons.
    /// Used when multiple actions visually share a single controller element (e.g. all
    /// touchpad gestures originate from the same touchpad rect). Stacking individual
    /// `.controllerAnchor(...)` modifiers does NOT reliably propagate every endpoint
    /// — emitting them all from one `anchorPreference` call does.
    func controllerAnchor(_ buttons: [ControllerButton], role: ConnectorRole) -> some View {
        anchorPreference(
            key: ControllerButtonAnchorPreferenceKey.self,
            value: .bounds
        ) { anchor in
            buttons.map { ConnectorEndpoint(button: $0, role: role, anchor: anchor) }
        }
    }
}

/// Interactive visual representation of a controller with a professional Reference Page layout
/// Automatically adapts to show Xbox or DualSense layouts based on connected controller
struct ControllerVisualView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    @Binding var selectedButton: ControllerButton?
    var selectedLayerId: UUID? = nil  // nil = base layer
    var swapFirstButton: ControllerButton? = nil  // First button selected in swap mode
    var isSwapMode: Bool = false
    var onButtonTap: (ControllerButton) -> Void

    @State private var hoveredButton: ControllerButton?

    private var isDualSense: Bool {
        controllerService.threadSafeIsDualSense
    }

    private var isDualShock: Bool {
        controllerService.threadSafeIsDualShock
    }

    /// True for any PlayStation controller (DualSense or DualShock) - used for PS-style labels and touchpad UI
    private var isPlayStation: Bool {
        controllerService.threadSafeIsPlayStation
    }

    private var isDualSenseEdge: Bool {
        controllerService.threadSafeIsDualSenseEdge
    }

    private var isXboxElite: Bool {
        controllerService.threadSafeIsXboxElite
    }

    private var isNintendo: Bool {
        controllerService.threadSafeIsNintendo
    }

    private var joystickSettings: JoystickSettings {
        profileManager.activeProfile?.joystickSettings ?? .default
    }

    private var leftStickDirectionButtons: [ControllerButton] {
        joystickSettings.chordSequenceJoystickDirectionButtons(side: .left)
    }

    private var rightStickDirectionButtons: [ControllerButton] {
        joystickSettings.chordSequenceJoystickDirectionButtons(side: .right)
    }

    /// Returns the currently selected layer, if any
    private var selectedLayer: Layer? {
        guard let layerId = selectedLayerId,
              let profile = profileManager.activeProfile else { return nil }
        return profile.layers.first(where: { $0.id == layerId })
    }

    private var connectorEmphasisButtons: Set<ControllerButton> {
        Set(ControllerButton.allCases.filter { button in
            if layerForButton(button) != nil && !isEditingDifferentLayer(button) {
                return true
            }
            return mapping(for: button) != nil
        })
    }

    /// Checks if a button is a layer activator
    private func isLayerActivator(_ button: ControllerButton) -> Bool {
        guard let profile = profileManager.activeProfile else { return false }
        return profile.layers.contains { $0.activatorButton == button }
    }

    /// Returns the layer that a button activates, if any
    private func layerForButton(_ button: ControllerButton) -> Layer? {
        guard let profile = profileManager.activeProfile else { return nil }
        return profile.layers.first { $0.activatorButton == button }
    }

    /// Returns true if this button is the activator for the currently selected layer
    /// (meaning it shouldn't be clickable when viewing that layer)
    private func isActivatorForSelectedLayer(_ button: ControllerButton) -> Bool {
        guard let layer = selectedLayer else { return false }
        return layer.activatorButton == button
    }

    /// Returns true if this button is the activator for the currently selected layer.
    /// Only that specific activator should be dimmed/disabled — other layer activators
    /// are freed up for remapping within the current layer.
    private func isLayerActivatorInLayerContext(_ button: ControllerButton) -> Bool {
        return isActivatorForSelectedLayer(button)
    }

    /// Returns true if we're editing a layer AND this button activates a DIFFERENT layer.
    /// In that case, we show the layer mapping instead of the activator badge.
    private func isEditingDifferentLayer(_ button: ControllerButton) -> Bool {
        guard selectedLayerId != nil else { return false }
        guard let layer = layerForButton(button) else { return false }
        return layer.id != selectedLayerId
    }

    /// Returns the layer's configured LED color, or fallback purple if none.
    private func layerColor(_ layer: Layer) -> Color {
        if let led = layer.dualSenseLEDSettings, led.lightBarEnabled {
            return led.lightBarColor.color
        }
        return Color.purple
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left Column: Shoulder and Left-side inputs
            VStack(alignment: .trailing, spacing: 16) {
                referenceGroup(title: "Shoulder", buttons: [.leftTrigger, .leftBumper])
                stickModeSection(title: "Left Stick", side: .left, center: .leftThumbstick)
                dpadDirectionCluster
            }
            .frame(width: 220)
            .padding(.trailing, 20)

            // Center Column: Controller Graphic and System Buttons
            VStack(spacing: 20) {
                // Touchpad section (PlayStation controllers) — header has a
                // mode picker that switches between the classic 4-button
                // layout and the 8-button quadrant layout. Two-finger buttons
                // stay visible in both modes since there's no quadrant
                // analog for two fingers.
                if isPlayStation {
                    touchpadButtonsSection
                }

                ZStack {
                    // Controller body - adapts to DualSense or Xbox shape
                    controllerBodyView
                        .frame(width: 320, height: 220)

                    // Compact Controller Overlay (Just icons, no labels)
                    // Extracted into a separate view to isolate 15Hz analog display
                    // updates from the rest of the view hierarchy
                    ControllerAnalogOverlay(
                        controllerService: controllerService,
                        isPlayStation: isPlayStation,
                        isNintendo: isNintendo,
                        isXboxElite: isXboxElite,
                        touchpadInputMode: touchpadInputMode,
                        onButtonTap: onButtonTap,
                        onButtonHover: handleButtonHover,
                        onSwapRequest: performSwap
                    )
                }
                .accessibilityHidden(true)

                // System Buttons Reference
                HStack(spacing: 20) {
                    VStack(alignment: .trailing) {
                        referenceRow(for: .view)
                        referenceRow(for: .xbox)
                    }
                    .frame(width: 220)
                    VStack(alignment: .leading) {
                        referenceRow(for: .menu)
                        // Show mic mute for DualSense, share for Xbox (but not Elite 2 where
                        // the Share button is the hardware profile cycle button, not mappable)
                        // DualShock 4's physical Share button maps to .view (buttonOptions), not .share
                        if isDualSense {
                            referenceRow(for: .micMute)
                        } else if !isDualShock && !isXboxElite {
                            referenceRow(for: .share)
                        }
                    }
                    .frame(width: 220)
                }

                // Edge-specific buttons (paddles and function buttons)
                if isDualSenseEdge {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EDGE CONTROLS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                        HStack(spacing: 20) {
                            VStack(alignment: .trailing) {
                                referenceRow(for: .leftFunction)
                                referenceRow(for: .leftPaddle)
                            }
                            .frame(width: 220)
                            VStack(alignment: .leading) {
                                referenceRow(for: .rightFunction)
                                referenceRow(for: .rightPaddle)
                            }
                            .frame(width: 220)
                        }
                    }
                }

                // Xbox Elite-specific buttons (back paddles)
                if isXboxElite {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ELITE PADDLES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Upper")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.7))
                                .padding(.horizontal, 4)
                            HStack(spacing: 20) {
                                referenceRow(for: .xboxPaddle1)
                                    .frame(width: 220, alignment: .trailing)
                                referenceRow(for: .xboxPaddle2)
                                    .frame(width: 220, alignment: .leading)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lower")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.7))
                                .padding(.horizontal, 4)
                            HStack(spacing: 20) {
                                referenceRow(for: .xboxPaddle3)
                                    .frame(width: 220, alignment: .trailing)
                                referenceRow(for: .xboxPaddle4)
                                    .frame(width: 220, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .frame(width: 460)

            // Right Column: Face buttons and Right-side inputs
            VStack(alignment: .leading, spacing: 16) {
                referenceGroup(title: "Shoulder", buttons: [.rightTrigger, .rightBumper])
                referenceGroup(title: "Actions", buttons: [.y, .b, .a, .x])
                stickModeSection(title: "Right Stick", side: .right, center: .rightThumbstick)
            }
            .frame(width: 220)
            .padding(.leading, 20)
        }
        .padding(20)
        .overlayPreferenceValue(ControllerButtonAnchorPreferenceKey.self) { endpoints in
            GeometryReader { proxy in
                ConnectorLayer(
                    endpoints: endpoints,
                    proxy: proxy,
                    hoveredButton: hoveredButton,
                    emphasizedButtons: connectorEmphasisButtons
                )
            }
        }
    }

    private func handleButtonHover(_ button: ControllerButton, _ hovering: Bool) {
        if hovering {
            hoveredButton = button
        } else if hoveredButton == button {
            hoveredButton = nil
        }
    }

    // MARK: - Touchpad Buttons Section (mode picker + bindings)

    private var touchpadInputMode: TouchpadInputMode {
        profileManager.activeProfile?.touchpadInputMode ?? .wholePad
    }

    /// Toggle between whole-pad and quadrants mode. Routes through
    /// `ProfileManager.setTouchpadInputMode` so the change persists and
    /// `MappingEngine` re-syncs the controller-side flag.
    private func setTouchpadInputMode(_ mode: TouchpadInputMode) {
        profileManager.setTouchpadInputMode(mode)
    }

    @ViewBuilder
    private var touchpadButtonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("TOUCHPAD")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                touchpadModeTabs
            }
            .padding(.horizontal, 4)

            switch touchpadInputMode {
            case .wholePad:
                wholePadTouchpadRows
            case .quadrants:
                quadrantTouchpadRows
            }
        }
    }

    /// Pill-style tab pair matching `LayerTabBar`: active tab uses the accent
    /// color, inactive uses a faint white wash. Animates the swap so it feels
    /// like a tab transition rather than a settings flip.
    private var touchpadModeTabs: some View {
        HStack(spacing: 6) {
            touchpadModeTab(.wholePad, label: "Whole Pad", systemImage: "rectangle")
            touchpadModeTab(.quadrants, label: "Quadrants", systemImage: "rectangle.split.2x2")
        }
        .animation(.easeInOut(duration: 0.15), value: touchpadInputMode)
    }

    @ViewBuilder
    private func touchpadModeTab(_ mode: TouchpadInputMode, label: String, systemImage: String) -> some View {
        let isSelected = touchpadInputMode == mode
        Button {
            setTouchpadInputMode(mode)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color.white.opacity(0.08))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(isSelected ? 0 : 0.05), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .white : .secondary)
        .hoverableButton()
    }

    /// Classic 4-row layout: single + two-finger × {click, tap}. Reflects
    /// `Profile.touchpadInputMode == .wholePad`.
    @ViewBuilder
    private var wholePadTouchpadRows: some View {
        HStack(spacing: 20) {
            VStack(alignment: .trailing) {
                referenceRow(for: .touchpadButton)
                referenceRow(for: .touchpadTap)
            }
            .frame(width: 220)
            VStack(alignment: .leading) {
                referenceRow(for: .touchpadTwoFingerButton)
                referenceRow(for: .touchpadTwoFingerTap)
            }
            .frame(width: 220)
        }
    }

    /// Quadrants mode rows. Two-finger buttons still appear (they have no
    /// quadrant analog) followed by the eight per-quadrant rows grouped in a
    /// 2×2 layout that mirrors the touchpad's physical orientation.
    @ViewBuilder
    private var quadrantTouchpadRows: some View {
        HStack(spacing: 20) {
            VStack(alignment: .trailing) {
                referenceRow(for: .touchpadTwoFingerButton)
            }
            .frame(width: 220)
            VStack(alignment: .leading) {
                referenceRow(for: .touchpadTwoFingerTap)
            }
            .frame(width: 220)
        }

        // Per-quadrant rows: top-left + top-right grouped, then bottom row.
        // Click and Touch variants are stacked within each quadrant column so
        // users can see both bindings for a single quadrant at a glance.
        HStack(spacing: 20) {
            VStack(alignment: .trailing, spacing: 4) {
                referenceRow(for: .touchpadRegionTopLeftClick)
                referenceRow(for: .touchpadRegionTopLeftTouch)
            }
            .frame(width: 220)
            VStack(alignment: .leading, spacing: 4) {
                referenceRow(for: .touchpadRegionTopRightClick)
                referenceRow(for: .touchpadRegionTopRightTouch)
            }
            .frame(width: 220)
        }
        HStack(spacing: 20) {
            VStack(alignment: .trailing, spacing: 4) {
                referenceRow(for: .touchpadRegionBottomLeftClick)
                referenceRow(for: .touchpadRegionBottomLeftTouch)
            }
            .frame(width: 220)
            VStack(alignment: .leading, spacing: 4) {
                referenceRow(for: .touchpadRegionBottomRightClick)
                referenceRow(for: .touchpadRegionBottomRightTouch)
            }
            .frame(width: 220)
        }
    }

    /// Swaps two buttons' mappings, dispatching to the layer-specific or base-layer
    /// swap method to match the existing tap-select-tap swap mode in `ButtonMappingsTab`.
    private func performSwap(from source: ControllerButton, to target: ControllerButton) {
        guard source != target else { return }
        if let layerId = selectedLayerId {
            profileManager.swapLayerMappings(button1: source, button2: target, in: layerId)
        } else {
            profileManager.swapMappings(button1: source, button2: target)
        }
    }

    // MARK: - Controller Body

    @ViewBuilder
    private var controllerBodyView: some View {
        if isPlayStation {
            DualSenseBodyShape()  // DualSense/DualShock share similar body shape
                .fill(LinearGradient(
                    colors: [Color(white: 0.95), Color(white: 0.88)], // PlayStation white/light grey
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        } else if isNintendo {
            NintendoProBodyShape()
                .fill(LinearGradient(
                    colors: [Color(white: 0.18), Color(white: 0.12)], // Nintendo Pro Controller dark charcoal
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        } else {
            ControllerBodyShape()
                .fill(LinearGradient(
                    colors: [Color(white: 0.95), Color(white: 0.9)], // Xbox light theme
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
    }

    // MARK: - Reference UI Components

    @ViewBuilder
    private func referenceGroup(title: String, buttons: [ControllerButton], rowSpacing: CGFloat = 12) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: rowSpacing) {
                ForEach(buttons) { button in
                    referenceRow(for: button)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func stickModeSection(title: String, side: JoystickSide, center: ControllerButton) -> some View {
        let mode = stickMode(side: side)
        let buttons = Set(side == .left ? leftStickDirectionButtons : rightStickDirectionButtons)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(LocalizedStringKey(title))
                    .textCase(.uppercase)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer(minLength: 4)
                if mode.exposesJoystickDirections {
                    stickPresetMenu(side: side)
                }
                stickModeMenu(side: side)
            }
            .padding(.horizontal, 4)

            if hasOrphanedStickDirectionMappings(side: side) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text("Direction bindings inactive — switch mode to Custom to use them.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }

            if mode.exposesJoystickDirections {
                directionClusterGrid(
                    up: buttons.contains(ControllerButton.joystickDirectionButton(side: side, direction: .up))
                        ? ControllerButton.joystickDirectionButton(side: side, direction: .up)
                        : nil,
                    left: buttons.contains(ControllerButton.joystickDirectionButton(side: side, direction: .left))
                        ? ControllerButton.joystickDirectionButton(side: side, direction: .left)
                        : nil,
                    center: .button(center),
                    right: buttons.contains(ControllerButton.joystickDirectionButton(side: side, direction: .right))
                        ? ControllerButton.joystickDirectionButton(side: side, direction: .right)
                        : nil,
                    down: buttons.contains(ControllerButton.joystickDirectionButton(side: side, direction: .down))
                        ? ControllerButton.joystickDirectionButton(side: side, direction: .down)
                        : nil
                )
            } else {
                referenceRow(for: center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dpadDirectionCluster: some View {
        directionCluster(
            title: "D-Pad",
            up: .dpadUp,
            left: .dpadLeft,
            center: .dpadPreset,
            right: .dpadRight,
            down: .dpadDown
        )
    }

    /// Returns true when the current editing scope (layer if selected, else profile) has direction
    /// button mappings for this side, but the effective stick mode won't dispatch them at runtime.
    /// Used to surface a small "these bindings won't fire" hint next to the stick mode picker so
    /// users don't get silently confused after switching mode away from Custom.
    private func hasOrphanedStickDirectionMappings(side: JoystickSide) -> Bool {
        guard !stickMode(side: side).exposesJoystickDirections else { return false }
        let directionButtons = Set(ControllerButton.joystickDirectionButtons(side: side))

        // Editing a layer: check that layer's own mappings (not the base).
        // Editing the base: check the profile-level mappings.
        let scopedMappings: [ControllerButton: KeyMapping]
        if let layer = selectedLayer {
            scopedMappings = layer.buttonMappings
        } else {
            scopedMappings = profileManager.activeProfile?.buttonMappings ?? [:]
        }
        return scopedMappings.keys.contains { directionButtons.contains($0) }
    }

    private func profileStickMode(side: JoystickSide) -> StickMode {
        switch side {
        case .left:
            return joystickSettings.leftStickMode
        case .right:
            return joystickSettings.rightStickMode
        }
    }

    private func layerStickModeOverride(side: JoystickSide) -> StickMode? {
        guard let layer = selectedLayer else { return nil }
        switch side {
        case .left:
            return layer.leftStickModeOverride
        case .right:
            return layer.rightStickModeOverride
        }
    }

    /// Effective mode resolved at the current editing scope: layer override (if any) → profile default.
    /// Mirrors `JoystickHandler`'s runtime resolution so the picker label and the actual behavior stay aligned.
    private func stickMode(side: JoystickSide) -> StickMode {
        layerStickModeOverride(side: side) ?? profileStickMode(side: side)
    }

    /// True when editing a layer AND that layer has no override for this side, so the displayed
    /// mode is inherited from the base profile. Used to subtly italicize the picker label.
    private func isStickModeInherited(side: JoystickSide) -> Bool {
        selectedLayerId != nil && layerStickModeOverride(side: side) == nil
    }

    private func setStickMode(_ mode: StickMode, side: JoystickSide) {
        guard mode.isVisibleInUI else { return }
        profileManager.setStickMode(mode, side: side, layerId: selectedLayerId)
    }

    private func clearStickModeOverride(side: JoystickSide) {
        guard let layerId = selectedLayerId else { return }
        profileManager.setStickMode(nil, side: side, layerId: layerId)
    }

    private func stickModeMenu(side: JoystickSide) -> some View {
        let selectedMode = stickMode(side: side)
        let inherited = isStickModeInherited(side: side)
        let editingLayer = selectedLayerId != nil

        return Menu {
            if editingLayer {
                Button {
                    clearStickModeOverride(side: side)
                } label: {
                    if inherited {
                        Label("Inherit from Base", systemImage: "checkmark")
                    } else {
                        Text("Inherit from Base")
                    }
                }
                Divider()
            }
            ForEach(StickMode.visibleModes, id: \.self) { mode in
                Button {
                    setStickMode(mode, side: side)
                } label: {
                    // Only show a checkmark next to the explicitly-selected mode. If the layer
                    // is inheriting, the checkmark sits next to "Inherit from Base" instead, so
                    // the user can distinguish "explicitly set to Mouse" from "inheriting Mouse."
                    if mode == selectedMode && !inherited {
                        Label {
                            Text(LocalizedStringKey(mode.displayName))
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(LocalizedStringKey(mode.displayName))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(LocalizedStringKey(selectedMode.displayName))
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .italic(inherited)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Set joystick mode")
    }

    private func stickPresetMenu(side: JoystickSide) -> some View {
        let selectedPreset = profileManager.stickDirectionPreset(side: side)

        return Menu {
            ForEach(StickDirectionPreset.allCases) { preset in
                Button {
                    profileManager.setStickDirectionPreset(preset, side: side)
                } label: {
                    if preset == selectedPreset {
                        Label {
                            Text(LocalizedStringKey(preset.displayName))
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(LocalizedStringKey(preset.displayName))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                    .font(.system(size: 8, weight: .bold))
                Text(LocalizedStringKey(selectedPreset?.shortLabel ?? "Keys"))
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Set custom direction keys")
    }

    private func directionCluster(
        title: String,
        up: ControllerButton?,
        left: ControllerButton?,
        center: DirectionClusterCenter,
        right: ControllerButton?,
        down: ControllerButton?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            directionClusterGrid(up: up, left: left, center: center, right: right, down: down)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func directionClusterGrid(
        up: ControllerButton?,
        left: ControllerButton?,
        center: DirectionClusterCenter,
        right: ControllerButton?,
        down: ControllerButton?
    ) -> some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 6) {
            GridRow {
                compactClusterSpacer()
                compactDirectionCell(up)
                compactClusterSpacer()
            }

            GridRow {
                compactDirectionCell(left)
                compactCenterCell(center)
                compactDirectionCell(right)
            }

            GridRow {
                compactClusterSpacer()
                compactDirectionCell(down)
                compactClusterSpacer()
            }
        }
        .frame(width: 212)
    }

    @ViewBuilder
    private func compactDirectionCell(_ button: ControllerButton?) -> some View {
        if let button {
            compactActionTile(for: button)
        } else {
            compactClusterSpacer()
        }
    }

    @ViewBuilder
    private func compactCenterCell(_ center: DirectionClusterCenter) -> some View {
        switch center {
        case .button(let button):
            compactActionTile(for: button)
        case .label(let label):
            Text(label)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 68, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .accessibilityHidden(true)
        case .dpadPreset:
            dpadPresetMenu
        }
    }

    private var dpadPresetMenu: some View {
        let preset = profileManager.activeProfile?.dpadPreset ?? .custom

        return Menu {
            Button("Arrow Keys") {
                profileManager.setDPadPreset(.arrows)
            }
            Button("WASD") {
                profileManager.setDPadPreset(.wasd)
            }
        } label: {
            VStack(spacing: 3) {
                Text(preset.shortLabel)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.75)
            }
            .foregroundStyle(.secondary)
            .frame(width: 68, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Set D-pad primary actions")
    }

    private func compactClusterSpacer() -> some View {
        Color.clear.frame(width: 68, height: 50)
    }

    private func compactActionTile(for button: ControllerButton) -> some View {
        let layerActivator = layerForButton(button)
        let showsLayerActivator = layerActivator != nil && !isEditingDifferentLayer(button)
        let currentMapping = mapping(for: button)
        let isUnmapped = !showsLayerActivator && currentMapping == nil
        let tileActive = selectedButton == button || isPressed(button)
        var badges = compactBadges(for: currentMapping)
        if let layer = layerActivator, showsLayerActivator {
            badges.insert(CompactActionBadge(label: "L", color: layerColor(layer)), at: 0)
        }

        return HoverableGlassContainer(
            isActive: tileActive,
            isMuted: isUnmapped || isBaseFallthrough(for: button)
        ) {
            VStack(spacing: 4) {
                compactTileHeader(for: button, badges: badges)
                .frame(maxWidth: .infinity)

                Text(compactPrimaryText(mapping: currentMapping, layer: layerActivator, showsLayer: showsLayerActivator))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(tileActive ? .white.opacity(0.92) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .frame(width: 68, height: 50)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange, lineWidth: 3)
                .opacity(swapFirstButton == button ? 1 : 0)
        )
        .opacity(isBaseFallthrough(for: button) ? 0.4 : 1.0)
        .contentShape(Rectangle())
        .controllerAnchor(button, role: .label)
        .opacity(isLayerActivatorInLayerContext(button) ? 0.4 : 1.0)
        .allowsHitTesting(!isLayerActivatorInLayerContext(button))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(button.displayName(forDualSense: isPlayStation, forNintendo: isNintendo))
        .accessibilityHint("Double-tap to configure")
        .accessibilityAddTraits(.isButton)
        .help(compactHelpText(for: button, mapping: currentMapping, layer: layerActivator, showsLayer: showsLayerActivator))
        .onTapGesture { onButtonTap(button) }
        .contextMenu {
            Button {
                onButtonTap(button)
            } label: {
                Label("Edit Mapping", systemImage: "pencil")
            }
            if mapping(for: button) != nil {
                Button {
                    if let layer = selectedLayer {
                        profileManager.removeLayerMapping(for: button, from: layer)
                    } else {
                        profileManager.removeMapping(for: button)
                    }
                } label: {
                    Label("Clear Mapping", systemImage: "xmark.circle")
                }
            }
        }
        .onHover { hovering in
            handleButtonHover(button, hovering)
        }
        .swappable(button, onSwap: performSwap)
    }

    @ViewBuilder
    private func compactTileHeader(for button: ControllerButton, badges: [CompactActionBadge]) -> some View {
        let icon = ButtonIconView(
            button: button,
            isPressed: isPressed(button),
            isDualSense: isPlayStation,
            isNintendo: isNintendo
        )
        .scaleEffect(0.72)
        .frame(width: 22, height: 22)

        if badges.isEmpty {
            HStack {
                Spacer(minLength: 0)
                icon
                Spacer(minLength: 0)
            }
            .frame(height: 22)
        } else if badges.count <= 2 {
            HStack(spacing: 3) {
                Spacer(minLength: 0)
                icon
                HStack(spacing: 2) {
                    ForEach(badges) { badge in
                        compactBadge(label: badge.label, color: badge.color)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 22)
        } else {
            HStack(spacing: 3) {
                icon
                Spacer(minLength: 0)
                compactBadgeTray(badges)
            }
            .frame(height: 22)
        }
    }

    private func compactBadgeTray(_ badges: [CompactActionBadge]) -> some View {
        let displayBadges: [CompactActionBadge]
        if badges.count > 4 {
            displayBadges = Array(badges.prefix(3)) + [CompactActionBadge(label: "+", color: .secondary)]
        } else {
            displayBadges = badges
        }
        let rows = stride(from: 0, to: displayBadges.count, by: 2).map {
            Array(displayBadges[$0..<min($0 + 2, displayBadges.count)])
        }

        return VStack(alignment: .trailing, spacing: 2) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 2) {
                    ForEach(rows[rowIndex]) { badge in
                        compactBadge(label: badge.label, color: badge.color)
                    }
                }
            }
        }
        .frame(width: 30, height: 22, alignment: .trailing)
    }

    private func compactBadge(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 6.5, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(width: 14, height: 9)
            .background(color)
            .cornerRadius(3)
    }

    private func compactBadges(for mapping: KeyMapping?) -> [CompactActionBadge] {
        guard let mapping else { return [] }
        var badges: [CompactActionBadge] = []

        if mapping.systemCommand != nil {
            badges.append(CompactActionBadge(label: "SYS", color: .green))
        } else if mapping.macroId != nil {
            badges.append(CompactActionBadge(label: "▶", color: .purple))
        } else if mapping.isHoldModifier {
            badges.append(CompactActionBadge(label: "▼", color: .purple))
        }
        if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
            badges.append(CompactActionBadge(label: "⏱", color: .orange))
        }
        if let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty {
            badges.append(CompactActionBadge(label: "2×", color: .cyan))
        }
        if let repeatMapping = mapping.repeatMapping, repeatMapping.enabled {
            badges.append(CompactActionBadge(label: "↻", color: .green))
        }

        return badges
    }

    private func compactPrimaryText(mapping: KeyMapping?, layer: Layer?, showsLayer: Bool) -> String {
        if let layer, showsLayer {
            return layer.name
        }

        guard let mapping else {
            return "Map"
        }

        if let hint = mapping.hint, !hint.isEmpty {
            return hint
        }

        if let systemCommand = mapping.systemCommand {
            return systemCommand.displayName
        }

        if let macroId = mapping.macroId,
           let profile = profileManager.activeProfile,
           let macro = profile.macros.first(where: { $0.id == macroId }) {
            return macro.name
        }

        if !mapping.isEmpty {
            return mapping.displayString
        }

        return "No tap"
    }

    private func compactHelpText(
        for button: ControllerButton,
        mapping: KeyMapping?,
        layer: Layer?,
        showsLayer: Bool
    ) -> String {
        let title = button.displayName(forDualSense: isPlayStation, forNintendo: isNintendo)
        if let layer, showsLayer {
            return "\(title)\nLayer Activator: \(layer.name)"
        }
        guard let mapping else {
            return "\(title)\nUnmapped"
        }
        let details = mapping.compactDescription.isEmpty ? "No tap action" : mapping.compactDescription
        return "\(title)\n\(details)"
    }

    @ViewBuilder
    private func referenceRow(for button: ControllerButton) -> some View {
        let layerActivator = layerForButton(button)
        let showsLayerActivator = layerActivator != nil && !isEditingDifferentLayer(button)
        let currentMapping = mapping(for: button)
        let isUnmapped = !showsLayerActivator && currentMapping == nil

        HStack(spacing: 12) {
            // Button Indicator (adapts to Xbox or PlayStation styling)
            // Fixed width container ensures mapping labels align across different button sizes
            ZStack(alignment: .topTrailing) {
                ButtonIconView(button: button, isPressed: isPressed(button), isDualSense: isPlayStation, isNintendo: isNintendo)

                // Layer activator badge — hidden when viewing a different layer,
                // since other layers' activators are inert in that context.
                if let layer = layerActivator, showsLayerActivator {
                    Text("L")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 12, height: 12)
                        .background(Circle().fill(layerColor(layer)))
                        .offset(x: 4, y: -4)
                        .help("Layer Activator: \(layer.name)")
                }
            }
            .frame(width: 50)  // Fixed width for consistent label alignment

            // Shortcut Labels Container
            HoverableGlassContainer(
                isActive: selectedButton == button,
                isMuted: isUnmapped || isBaseFallthrough(for: button)
            ) {
                HStack {
                    if let layer = layerActivator, showsLayerActivator {
                        // This button is a layer activator (only show when on base or its own layer)
                        HStack(spacing: 6) {
                            Text("L")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(layerColor(layer))
                                .cornerRadius(3)
                            Text(layer.name)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                    } else if let mapping = currentMapping {
                        MappingLabelView(
                            mapping: mapping,
                            font: .system(size: 15, weight: .semibold, design: .rounded)
                        )
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Add mapping")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.34))
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .overlay(
                // Swap mode selection indicator
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange, lineWidth: 3)
                    .opacity(swapFirstButton == button ? 1 : 0)
            )
            .opacity(isBaseFallthrough(for: button) ? 0.4 : 1.0)  // Dim fallthrough mappings
            // Anchor only the glass container so connectors terminate at the box edge,
            // independent of which side of the controller the row sits on. Anchoring
            // the parent HStack would have right-column rows resolve to the icon edge.
            .controllerAnchor(button, role: .label)
        }
        .contentShape(Rectangle())
        .opacity(isLayerActivatorInLayerContext(button) ? 0.4 : 1.0)  // Dim all layer activators when viewing any layer
        .allowsHitTesting(!isLayerActivatorInLayerContext(button))  // Disable clicks on layer activators when in layer context
        .accessibilityElement(children: .combine)
        .accessibilityLabel(button.displayName(forDualSense: isPlayStation, forNintendo: isNintendo))
        .accessibilityHint("Double-tap to configure")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { onButtonTap(button) }
        .contextMenu {
            Button {
                onButtonTap(button)
            } label: {
                Label("Edit Mapping", systemImage: "pencil")
            }
            if mapping(for: button) != nil {
                Button {
                    if let layer = selectedLayer {
                        profileManager.removeLayerMapping(for: button, from: layer)
                    } else {
                        profileManager.removeMapping(for: button)
                    }
                } label: {
                    Label("Clear Mapping", systemImage: "xmark.circle")
                }
            }
        }
        .onHover { hovering in
            handleButtonHover(button, hovering)
        }
        .swappable(button, onSwap: performSwap)
    }

    // MARK: - Helpers

    private func isPressed(_ button: ControllerButton) -> Bool {
        controllerService.activeButtons.contains(button)
    }

    private func mapping(for button: ControllerButton) -> KeyMapping? {
        guard let profile = profileManager.activeProfile else { return nil }

        // If viewing a layer, check layer mapping first
        if selectedLayerId != nil {
            // The current layer's own activator button can't be remapped
            if isActivatorForSelectedLayer(button) {
                return nil
            }
            // Check if this button has a layer-specific mapping
            if let layer = selectedLayer,
               let layerMapping = layer.buttonMappings[button], !layerMapping.isEmpty {
                return layerMapping
            }
            // Fall through to base layer
        }

        // Check base layer
        guard let mapping = profile.buttonMappings[button] else { return nil }

        // If the mapping is effectively empty (no primary, no long hold, no double tap), return nil
        // so the UI renders it as "Unmapped"
        if mapping.isEmpty &&
           (mapping.longHoldMapping?.isEmpty ?? true) &&
           (mapping.doubleTapMapping?.isEmpty ?? true) {
            return nil
        }

        return mapping
    }

    /// Returns true if the mapping shown is from the base layer (fallthrough)
    private func isBaseFallthrough(for button: ControllerButton) -> Bool {
        guard let layer = selectedLayer,
              let profile = profileManager.activeProfile else { return false }

        // Not a fallthrough if button is the layer's activator
        if layer.activatorButton == button { return false }

        // It's a fallthrough if the layer doesn't have a mapping for this button
        let layerMapping = layer.buttonMappings[button]
        let hasLayerMapping = layerMapping != nil && !layerMapping!.isEmpty
        let hasBaseMapping = profile.buttonMappings[button] != nil

        return !hasLayerMapping && hasBaseMapping
    }
}

// MARK: - Controller Analog Overlay

/// Extracted overlay view that isolates high-frequency analog display updates (15Hz)
/// from the rest of the ControllerVisualView hierarchy. By snapshotting display values
/// into local @State via .onReceive, only this sub-view redraws when joystick/trigger
/// values change, preventing cascading redraws of the mapping reference rows.
struct ControllerAnalogOverlay: View {
    let controllerService: ControllerService
    let isPlayStation: Bool
    let isNintendo: Bool
    let isXboxElite: Bool
    /// Whole-pad shows one big click target with a single anchor. Quadrants
    /// shows the dashed divider cross plus four per-quadrant tap zones, each
    /// anchoring its `.touchpadRegion*Click` and `.touchpadRegion*Touch`
    /// buttons so connectors land at the correct quarter of the pad.
    var touchpadInputMode: TouchpadInputMode = .wholePad
    var onButtonTap: (ControllerButton) -> Void
    var onButtonHover: ((ControllerButton, Bool) -> Void)? = nil
    var onSwapRequest: ((ControllerButton, ControllerButton) -> Void)? = nil

    // Snapshotted analog display values (updated via .onReceive at 15Hz)
    @State private var leftStick: CGPoint = .zero
    @State private var rightStick: CGPoint = .zero
    @State private var leftTrigger: Float = 0
    @State private var rightTrigger: Float = 0
    @State private var isTouchpadTouching: Bool = false
    @State private var touchpadPosition: CGPoint = .zero
    @State private var isTouchpadSecondaryTouching: Bool = false
    @State private var touchpadSecondaryPosition: CGPoint = .zero
    @State private var activeButtons: Set<ControllerButton> = []
    /// Local hover tracking — used by the touchpad quadrant zones to highlight
    /// the targeted region. The parent owns the canonical hover state for
    /// connector drawing; this is just for the per-zone tint.
    @State private var hoveredQuadrant: ControllerButton?
    @State private var isConnected: Bool = false
    @State private var batteryLevel: Float = -1
    @State private var batteryState: GCDeviceBattery.State = .unknown

    var body: some View {
        Group {
            if isPlayStation {
                dualSenseOverlay
            } else if isNintendo {
                nintendoOverlay
            } else {
                xboxOverlay
            }
        }
        .onReceive(controllerService.displayLeftStickSubject) { leftStick = $0 }
        .onReceive(controllerService.displayRightStickSubject) { rightStick = $0 }
        .onReceive(controllerService.displayLeftTriggerSubject) { leftTrigger = $0 }
        .onReceive(controllerService.displayRightTriggerSubject) { rightTrigger = $0 }
        .onReceive(controllerService.displayIsTouchpadTouchingSubject) { isTouchpadTouching = $0 }
        .onReceive(controllerService.displayTouchpadPositionSubject) { touchpadPosition = $0 }
        .onReceive(controllerService.displayIsTouchpadSecondaryTouchingSubject) { isTouchpadSecondaryTouching = $0 }
        .onReceive(controllerService.displayTouchpadSecondaryPositionSubject) { touchpadSecondaryPosition = $0 }
        .onReceive(controllerService.$activeButtons) { activeButtons = $0 }
        .onReceive(controllerService.$isConnected) { isConnected = $0 }
        .onReceive(controllerService.$batteryLevel) { batteryLevel = $0 }
        .onReceive(controllerService.$batteryState) { batteryState = $0 }
    }

    // MARK: - Xbox Controller Overlay

    private var xboxOverlay: some View {
        VStack(spacing: 15) {
            HStack(spacing: 140) {
                miniTrigger(.leftTrigger, label: "LT", value: leftTrigger)
                miniTrigger(.rightTrigger, label: "RT", value: rightTrigger)
            }

            HStack(spacing: 120) {
                miniBumper(.leftBumper, label: "LB")
                miniBumper(.rightBumper, label: "RB")
            }
            .offset(y: -5)

            HStack(spacing: 40) {
                miniStick(.leftThumbstick, pos: leftStick)

                VStack(spacing: 6) {
                    miniCircle(.xbox, size: 22)

                    if isConnected {
                        BatteryView(level: batteryLevel, state: batteryState)
                    }

                    HStack(spacing: 12) {
                        miniCircle(.view, size: 14)
                        miniCircle(.menu, size: 14)
                    }
                    if !isXboxElite {
                        miniCircle(.share, size: 10)
                    }
                }

                miniFaceButtons()
            }

            HStack(spacing: 80) {
                miniDPad()
                miniStick(.rightThumbstick, pos: rightStick)
            }
        }
    }

    // MARK: - Nintendo Pro Controller Overlay

    private var nintendoOverlay: some View {
        VStack(spacing: 15) {
            HStack(spacing: 140) {
                miniTrigger(.leftTrigger, label: "ZL", value: leftTrigger)
                miniTrigger(.rightTrigger, label: "ZR", value: rightTrigger)
            }

            HStack(spacing: 120) {
                miniBumper(.leftBumper, label: "L")
                miniBumper(.rightBumper, label: "R")
            }
            .offset(y: -5)

            HStack(spacing: 40) {
                miniStick(.leftThumbstick, pos: leftStick)

                VStack(spacing: 6) {
                    if isConnected {
                        BatteryView(level: batteryLevel, state: batteryState)
                    }

                    // − and + buttons (slightly wider)
                    HStack(spacing: 20) {
                        miniCircle(.view, size: 16)   // − button
                        miniCircle(.menu, size: 16)   // + button
                    }

                    // Capture and Home — side by side, mirrored (slightly narrower)
                    HStack(spacing: 20) {
                        miniSquare(.share, size: 10)   // Capture (left)
                        miniCircle(.xbox, size: 10)    // Home (right)
                    }
                }

                miniFaceButtons()
            }

            HStack(spacing: 80) {
                miniDPad()
                miniStick(.rightThumbstick, pos: rightStick)
            }
        }
    }

    // MARK: - DualSense Controller Overlay

    private var dualSenseOverlay: some View {
        VStack(spacing: 4) {
            // Row 1: Triggers (top)
            HStack(spacing: 150) {
                miniTrigger(.leftTrigger, label: "L2", value: leftTrigger)
                miniTrigger(.rightTrigger, label: "R2", value: rightTrigger)
            }

            // Row 2: Bumpers
            HStack(spacing: 130) {
                miniBumper(.leftBumper, label: "L1")
                miniBumper(.rightBumper, label: "R1")
            }

            // Row 3: Battery indicator (above touchpad)
            if isConnected {
                BatteryView(level: batteryLevel, state: batteryState)
                    .frame(width: 40)
            }

            // Row 4: D-pad + Touchpad section + Face buttons (straddling touchpad)
            HStack(spacing: 8) {
                miniDPad()
                    .frame(width: 40)
                    .offset(y: 15)

                // Center: Create + Touchpad + Options
                HStack(alignment: .top, spacing: 6) {
                    miniCircle(.view, size: 12)  // Create button
                    miniTouchpad()
                    miniCircle(.menu, size: 12)  // Options button
                }

                miniFaceButtons()
                    .frame(width: 40)
                    .offset(y: 15)
            }

            // Row 5: Sticks with PS/Mic in center (bottom)
            HStack(spacing: 20) {
                miniStick(.leftThumbstick, pos: leftStick)
                VStack(spacing: 3) {
                    miniCircle(.xbox, size: 16)  // PS button
                    miniBumperWithIcon(.micMute, icon: "mic.slash", width: 16)  // Mic mute
                }
                miniStick(.rightThumbstick, pos: rightStick)
            }
        }
    }

    // MARK: - Mini Touchpad

    private func miniTouchpad() -> some View {
        let color = isPressed(.touchpadButton) ? Color.accentColor : Color(white: 0.25)
        let touchpadWidth: CGFloat = 100
        let touchpadHeight: CGFloat = 50
        let inQuadrantsMode = touchpadInputMode == .quadrants

        return ZStack {
            // Base touchpad shape
            RoundedRectangle(cornerRadius: 10)
                .fill(jewelGradient(color, pressed: isPressed(.touchpadButton)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5)
                )

            // Quadrant divider cross is only meaningful in quadrants mode.
            // In whole-pad mode the entire pad is one binding target and the
            // dashed cross would mislead users.
            if inQuadrantsMode {
                quadrantDividers(width: touchpadWidth, height: touchpadHeight)
            }

            // Live activation overlay: which quadrant is currently being
            // touched, and is it being clicked? Drawn under the touch dot so
            // the dot stays visible. Touch = soft accent wash; click = brighter
            // accent fill — the click distinction makes a physical press
            // visually distinct from a finger that's just resting on the pad.
            if isTouchpadTouching {
                quadrantHighlight(
                    region: TouchpadRegion.from(position: touchpadPosition),
                    width: touchpadWidth,
                    height: touchpadHeight,
                    isClicked: isPressed(.touchpadButton)
                )
            }

            // Primary touch point
            if isTouchpadTouching {
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .shadow(color: .white.opacity(0.5), radius: 3)
                    .offset(
                        x: touchpadPosition.x * (touchpadWidth / 2 - 5),
                        y: -touchpadPosition.y * (touchpadHeight / 2 - 5)
                    )
            }

            // Secondary touch point (two-finger)
            if isTouchpadSecondaryTouching {
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .shadow(color: .white.opacity(0.4), radius: 2)
                    .offset(
                        x: touchpadSecondaryPosition.x * (touchpadWidth / 2 - 4),
                        y: -touchpadSecondaryPosition.y * (touchpadHeight / 2 - 4)
                    )
            }

            quadrantTapZones(width: touchpadWidth, height: touchpadHeight)
                .allowsHitTesting(inQuadrantsMode)
        }
        .frame(width: touchpadWidth, height: touchpadHeight)
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        .onTapGesture { onButtonTap(.touchpadButton) }
        // All touchpad connector anchors. Whole-pad and quadrant variants
        // both currently resolve to the entire pad rect; ConnectorLayer can
        // refine quadrant endpoints visually if needed. Stacking these as
        // sibling modifiers on the working chain (rather than nested child
        // views) is the only placement that reliably propagates region
        // anchors through SwiftUI's preference machinery here.
        .controllerAnchor(
            [.touchpadButton, .touchpadTap, .touchpadTwoFingerButton, .touchpadTwoFingerTap,
             .touchpadRegionTopLeftClick, .touchpadRegionTopRightClick,
             .touchpadRegionBottomLeftClick, .touchpadRegionBottomRightClick,
             .touchpadRegionTopLeftTouch, .touchpadRegionTopRightTouch,
             .touchpadRegionBottomLeftTouch, .touchpadRegionBottomRightTouch],
            role: .controller
        )
        .onHover { hovering in onButtonHover?(.touchpadButton, hovering) }
        .swappable(.touchpadButton, onSwap: onSwapRequest)
    }

    /// Live highlight on the active quadrant. `isClicked` distinguishes a
    /// physical click (brighter, accent-saturated fill) from a passive touch
    /// (soft, low-opacity wash) so the same overlay communicates two
    /// different input states. Clipped to a rounded rectangle slightly inset
    /// from the touchpad's corner radius so it doesn't bleed past the bezel.
    private func quadrantHighlight(
        region: TouchpadRegion,
        width: CGFloat,
        height: CGFloat,
        isClicked: Bool
    ) -> some View {
        let halfW = width / 2
        let halfH = height / 2
        let originX: CGFloat = (region == .topLeft || region == .bottomLeft) ? 0 : halfW
        // SwiftUI Y grows downward inside this view; touchpad "top" maps to y=0.
        let originY: CGFloat = (region == .topLeft || region == .topRight) ? 0 : halfH
        let touchOpacity: Double = 0.18
        let clickOpacity: Double = 0.42
        return Rectangle()
            .fill(Color.accentColor.opacity(isClicked ? clickOpacity : touchOpacity))
            .frame(width: halfW, height: halfH)
            .position(x: originX + halfW / 2, y: originY + halfH / 2)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(width: width, height: height)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.08), value: isClicked)
    }

    /// Subtle dashed cross dividing the touchpad into four quadrants. Visual
    /// only — no hit testing.
    private func quadrantDividers(width: CGFloat, height: CGFloat) -> some View {
        return ZStack {
            // Vertical divider at horizontal center
            Path { path in
                path.move(to: CGPoint(x: width / 2, y: 4))
                path.addLine(to: CGPoint(x: width / 2, y: height - 4))
            }
            .stroke(Color.white.opacity(0.18),
                    style: StrokeStyle(lineWidth: 0.6, lineCap: .round, dash: [2, 2]))
            // Horizontal divider at vertical center
            Path { path in
                path.move(to: CGPoint(x: 4, y: height / 2))
                path.addLine(to: CGPoint(x: width - 4, y: height / 2))
            }
            .stroke(Color.white.opacity(0.18),
                    style: StrokeStyle(lineWidth: 0.6, lineCap: .round, dash: [2, 2]))
        }
        .allowsHitTesting(false)
    }

    /// 2×2 grid of transparent tap zones for hover/tap/drag handling.
    /// Connector anchors live in `quadrantAnchorOverlay`, separately attached
    /// to miniTouchpad's outer ZStack so they propagate to the connector
    /// preference reliably.
    private func quadrantTapZones(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                quadrantTapTarget(region: .topLeft, width: width / 2, height: height / 2)
                quadrantTapTarget(region: .topRight, width: width / 2, height: height / 2)
            }
            HStack(spacing: 0) {
                quadrantTapTarget(region: .bottomLeft, width: width / 2, height: height / 2)
                quadrantTapTarget(region: .bottomRight, width: width / 2, height: height / 2)
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func quadrantTapTarget(region: TouchpadRegion, width: CGFloat, height: CGFloat) -> some View {
        let clickButton = ControllerButton.from(region: region, trigger: .click) ?? .touchpadButton
        let touchButton = ControllerButton.from(region: region, trigger: .touch) ?? .touchpadTap
        let isHovered = hoveredQuadrant == clickButton || hoveredQuadrant == touchButton
        Rectangle()
            .fill(Color.white.opacity(isHovered ? 0.12 : 0.001))
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { onButtonTap(clickButton) }
            .onHover { hovering in
                if hovering {
                    hoveredQuadrant = clickButton
                } else if hoveredQuadrant == clickButton || hoveredQuadrant == touchButton {
                    hoveredQuadrant = nil
                }
                onButtonHover?(clickButton, hovering)
                _ = touchButton  // kept in scope so Swift doesn't elide the binding
            }
            .swappable(clickButton, onSwap: onSwapRequest)
    }

    // MARK: - Mini Controller Helpers (Jewel/Glass Style)

    private func jewelGradient(_ color: Color, pressed: Bool) -> LinearGradient {
        LinearGradient(
            colors: [
                pressed ? color.opacity(0.8) : color,
                pressed ? color.opacity(0.6) : color.opacity(0.8)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glassOverlay: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.5), location: 0),
                .init(color: .white.opacity(0.1), location: 0.45),
                .init(color: .clear, location: 0.5),
                .init(color: .black.opacity(0.1), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func isPressed(_ button: ControllerButton) -> Bool {
        activeButtons.contains(button)
    }

    private func miniTrigger(_ button: ControllerButton, label: String, value: Float) -> some View {
        let color = Color(white: 0.2) // Dark grey plastic
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

        return ZStack(alignment: .bottom) {
            // Background
            shape
                .fill(jewelGradient(color, pressed: false))
                .overlay(glassOverlay.clipShape(shape))
                .frame(width: 34, height: 18)

            // Fill based on pressure
            if value > 0 {
                shape
                    .fill(jewelGradient(Color.accentColor, pressed: isPressed(button)))
                    .frame(width: 34, height: 18 * CGFloat(value))
                    .overlay(glassOverlay.clipShape(shape))
            }

            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .shadow(radius: 1)
        }
        .clipShape(shape)
        .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 2)
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor(button, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
    }

    private func miniBumper(_ button: ControllerButton, label: String) -> some View {
        let color = isPressed(button) ? Color.accentColor : Color(white: 0.25)
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)

        return shape
            .fill(jewelGradient(color, pressed: isPressed(button)))
            .overlay(glassOverlay.clipShape(shape))
            .frame(width: 38, height: 9)
            .overlay(
                Text(label)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 1)
            )
            .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 2)
            .onTapGesture { onButtonTap(button) }
            .controllerAnchor(button, role: .controller)
            .onHover { hovering in onButtonHover?(button, hovering) }
            .swappable(button, onSwap: onSwapRequest)
    }

    /// Bumper-shaped button with an icon inside (used for mic mute on DualSense)
    private func miniBumperWithIcon(_ button: ControllerButton, icon: String, width: CGFloat = 38) -> some View {
        let color = isPressed(button) ? Color.accentColor : Color(white: 0.25)
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)

        return shape
            .fill(jewelGradient(color, pressed: isPressed(button)))
            .overlay(glassOverlay.clipShape(shape))
            .frame(width: width, height: 9)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 1)
            )
            .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 2)
            .onTapGesture { onButtonTap(button) }
            .controllerAnchor(button, role: .controller)
            .onHover { hovering in onButtonHover?(button, hovering) }
            .swappable(button, onSwap: onSwapRequest)
    }

    private func miniStick(_ button: ControllerButton, pos: CGPoint) -> some View {
        let directionButtons = button == .leftThumbstick
            ? ControllerButton.joystickDirectionButtons(side: .left)
            : ControllerButton.joystickDirectionButtons(side: .right)
        let isStickActive = isPressed(button) || directionButtons.contains(where: isPressed)

        return ZStack {
            // Base well
            Circle()
                .fill(
                    LinearGradient(colors: [Color(white: 0.1), Color(white: 0.3)], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 30, height: 30)
                .shadow(color: .white.opacity(0.1), radius: 0, x: 0, y: 1) // Highlight at bottom lip
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))

            // Stick Cap
            let color = isStickActive ? Color.accentColor : Color(white: 0.3)
            Circle()
                .fill(jewelGradient(color, pressed: isStickActive))
                .overlay(glassOverlay.clipShape(Circle()))
                .frame(width: 20, height: 20)
                .offset(x: pos.x * 5, y: -pos.y * 5)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
        }
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor([button] + directionButtons, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
    }

    private func miniCircle(_ button: ControllerButton, size: CGFloat) -> some View {
        // Use silver/chrome for Xbox/PS button, grey for others
        let baseColor: Color = {
            if button == .xbox {
                return Color(white: 0.85) // Silver/Chrome for both Xbox and PlayStation
            }
            return Color(white: 0.3)
        }()
        let color = isPressed(button) ? Color.accentColor : baseColor

        return ZStack {
            Circle()
                .fill(jewelGradient(color, pressed: isPressed(button)))
                .overlay(glassOverlay.clipShape(Circle()))

            // Add Xbox or PlayStation logo for the center button
            if button == .xbox {
                Image(systemName: isPlayStation ? "playstation.logo" : (isNintendo ? "house" : "xbox.logo"))
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundColor(isPressed(button) ? .white : Color(white: 0.3))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 1)
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor(button, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
    }

    private func miniSquare(_ button: ControllerButton, size: CGFloat) -> some View {
        let color = isPressed(button) ? Color.accentColor : Color(white: 0.3)
        return RoundedRectangle(cornerRadius: size * 0.2)
            .fill(jewelGradient(color, pressed: isPressed(button)))
            .overlay(glassOverlay.clipShape(RoundedRectangle(cornerRadius: size * 0.2)))
            .frame(width: size, height: size)
            .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 1)
            .onTapGesture { onButtonTap(button) }
            .controllerAnchor(button, role: .controller)
            .onHover { hovering in onButtonHover?(button, hovering) }
            .swappable(button, onSwap: onSwapRequest)
    }

    private func miniFaceButton(_ button: ControllerButton, color: Color) -> some View {
        // Use the vibrant colors for A/B/X/Y even when not pressed, just like the real controller
        let displayColor = isPressed(button) ? color.opacity(0.8) : color

        return Circle()
            .fill(jewelGradient(displayColor, pressed: isPressed(button)))
            .overlay(glassOverlay.clipShape(Circle()))
            .frame(width: 12, height: 12)
            .shadow(color: displayColor.opacity(0.4), radius: 2)
            .onTapGesture { onButtonTap(button) }
            .controllerAnchor(button, role: .controller)
            .onHover { hovering in onButtonHover?(button, hovering) }
            .swappable(button, onSwap: onSwapRequest)
    }

    /// PlayStation-style face button: dark background with colored symbol
    private func miniPSFaceButton(_ button: ControllerButton, symbolColor: Color) -> some View {
        let bgColor = Color(white: 0.12)
        let symbol: String = {
            switch button {
            case .a: return "\u{2715}" // Cross
            case .b: return "\u{25CB}" // Circle
            case .x: return "\u{25A1}" // Square
            case .y: return "\u{25B3}" // Triangle
            default: return ""
            }
        }()

        return ZStack {
            Circle()
                .fill(jewelGradient(bgColor, pressed: isPressed(button)))
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.15), location: 0),
                            .init(color: .clear, location: 0.5),
                            .init(color: .black.opacity(0.2), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(Circle())
                )

            Text(symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(isPressed(button) ? symbolColor.opacity(0.7) : symbolColor)
        }
        .frame(width: 12, height: 12)
        .shadow(color: symbolColor.opacity(0.3), radius: 2)
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor(button, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
    }

    private func miniFaceButtons() -> some View {
        ZStack {
            if isPlayStation {
                // PlayStation style: dark background with colored symbols
                miniPSFaceButton(.y, symbolColor: ButtonColors.psTriangle).offset(y: -12)
                miniPSFaceButton(.a, symbolColor: ButtonColors.psCross).offset(y: 12)
                miniPSFaceButton(.x, symbolColor: ButtonColors.psSquare).offset(x: -12)
                miniPSFaceButton(.b, symbolColor: ButtonColors.psCircle).offset(x: 12)
            } else {
                // Xbox layout and colors (colored background)
                miniFaceButton(.y, color: ButtonColors.xboxY).offset(y: -12)
                miniFaceButton(.a, color: ButtonColors.xboxA).offset(y: 12)
                miniFaceButton(.x, color: ButtonColors.xboxX).offset(x: -12)
                miniFaceButton(.b, color: ButtonColors.xboxB).offset(x: 12)
            }
        }
        .frame(width: 40, height: 40)
    }

    private func miniDPad() -> some View {
        let color = Color(white: 0.25)

        return ZStack {
            // Background Cross
            Group {
                RoundedRectangle(cornerRadius: 2).frame(width: 8, height: 24)
                RoundedRectangle(cornerRadius: 2).frame(width: 24, height: 8)
            }
            .foregroundStyle(jewelGradient(color, pressed: false))
            .shadow(radius: 1)

            // Active states (Lighting up)
            if isPressed(.dpadUp) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 8, height: 10).offset(y: -7).blur(radius: 2)
            }
            if isPressed(.dpadDown) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 8, height: 10).offset(y: 7).blur(radius: 2)
            }
            if isPressed(.dpadLeft) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 10, height: 8).offset(x: -7).blur(radius: 2)
            }
            if isPressed(.dpadRight) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 10, height: 8).offset(x: 7).blur(radius: 2)
            }

            // Tap zones — `.offset` is render-only and works fine for hit-testing.
            // Anchors are reported separately by the markers below, since `.offset`
            // does NOT propagate into anchor preference reads from ancestor proxies.
            Group {
                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: 20, height: 20)
                    .offset(y: -10)
                    .onTapGesture { onButtonTap(.dpadUp) }
                    .onHover { hovering in onButtonHover?(.dpadUp, hovering) }
                    .swappable(.dpadUp, onSwap: onSwapRequest)

                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: 20, height: 20)
                    .offset(y: 10)
                    .onTapGesture { onButtonTap(.dpadDown) }
                    .onHover { hovering in onButtonHover?(.dpadDown, hovering) }
                    .swappable(.dpadDown, onSwap: onSwapRequest)

                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: 20, height: 20)
                    .offset(x: -10)
                    .onTapGesture { onButtonTap(.dpadLeft) }
                    .onHover { hovering in onButtonHover?(.dpadLeft, hovering) }
                    .swappable(.dpadLeft, onSwap: onSwapRequest)

                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: 20, height: 20)
                    .offset(x: 10)
                    .onTapGesture { onButtonTap(.dpadRight) }
                    .onHover { hovering in onButtonHover?(.dpadRight, hovering) }
                    .swappable(.dpadRight, onSwap: onSwapRequest)
            }

            // Connector anchor markers. VStack/HStack layout guarantees each
            // marker's reported anchor sits at the corresponding edge of the
            // d-pad cross, so per-direction connector lines emerge correctly.
            VStack(spacing: 0) {
                Color.clear.frame(width: 1, height: 1)
                    .controllerAnchor(.dpadUp, role: .controller)
                Spacer(minLength: 0)
                Color.clear.frame(width: 1, height: 1)
                    .controllerAnchor(.dpadDown, role: .controller)
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: 1, height: 1)
                    .controllerAnchor(.dpadLeft, role: .controller)
                Spacer(minLength: 0)
                Color.clear.frame(width: 1, height: 1)
                    .controllerAnchor(.dpadRight, role: .controller)
            }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Connector Layer

/// Renders semi-transparent Bezier connectors between each controller-side mini button
/// and its corresponding action label. The connector for the hovered button is drawn
/// brighter and slightly thicker; all others remain faint.
///
/// The layer is placed via `.backgroundPreferenceValue` so connector strokes are masked
/// behind the controller body and the label glass containers — visible only in the gap.
struct ConnectorLayer: View {
    let endpoints: [ConnectorEndpoint]
    let proxy: GeometryProxy
    let hoveredButton: ControllerButton?
    let emphasizedButtons: Set<ControllerButton>

    private struct Pair {
        let button: ControllerButton
        let controllerAnchor: Anchor<CGRect>
        let labelAnchor: Anchor<CGRect>
    }

    private var pairs: [Pair] {
        var byButton: [ControllerButton: (controller: Anchor<CGRect>?, label: Anchor<CGRect>?)] = [:]
        for endpoint in endpoints {
            var entry = byButton[endpoint.button] ?? (controller: nil, label: nil)
            switch endpoint.role {
            case .controller: entry.controller = endpoint.anchor
            case .label: entry.label = endpoint.anchor
            }
            byButton[endpoint.button] = entry
        }
        return byButton.compactMap { (button, entry) in
            guard let c = entry.controller, let l = entry.label else { return nil }
            return Pair(button: button, controllerAnchor: c, labelAnchor: l)
        }
    }

    var body: some View {
        ZStack {
            ForEach(pairs, id: \.button) { pair in
                let isHovered = pair.button == hoveredButton
                let isEmphasized = emphasizedButtons.contains(pair.button)
                let rawControllerRect = proxy[pair.controllerAnchor]
                let labelRect = proxy[pair.labelAnchor]
                // For touchpad quadrant buttons, slice the whole-pad anchor
                // rect down to the corresponding quarter so the connector
                // terminates at the quadrant edge, not the pad center.
                let controllerRect = Self.quadrantRect(of: rawControllerRect, for: pair.button)
                let labelCenter = CGPoint(x: labelRect.midX, y: labelRect.midY)
                let controllerCenter = CGPoint(x: controllerRect.midX, y: controllerRect.midY)
                let start = rectEdgePoint(of: controllerRect, towards: labelCenter)
                let end = rectEdgePoint(of: labelRect, towards: controllerCenter)

                ConnectorPath(start: start, end: end)
                    .stroke(
                        isHovered ? Color.accentColor : Color.white.opacity(0.22),
                        style: StrokeStyle(lineWidth: isHovered ? 1.6 : 0.8, lineCap: .round)
                    )
                    .opacity(isHovered ? 0.9 : (isEmphasized ? 0.18 : 0))
            }
        }
        .animation(.easeOut(duration: 0.15), value: hoveredButton)
        .allowsHitTesting(false)
    }

    /// For touchpad quadrant buttons, returns the rect of the corresponding
    /// quarter of the whole-pad anchor rect; for any other button, returns
    /// the rect unchanged. Lets the eight region buttons share a single
    /// whole-pad `controllerAnchor` while still having connectors that land
    /// at each quadrant's center.
    private static func quadrantRect(of padRect: CGRect, for button: ControllerButton) -> CGRect {
        guard let region = button.touchpadRegion else { return padRect }
        let halfW = padRect.width / 2
        let halfH = padRect.height / 2
        let originX = (region == .topLeft || region == .bottomLeft) ? padRect.minX : padRect.midX
        let originY = (region == .topLeft || region == .topRight) ? padRect.minY : padRect.midY
        return CGRect(x: originX, y: originY, width: halfW, height: halfH)
    }

    /// Projects a ray from the rect's center toward `target` and returns the point where
    /// it intersects the rect's boundary. Used to terminate connector lines at the visual
    /// edge of buttons and labels rather than at their geometric centers.
    private func rectEdgePoint(of rect: CGRect, towards target: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - center.x
        let dy = target.y - center.y
        if dx == 0 && dy == 0 { return center }

        let halfW = rect.width / 2
        let halfH = rect.height / 2
        let scaleX = abs(dx) > 0 ? halfW / abs(dx) : .infinity
        let scaleY = abs(dy) > 0 ? halfH / abs(dy) : .infinity
        let scale = min(scaleX, scaleY)

        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }
}

/// A smooth horizontal-tangent Bezier curve between two points.
struct ConnectorPath: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = (start.x + end.x) / 2
        let cp1 = CGPoint(x: midX, y: start.y)
        let cp2 = CGPoint(x: midX, y: end.y)
        path.move(to: start)
        path.addCurve(to: end, control1: cp1, control2: cp2)
        return path
    }
}

// MARK: - Hoverable Glass Container

/// A container that applies GlassCardBackground with hover tracking
struct HoverableGlassContainer<Content: View>: View {
    let isActive: Bool
    let isMuted: Bool
    let content: Content

    @State private var isHovered = false

    init(isActive: Bool, isMuted: Bool = false, @ViewBuilder content: () -> Content) {
        self.isActive = isActive
        self.isMuted = isMuted
        self.content = content()
    }

    var body: some View {
        content
            .contentShape(Rectangle())
            .background(GlassCardBackground(isActive: isActive, isHovered: isHovered, isMuted: isMuted))
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

// MARK: - Controller Body Shapes

struct ControllerBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        path.move(to: CGPoint(x: width * 0.2, y: height * 0.15))
        path.addCurve(to: CGPoint(x: width * 0.8, y: height * 0.15), control1: CGPoint(x: width * 0.35, y: height * 0.05), control2: CGPoint(x: width * 0.65, y: height * 0.05))
        path.addQuadCurve(to: CGPoint(x: width * 0.95, y: height * 0.35), control: CGPoint(x: width * 0.98, y: height * 0.2))
        path.addCurve(to: CGPoint(x: width * 0.75, y: height * 0.9), control1: CGPoint(x: width * 1.0, y: height * 0.6), control2: CGPoint(x: width * 0.9, y: height * 0.85))
        path.addQuadCurve(to: CGPoint(x: width * 0.25, y: height * 0.9), control: CGPoint(x: width * 0.5, y: height * 0.75))
        path.addCurve(to: CGPoint(x: width * 0.05, y: height * 0.35), control1: CGPoint(x: width * 0.1, y: height * 0.85), control2: CGPoint(x: width * 0.0, y: height * 0.6))
        path.addQuadCurve(to: CGPoint(x: width * 0.2, y: height * 0.15), control: CGPoint(x: width * 0.02, y: height * 0.2))
        path.closeSubpath()
        return path
    }
}

/// DualSense controller body shape - distinctive split design with wing-like grips
struct DualSenseBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        // DualSense key features: wing-like handles that flare out, split/V bottom

        // Start at top-left
        path.move(to: CGPoint(x: width * 0.18, y: height * 0.10))

        // Top edge - wide and flat
        path.addQuadCurve(
            to: CGPoint(x: width * 0.82, y: height * 0.10),
            control: CGPoint(x: width * 0.5, y: height * 0.05)
        )

        // Right shoulder - curves outward to the wing
        path.addCurve(
            to: CGPoint(x: width * 0.98, y: height * 0.45),
            control1: CGPoint(x: width * 0.92, y: height * 0.10),
            control2: CGPoint(x: width * 1.0, y: height * 0.28)
        )

        // Right wing/handle - flares out then curves back in dramatically
        path.addCurve(
            to: CGPoint(x: width * 0.62, y: height * 0.95),
            control1: CGPoint(x: width * 0.98, y: height * 0.70),
            control2: CGPoint(x: width * 0.78, y: height * 0.92)
        )

        // Bottom split - smooth convex curve bulging outward
        path.addQuadCurve(
            to: CGPoint(x: width * 0.38, y: height * 0.95),
            control: CGPoint(x: width * 0.5, y: height * 0.98)
        )

        // Left wing/handle - mirror of right
        path.addCurve(
            to: CGPoint(x: width * 0.02, y: height * 0.45),
            control1: CGPoint(x: width * 0.22, y: height * 0.92),
            control2: CGPoint(x: width * 0.02, y: height * 0.70)
        )

        // Left shoulder - curves back to top
        path.addCurve(
            to: CGPoint(x: width * 0.18, y: height * 0.10),
            control1: CGPoint(x: width * 0.0, y: height * 0.28),
            control2: CGPoint(x: width * 0.08, y: height * 0.10)
        )

        path.closeSubpath()
        return path
    }
}

/// Nintendo Switch Pro Controller body shape - wide, rounded rectangular form with smooth grips
struct NintendoProBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        // Pro Controller: wider and more rounded than Xbox, with straighter top edge
        // and smooth cylindrical grips that curve gently outward

        // Start at top-left
        path.move(to: CGPoint(x: width * 0.22, y: height * 0.12))

        // Top edge - wide and gently curved
        path.addQuadCurve(
            to: CGPoint(x: width * 0.78, y: height * 0.12),
            control: CGPoint(x: width * 0.5, y: height * 0.06)
        )

        // Right shoulder - smooth curve into grip
        path.addCurve(
            to: CGPoint(x: width * 0.96, y: height * 0.40),
            control1: CGPoint(x: width * 0.90, y: height * 0.12),
            control2: CGPoint(x: width * 0.97, y: height * 0.25)
        )

        // Right grip - smooth cylindrical shape, less angular than Xbox
        path.addCurve(
            to: CGPoint(x: width * 0.72, y: height * 0.92),
            control1: CGPoint(x: width * 0.97, y: height * 0.62),
            control2: CGPoint(x: width * 0.85, y: height * 0.88)
        )

        // Bottom edge - wide rounded curve connecting grips
        path.addQuadCurve(
            to: CGPoint(x: width * 0.28, y: height * 0.92),
            control: CGPoint(x: width * 0.5, y: height * 0.80)
        )

        // Left grip - mirror of right
        path.addCurve(
            to: CGPoint(x: width * 0.04, y: height * 0.40),
            control1: CGPoint(x: width * 0.15, y: height * 0.88),
            control2: CGPoint(x: width * 0.03, y: height * 0.62)
        )

        // Left shoulder - back to top
        path.addCurve(
            to: CGPoint(x: width * 0.22, y: height * 0.12),
            control1: CGPoint(x: width * 0.03, y: height * 0.25),
            control2: CGPoint(x: width * 0.10, y: height * 0.12)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Shared Components

struct BatteryView: View {
    let level: Float
    let state: GCDeviceBattery.State
    
    // Xbox controllers on macOS often report 0.0 with unknown state when data is unavailable
    private var isUnknown: Bool {
		!ControllerBatteryDisplayPolicy.isKnown(level: level, state: state)
    }

    private var percentage: Int? {
		ControllerBatteryDisplayPolicy.percentage(level: level, state: state)
    }
    
    var body: some View {
        HStack(spacing: 2) {
            if state == .charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
            }
            
            ZStack(alignment: .leading) {
                // Battery outline
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.primary.opacity(0.4), lineWidth: 1)
                    .frame(width: 30, height: 14)
                
                // Empty track background
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 28, height: 12)
                    .padding(.leading, 1)

                // Fill
                if !isUnknown {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(batteryColor)
                            .frame(width: max(2, 28 * CGFloat(level)), height: 12)
                        
						Text("\(percentage ?? 0)%")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0)
                            .frame(width: 28, alignment: .center)
                    }
                    .padding(.leading, 1)
                } else {
                    // Unknown level
                    Text("?")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 14, alignment: .center)
                }
            }
            
            // Battery tip
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.4))
                .frame(width: 2, height: 4)
        }
		.help(percentage.map { "Battery: \($0)%" } ?? "Battery level unavailable (common macOS limitation for Xbox controllers)")
		.accessibilityLabel(percentage.map { "Battery: \($0) percent" } ?? "Battery unavailable")
    }
    
    private var batteryColor: Color {
        if state == .charging { return .green }
        if level > 0.6 { return .green }
        if level > 0.2 { return .orange }
        return .red
    }
}

struct MappingTag: View {
    let mapping: KeyMapping
    
    var body: some View {
        MappingLabelView(
            mapping: mapping,
            font: .system(size: 13, weight: .semibold),
            foregroundColor: .primary
        )
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
    }
}



#Preview {
    ControllerVisualView(selectedButton: .constant(nil), selectedLayerId: nil) { _ in }
        .environmentObject(ControllerService())
        .environmentObject(ProfileManager())
        .frame(width: 800, height: 600)
}
