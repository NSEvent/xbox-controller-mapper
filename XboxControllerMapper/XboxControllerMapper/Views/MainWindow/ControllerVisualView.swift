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
    func swappable(
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

enum DirectionClusterCenter {
    case button(ControllerButton)
    case label(String)
    case dpadPreset
}

private struct CompactActionBadge: Identifiable {
    let label: String
    let color: Color

    var id: String { label }
}

enum ControllerPreviewLayout: String, CaseIterable, Identifiable {
	case active
	case xbox
	case xboxElite
	case dualSense
	case dualSenseEdge
	case dualShock
	case nintendo
	case steam
	case eightBitDoZero2
	case eightBitDoMicro
	case eightBitDoLite2
	case eightBitDoLiteSE
	case appleTVRemote

	var id: String { rawValue }

	var displayName: String {
		switch self {
		case .active: return "Active Controller"
		case .xbox: return "Xbox"
		case .xboxElite: return "Xbox Elite"
		case .dualSense: return "DualSense"
		case .dualSenseEdge: return "DualSense Edge"
		case .dualShock: return "DualShock 4"
		case .nintendo: return "Nintendo"
		case .steam: return "Steam"
		case .eightBitDoZero2: return "8BitDo Zero 2"
		case .eightBitDoMicro: return "8BitDo Micro"
		case .eightBitDoLite2: return "8BitDo Lite 2"
		case .eightBitDoLiteSE: return "8BitDo Lite SE"
		case .appleTVRemote: return "Apple TV Remote"
		}
	}

	var systemImage: String {
		switch self {
		case .active: return "dot.radiowaves.left.and.right"
		case .xbox, .xboxElite: return "xbox.logo"
		case .dualSense, .dualSenseEdge, .dualShock: return "playstation.logo"
		case .nintendo: return "house"
		case .steam: return "gamecontroller"
		case .eightBitDoZero2, .eightBitDoMicro: return "gamecontroller.circle"
		case .eightBitDoLite2, .eightBitDoLiteSE: return "gamecontroller.circle.fill"
		case .appleTVRemote: return "appletvremote.gen3"
		}
	}

	func isPlayStation(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsPlayStation
		case .dualSense, .dualSenseEdge, .dualShock: return true
		default: return false
		}
	}

	func isDualSense(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsDualSense
		case .dualSense, .dualSenseEdge: return true
		default: return false
		}
	}

	func isDualSenseEdge(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsDualSenseEdge
		case .dualSenseEdge: return true
		default: return false
		}
	}

	func isDualShock(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsDualShock
		case .dualShock: return true
		default: return false
		}
	}

	func isXboxElite(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsXboxElite
		case .xboxElite: return true
		default: return false
		}
	}

	func isSteamController(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsSteamController
		case .steam: return true
		default: return false
		}
	}

	func isNintendo(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsNintendo
		case .nintendo: return true
		default: return false
		}
	}

	/// Non-nil when this preview selects one of the small 8BitDo pads.
	/// `.active` resolves connected pads by their SDL/HID product name.
	func eightBitDoModel(using service: ControllerService) -> EightBitDoMinimapModel? {
		switch self {
		case .active: return service.threadSafeEightBitDoMinimapModel
		case .eightBitDoZero2: return .zero2
		case .eightBitDoMicro: return .micro
		case .eightBitDoLite2: return .lite2
		case .eightBitDoLiteSE: return .liteSE
		default: return nil
		}
	}

	func isAppleTVRemote(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsAppleTVRemote
		case .appleTVRemote: return true
		default: return false
		}
	}
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
struct ControllerVisualView: View, ControllerTypeProviding {
	private static let mappingPasteboardType = NSPasteboard.PasteboardType("com.kevintang.ControllerKeys.keyMapping")

    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    @Binding var selectedButton: ControllerButton?
    var selectedLayerId: UUID? = nil  // nil = base layer
    var swapFirstButton: ControllerButton? = nil  // First button selected in swap mode
    var isSwapMode: Bool = false
	var previewLayout: ControllerPreviewLayout = .active
    var onButtonTap: (ControllerButton) -> Void

    @State private var hoveredButton: ControllerButton?

	var isPlayStation: Bool { previewLayout.isPlayStation(using: controllerService) }
	var isDualSense: Bool { previewLayout.isDualSense(using: controllerService) }
	var isDualSenseEdge: Bool { previewLayout.isDualSenseEdge(using: controllerService) }
	var isDualShock: Bool { previewLayout.isDualShock(using: controllerService) }
	var isXboxElite: Bool { previewLayout.isXboxElite(using: controllerService) }
	var isSteamController: Bool { previewLayout.isSteamController(using: controllerService) }
	var isNintendo: Bool { previewLayout.isNintendo(using: controllerService) }
	var isAppleTVRemote: Bool { previewLayout.isAppleTVRemote(using: controllerService) }
	var eightBitDoModel: EightBitDoMinimapModel? { previewLayout.eightBitDoModel(using: controllerService) }

	/// The small 8BitDo pads (Zero 2, Micro) are stickless: the physical d-pad
	/// feeds the left-stick axis, so they expose no analog sticks at all. The
	/// Lite 2 / Lite SE are full pads with real sticks.
	var isStickless: Bool { eightBitDoModel == .zero2 || eightBitDoModel == .micro }

	/// Whether the previewed controller exposes analog sticks in the sidebar.
	var hasSticks: Bool { !isStickless }

	/// The Zero 2 has no triggers at all (only L/R bumpers). Every other
	/// controller — including the Micro (L2/R2) — does.
	var hasTriggers: Bool { eightBitDoModel != .zero2 }

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
			Group {
				if isAppleTVRemote {
					appleTVRemoteLayout
				} else {
					standardControllerLayout
				}
			}
			.overlayPreferenceValue(ControllerButtonAnchorPreferenceKey.self) { endpoints in
				GeometryReader { proxy in
					ConnectorLayer(
						endpoints: endpoints,
						proxy: proxy,
						isAppleTVRemote: isAppleTVRemote,
						hoveredButton: hoveredButton,
						emphasizedButtons: connectorEmphasisButtons
					)
				}
			}
	    }

	    @ViewBuilder
	    private var standardControllerLayout: some View {
			HStack(alignment: .center, spacing: 0) {
            // Left Column: Shoulder and Left-side inputs
            VStack(alignment: .trailing, spacing: 16) {
                referenceGroup(title: "Shoulder", buttons: hasTriggers ? [.leftTrigger, .leftBumper] : [.leftBumper])
                if isStickless {
                    // Stickless pads: the d-pad IS the left-stick axis, so a
                    // single section drives both the mode (mouse/scroll/d-pad/…)
                    // and the per-direction bindings.
                    sticklessDpadSection
                } else {
                    stickModeSection(title: "Left Stick", side: .left, center: .leftThumbstick)
                    dpadDirectionCluster
                }
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
                if isSteamController {
                    steamTouchpadButtonsSection
                } else if isPlayStation {
                    touchpadButtonsSection
                }

                // Layer scope chip sits above the controller so it never
                // covers the controls drawn at the body's top edge.
                layerScopeChip()

                ZStack {
                    // Controller body - styled per controller model
                    controllerBodyView
                        .frame(width: controllerPreviewWidth, height: controllerPreviewHeight)

                    // Compact Controller Overlay (Just icons, no labels)
                    // Extracted into a separate view to isolate 15Hz analog display
                    // updates from the rest of the view hierarchy
                    ControllerAnalogOverlay(
                        controllerService: controllerService,
                        isPlayStation: isPlayStation,
                        isNintendo: isNintendo,
                        isXboxElite: isXboxElite,
                        isSteamController: isSteamController,
                        isDualShock: isDualShock,
                        isDualSenseEdge: isDualSenseEdge,
                        eightBitDoModel: eightBitDoModel,
                        elitePaddleButtons: [
                            eliteReferenceButton(for: .xboxPaddle1),
                            eliteReferenceButton(for: .xboxPaddle2),
                            eliteReferenceButton(for: .xboxPaddle3),
                            eliteReferenceButton(for: .xboxPaddle4)
                        ],
                        touchpadInputMode: touchpadInputMode,
                        onButtonTap: onButtonTap,
                        onButtonHover: handleButtonHover,
						onSwapRequest: performSwap,
						overrideColorForButton: layerOverrideColor(for:)
                    )
                    .frame(width: controllerPreviewWidth, height: controllerPreviewHeight)
                }
                .accessibilityHidden(true)

                // System Buttons Reference
                HStack(spacing: 20) {
                    VStack(alignment: .trailing) {
                        referenceRow(for: .view)
                        // The Zero 2 has no home/guide button at all.
                        if eightBitDoModel != .zero2 {
                            referenceRow(for: .xbox)
                        }
                    }
                    .frame(width: 220)
                    VStack(alignment: .leading) {
                        referenceRow(for: .menu)
                        // Show mic mute for DualSense, share for Xbox (but not Elite 2 where
                        // the Share button is the hardware profile cycle button, not mappable)
                        // DualShock 4's physical Share button maps to .view (buttonOptions), not .share
                        // On 8BitDo pads the star is the firmware profile button (not mappable),
                        // so it never gets a reference row — it shows on the minimap only.
                        if isDualSense {
                            referenceRow(for: .micMute)
                        } else if !isDualShock && (!isXboxElite || isSteamController) && eightBitDoModel == nil {
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
                if isXboxElite || isSteamController {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isSteamController ? "STEAM GRIP BUTTONS" : "ELITE PADDLES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Upper")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.7))
                                .padding(.horizontal, 4)
                            HStack(spacing: 20) {
								referenceRow(for: eliteReferenceButton(for: .xboxPaddle1))
                                    .frame(width: 220, alignment: .trailing)
								referenceRow(for: eliteReferenceButton(for: .xboxPaddle2))
                                    .frame(width: 220, alignment: .leading)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lower")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.7))
                                .padding(.horizontal, 4)
                            HStack(spacing: 20) {
								referenceRow(for: eliteReferenceButton(for: .xboxPaddle3))
                                    .frame(width: 220, alignment: .trailing)
								referenceRow(for: eliteReferenceButton(for: .xboxPaddle4))
                                    .frame(width: 220, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .frame(width: 460)

            // Right Column: Face buttons and Right-side inputs
            VStack(alignment: .leading, spacing: 16) {
                referenceGroup(title: "Shoulder", buttons: hasTriggers ? [.rightTrigger, .rightBumper] : [.rightBumper])
                referenceGroup(title: "Actions", buttons: [.y, .b, .a, .x])
                if hasSticks {
                    stickModeSection(title: "Right Stick", side: .right, center: .rightThumbstick)
                }
            }
            .frame(width: 220)
            .padding(.leading, 20)
			}
			.padding(20)
	    }

    func handleButtonHover(_ button: ControllerButton, _ hovering: Bool) {
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

    @ViewBuilder
    private var steamTouchpadButtonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("STEAM TOUCHPADS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                touchpadModeTabs
            }
            .padding(.horizontal, 4)

            switch touchpadInputMode {
            case .wholePad:
                steamWholePadTouchpadRows
            case .quadrants:
                steamQuadrantTouchpadRows
            }
        }
    }

    @ViewBuilder
    private var steamWholePadTouchpadRows: some View {
        HStack(spacing: 20) {
            VStack(alignment: .trailing) {
                referenceRow(for: .leftTouchpadButton)
                referenceRow(for: .leftTouchpadTap)
            }
            .frame(width: 220)
            VStack(alignment: .leading) {
                referenceRow(for: .rightTouchpadButton)
                referenceRow(for: .rightTouchpadTap)
            }
            .frame(width: 220)
        }
    }

    @ViewBuilder
    private var steamQuadrantTouchpadRows: some View {
        HStack(alignment: .top, spacing: 20) {
            steamQuadrantColumn(side: .left, alignment: .trailing)
                .frame(width: 220)
            steamQuadrantColumn(side: .right, alignment: .leading)
                .frame(width: 220)
        }
    }

    @ViewBuilder
    private func steamQuadrantColumn(side: SteamTouchpadSide, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text("\(side.displayName.uppercased()) PAD")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary.opacity(0.75))
                .padding(.horizontal, 4)

            ForEach(TouchpadRegion.allCases) { region in
                let click = ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .click)
                let touch = ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .touch)
                VStack(alignment: alignment, spacing: 3) {
                    if let click {
                        referenceRow(for: click)
                    }
                    if let touch {
                        referenceRow(for: touch)
                    }
                }
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
    func performSwap(from source: ControllerButton, to target: ControllerButton) {
        guard source != target else { return }
        if let layerId = selectedLayerId {
            profileManager.swapLayerMappings(button1: source, button2: target, in: layerId)
        } else {
            profileManager.swapMappings(button1: source, button2: target)
        }
    }

    // MARK: - Controller Body

	/// Resolved minimap style for the previewed controller.
	var minimapStyle: ControllerMinimapStyle {
		if let eightBitDoModel { return eightBitDoModel.minimapStyle }
		if isSteamController { return .steam }
		if isDualShock { return .dualShock }
		if isDualSenseEdge { return .dualSenseEdge }
		if isPlayStation { return .dualSense }
		if isNintendo { return .nintendo }
		if isXboxElite { return .xboxElite }
		return .xbox
	}

	private var controllerPreviewWidth: CGFloat { minimapStyle.previewSize.width }
	private var controllerPreviewHeight: CGFloat { minimapStyle.previewSize.height }

	private var controllerBodyView: some View {
		ControllerBodyView(style: minimapStyle)
	}

	// MARK: - Reference UI Components

    @ViewBuilder
    func referenceGroup(title: String, buttons: [ControllerButton], rowSpacing: CGFloat = 12) -> some View {
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

    /// D-pad section for stickless pads (Zero 2 / Micro). The physical d-pad
    /// feeds the left-stick axis, so its dropdown is the d-pad's own preset
    /// picker — Arrow Keys / WASD / Custom (which route the axis back to true
    /// d-pad buttons) — extended with Mouse and Scroll (which drive the axis
    /// directly). There is deliberately no "D-Pad" entry: that StickMode exists
    /// to make an analog *stick* emulate a d-pad, which is meaningless for a
    /// control that already is one. The direction tiles only appear for the key
    /// presets, where binding the four directions makes sense.
    @ViewBuilder
    private var sticklessDpadSection: some View {
        let mode = stickMode(side: .left)
        // Arrow Keys / WASD / Custom all run through StickMode.dpad; Mouse and
        // Scroll drive the axis, so the per-direction tiles are only relevant
        // in the key presets.
        let showsDirections = (mode == .dpad)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("D-Pad")
                    .textCase(.uppercase)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer(minLength: 4)
                sticklessDpadModeMenu
            }
            .padding(.horizontal, 4)

            if showsDirections {
                directionClusterGrid(
                    up: .dpadUp,
                    left: .dpadLeft,
                    center: .label(""),
                    right: .dpadRight,
                    down: .dpadDown
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Dropdown for the stickless d-pad: the d-pad key presets plus Mouse and
    /// Scroll. Arrow Keys / WASD / Custom seed the d-pad button mappings and
    /// route the axis to the d-pad; Mouse / Scroll switch the axis directly.
    private var sticklessDpadModeMenu: some View {
        let mode = stickMode(side: .left)
        let preset = profileManager.activeProfile?.dpadPreset ?? .custom
        let label: String = {
            switch mode {
            case .mouse: return "Mouse"
            case .scroll: return "Scroll"
            case .none: return "Off"
            default: return preset.displayName  // Arrows / WASD / Custom
            }
        }()
        let isKeyMode = (mode == .dpad)

        return Menu {
            sticklessDpadModeButton("Arrow Keys", selected: isKeyMode && preset == .arrows) {
                profileManager.setDPadPreset(.arrows)
                setStickMode(.dpad, side: .left)
            }
            sticklessDpadModeButton("WASD", selected: isKeyMode && preset == .wasd) {
                profileManager.setDPadPreset(.wasd)
                setStickMode(.dpad, side: .left)
            }
            sticklessDpadModeButton("Custom", selected: isKeyMode && preset == .custom) {
                profileManager.setDPadPreset(.custom)
                setStickMode(.dpad, side: .left)
            }
            Divider()
            sticklessDpadModeButton("Mouse", selected: mode == .mouse) {
                setStickMode(.mouse, side: .left)
            }
            sticklessDpadModeButton("Scroll", selected: mode == .scroll) {
                setStickMode(.scroll, side: .left)
            }
            sticklessDpadModeButton("Off", selected: mode == StickMode.none) {
                setStickMode(StickMode.none, side: .left)
            }
        } label: {
            HStack(spacing: 4) {
                Text(LocalizedStringKey(label))
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
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
        .help("Set what the D-pad does")
    }

    @ViewBuilder
    private func sticklessDpadModeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
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

    func directionCluster(
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
			Button("Custom") {
				profileManager.setDPadPreset(.custom)
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

	func layerScopeChip(nameMaxWidth: CGFloat = 112) -> some View {
		let layer = selectedLayer
		let color = layer.map { layerColor($0) } ?? Color.secondary
		let layerName = layer?.name

		return HStack(spacing: 6) {
			Circle()
				.fill(color)
				.frame(width: 7, height: 7)
			Text(layer == nil ? "BASE" : "LAYER")
				.font(.system(size: 8, weight: .black, design: .rounded))
				.foregroundStyle(.secondary)
			if let layerName {
				Text(layerName)
					.font(.system(size: 10, weight: .heavy, design: .rounded))
					.foregroundStyle(.primary)
					.lineLimit(1)
					.truncationMode(.tail)
					.minimumScaleFactor(0.65)
					.frame(maxWidth: nameMaxWidth, alignment: .leading)
			}
		}
		.padding(.horizontal, 9)
		.frame(height: 24)
		.background(
			Capsule()
				.fill(.regularMaterial)
				.shadow(color: color.opacity(layer == nil ? 0 : 0.24), radius: 7, x: 0, y: 2)
		)
		.overlay(
			Capsule()
				.stroke(color.opacity(layer == nil ? 0.18 : 0.7), lineWidth: 1)
		)
		.help(layerName.map { "Layer: \($0)" } ?? "Base layer")
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
			layerOverrideOutline(for: button, cornerRadius: 10)
		)
		.overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange, lineWidth: 3)
                .opacity(swapFirstButton == button ? 1 : 0)
        )
        .opacity(isBaseFallthrough(for: button) ? 0.4 : 1.0)
        .contentShape(Rectangle())
        .controllerAnchor(button, role: .label)
        .opacity(isLayerActivatorInLayerContext(button) ? 0.4 : 1.0)
        .accessibilityElement(children: .combine)
			.accessibilityLabel(button.displayName(forDualSense: isPlayStation, forNintendo: isNintendo, forAppleTVRemote: isAppleTVRemote, forEightBitDo: eightBitDoModel != nil))
		.accessibilityHint(showsLayerActivator ? "Double-tap to open layer" : "Double-tap to configure")
        .accessibilityAddTraits(.isButton)
        .help(compactHelpText(for: button, mapping: currentMapping, layer: layerActivator, showsLayer: showsLayerActivator))
        .onTapGesture { onButtonTap(button) }
        .contextMenu {
			if let layer = layerActivator, showsLayerActivator {
				Button {
					onButtonTap(button)
				} label: {
					Label("Open Layer", systemImage: "square.stack.3d.up")
				}
				Button {
					_ = profileManager.setLayerActivator(layer, button: nil)
				} label: {
					Label("Remove Layer Activator", systemImage: "link.badge.minus")
				}
				Divider()
			} else {
				Button {
					onButtonTap(button)
				} label: {
					Label("Edit Mapping", systemImage: "pencil")
				}
			}
			if !showsLayerActivator, currentMapping != nil {
				Button {
					copyMapping(for: button)
				} label: {
					Label("Copy Mapping", systemImage: "doc.on.doc")
				}
			}
			if !showsLayerActivator, canPasteMapping {
				Button {
					pasteMapping(to: button)
				} label: {
					Label("Paste Mapping", systemImage: "doc.on.clipboard")
				}
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
				isNintendo: isNintendo,
				isSteamController: isSteamController,
				isAppleTVRemote: isAppleTVRemote,
				isEightBitDo: eightBitDoModel != nil
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
           let macroName = profile.macroDisplayName(for: macroId) {
            return macroName
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
			let title = button.displayName(forDualSense: isPlayStation, forNintendo: isNintendo, forAppleTVRemote: isAppleTVRemote, forEightBitDo: eightBitDoModel != nil)
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
                ButtonIconView(
                    button: button,
						isPressed: isPressed(button),
						isDualSense: isPlayStation,
						isNintendo: isNintendo,
						isSteamController: isSteamController,
						isAppleTVRemote: isAppleTVRemote,
						isEightBitDo: eightBitDoModel != nil
					)

				// Layer activator badge — hidden when viewing a different layer
				// so that context can still map the same physical button.
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
				layerOverrideOutline(for: button, cornerRadius: 10)
			)
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
        .accessibilityElement(children: .combine)
			.accessibilityLabel(button.displayName(forDualSense: isPlayStation, forNintendo: isNintendo, forAppleTVRemote: isAppleTVRemote, forEightBitDo: eightBitDoModel != nil))
		.accessibilityHint(showsLayerActivator ? "Double-tap to open layer" : "Double-tap to configure")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { onButtonTap(button) }
        .contextMenu {
			if let layer = layerActivator, showsLayerActivator {
				Button {
					onButtonTap(button)
				} label: {
					Label("Open Layer", systemImage: "square.stack.3d.up")
				}
				Button {
					_ = profileManager.setLayerActivator(layer, button: nil)
				} label: {
					Label("Remove Layer Activator", systemImage: "link.badge.minus")
				}
				Divider()
			} else {
				Button {
					onButtonTap(button)
				} label: {
					Label("Edit Mapping", systemImage: "pencil")
				}
			}
			if !showsLayerActivator, currentMapping != nil {
				Button {
					copyMapping(for: button)
				} label: {
					Label("Copy Mapping", systemImage: "doc.on.doc")
				}
			}
			if !showsLayerActivator, canPasteMapping {
				Button {
					pasteMapping(to: button)
				} label: {
					Label("Paste Mapping", systemImage: "doc.on.clipboard")
				}
			}
			if currentMapping != nil {
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

    func isPressed(_ button: ControllerButton) -> Bool {
		controllerService.activeButtons.contains(button) ||
			button.physicalEquivalentButtons.contains { controllerService.activeButtons.contains($0) }
    }

	private func eliteReferenceButton(for physicalButton: ControllerButton) -> ControllerButton {
		guard let profile = profileManager.activeProfile else {
			return physicalButton.logicalEquivalent ?? physicalButton
		}
		let layerActivatorMap = Dictionary(uniqueKeysWithValues: profile.layers.compactMap { layer in
			layer.activatorButton.map { ($0, layer.id) }
		})
		let activeLayerIds = selectedLayerId.map { [$0] } ?? []
		return ButtonMappingResolutionPolicy.resolvedButton(
			button: physicalButton,
			profile: profile,
			activeLayerIds: activeLayerIds,
			layerActivatorMap: layerActivatorMap
		)
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

	private var canPasteMapping: Bool {
		pasteboardMapping() != nil
	}

	private func copyMapping(for button: ControllerButton) {
		guard let mapping = mapping(for: button),
			  let data = try? JSONEncoder().encode(mapping) else { return }
		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		pasteboard.setData(data, forType: Self.mappingPasteboardType)
		pasteboard.setString(mapping.compactDescription, forType: .string)
	}

	private func pasteMapping(to button: ControllerButton) {
		guard let mapping = pasteboardMapping() else { return }
		if let layer = selectedLayer {
			profileManager.setLayerMapping(mapping, for: button, in: layer)
		} else {
			profileManager.setMapping(mapping, for: button)
		}
	}

	private func pasteboardMapping() -> KeyMapping? {
		guard let data = NSPasteboard.general.data(forType: Self.mappingPasteboardType) else { return nil }
		return try? JSONDecoder().decode(KeyMapping.self, from: data)
	}

    private func layerOverrideColor(for button: ControllerButton) -> Color? {
		guard let layer = selectedLayer,
			  layer.activatorButton != button,
			  let mapping = layer.buttonMappings[button],
			  !mapping.isEmpty else { return nil }
		return layerColor(layer)
	}

	@ViewBuilder
	private func layerOverrideOutline(for button: ControllerButton, cornerRadius: CGFloat) -> some View {
		if let color = layerOverrideColor(for: button) {
			RoundedRectangle(cornerRadius: cornerRadius)
				.stroke(color.opacity(0.9), lineWidth: 2)
				.shadow(color: color.opacity(0.35), radius: 4, x: 0, y: 0)
		}
    }

    /// Returns true if the mapping shown is from the base layer (fallthrough)
    private func isBaseFallthrough(for button: ControllerButton) -> Bool {
        guard let layer = selectedLayer,
              let profile = profileManager.activeProfile else { return false }

        // Not a fallthrough if button is the layer's activator
        if layer.activatorButton == button { return false }

        // It's a fallthrough if the layer doesn't have a mapping for this button
        let hasLayerMapping = layer.buttonMappings[button]?.isEmpty == false
        let hasBaseMapping = profile.buttonMappings[button] != nil

        return !hasLayerMapping && hasBaseMapping
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
	let isAppleTVRemote: Bool
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
				let start = controllerEdgePoint(of: controllerRect, button: pair.button, towards: labelCenter)
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

	private static func usesCircularAppleTVConnector(for button: ControllerButton) -> Bool {
		switch button {
		case .touchpadButton, .touchpadTap,
			 .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
			 .view, .menu, .xbox, .appleTVRemotePower, .appleTVRemoteMute:
			return true
		default:
			return false
		}
	}

	private func controllerEdgePoint(of rect: CGRect, button: ControllerButton, towards target: CGPoint) -> CGPoint {
		if isAppleTVRemote && Self.usesCircularAppleTVConnector(for: button) {
			return circleEdgePoint(of: rect, towards: target)
		}
		return rectEdgePoint(of: rect, towards: target)
	}

	private func circleEdgePoint(of rect: CGRect, towards target: CGPoint) -> CGPoint {
		let center = CGPoint(x: rect.midX, y: rect.midY)
		let dx = target.x - center.x
		let dy = target.y - center.y
		if dx == 0 && dy == 0 { return center }

		let distance = hypot(dx, dy)
		let radius = min(rect.width, rect.height) / 2
		return CGPoint(
			x: center.x + dx / distance * radius,
			y: center.y + dy / distance * radius
		)
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
