import SwiftUI

/// A static, non-interactive controller minimap for the Connection Guides that
/// highlights the buttons used to put a controller into pairing mode.
///
/// It reuses the Buttons-tab minimap renderer verbatim — `ControllerBodyView` +
/// `ControllerAnalogOverlay` for the gamepads, and `AppleTVRemoteMinimapView`
/// for the Siri Remote — and drives the highlight so the pairing buttons read
/// as "press these":
///   • a hardware-free `ControllerService` carries the pairing set in its
///     `activeButtons`, so both renderers light those buttons in their accent
///     (pressed) state;
///   • the gamepad overlay additionally draws an accent ring around them via
///     `overrideColorForButton`.
///
/// Because hardware monitoring is off, the service's analog subjects never fire,
/// so sticks/triggers stay at rest and only the pairing buttons light up.
struct PairingMinimapView: View {
    let layout: ControllerPreviewLayout
    /// On-minimap buttons that are part of the pairing combo (may be empty for
    /// controllers whose pairing button lives off the front face).
    let pressedButtons: Set<ControllerButton>
    /// Width the gamepad minimap is scaled to. The tall Siri Remote scales to
    /// `remoteTargetHeight` instead (it's far taller than it is wide).
    var targetWidth: CGFloat = 220
    var remoteTargetHeight: CGFloat = 300

    /// Quiet, hardware-free service whose only job is to carry `activeButtons`
    /// so the existing minimap lights the pairing buttons. The default-value
    /// expression is wrapped in `@StateObject`'s autoclosure, so it's created
    /// once per view identity rather than on every redraw.
    @StateObject private var service = ControllerService(enableHardwareMonitoring: false)

    var body: some View {
        Group {
            if visualDescriptor.isAppleTVRemote {
                appleTVRemoteMinimap
            } else {
                gamepadMinimap
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Keep the lit set in sync — covers both first appearance and switching
        // between controllers (the view's identity is reused across the switch).
        .onAppear { service.activeButtons = pressedButtons }
        .onChange(of: pressedButtons) { _, newValue in
            service.activeButtons = newValue
        }
    }

    // MARK: - Gamepad

    private var visualDescriptor: ControllerVisualDescriptor {
        ControllerVisualDescriptor.resolved(previewLayout: layout, using: service)
    }

    private var minimapStyle: ControllerMinimapStyle {
        visualDescriptor.minimapStyle ?? .xbox
    }

    private var gamepadMinimap: some View {
        let style = minimapStyle
        let size = style.previewSize
        let scale = targetWidth / size.width

        return ZStack {
            ControllerBodyView(style: style)
                .frame(width: size.width, height: size.height)

            ControllerAnalogOverlay(
                controllerService: service,
                isPlayStation: visualDescriptor.isPlayStation,
                isNintendo: visualDescriptor.isNintendo,
                isXboxElite: visualDescriptor.isXboxElite,
                isSteamController: visualDescriptor.isSteamController,
                isDualShock: visualDescriptor.isDualShock,
                isDualSenseEdge: visualDescriptor.isDualSenseEdge,
                eightBitDoModel: visualDescriptor.eightBitDoModel,
                onButtonTap: { _ in },
                overrideColorForButton: { pressedButtons.contains($0) ? Color.accentColor : nil }
            )
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(scale)
        .frame(width: targetWidth, height: (size.height * scale).rounded())
    }

    // MARK: - Apple TV Remote

    private var appleTVRemoteMinimap: some View {
        let size = AppleTVRemoteMinimapView.previewSize
        let scale = remoteTargetHeight / size.height

        return AppleTVRemoteMinimapView(controllerService: service)
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .frame(width: (size.width * scale).rounded(), height: remoteTargetHeight)
    }
}
