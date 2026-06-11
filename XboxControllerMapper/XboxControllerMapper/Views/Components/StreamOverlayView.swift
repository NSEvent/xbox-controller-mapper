import SwiftUI
import Combine

/// Compact controller overlay for OBS/streaming capture.
/// Renders the same product-accurate minimap as the Buttons tab (body
/// silhouette + live button/stick/touchpad state) for whichever controller
/// is actually connected, plus a last-action text line.
struct StreamOverlayView: View {
    @ObservedObject var controllerService: ControllerService
    @ObservedObject var inputLogService: InputLogService

    @State private var lastActionText: String = ""
    @State private var lastActionOpacity: Double = 0
    @State private var hideTimer: Timer?

    /// Width the controller graphic is scaled to fit in the overlay panel.
    private let graphicWidth: CGFloat = 200

    private var isAppleTVRemote: Bool {
        controllerService.threadSafeIsAppleTVRemote
    }

    /// Resolved from the connected controller so the overlay always matches
    /// the active hardware (previously this was hardcoded to Xbox vs
    /// PlayStation only).
    private var minimapStyle: ControllerMinimapStyle {
        if controllerService.threadSafeIsSteamController { return .steam }
        if controllerService.threadSafeIsDualShock { return .dualShock }
        if controllerService.threadSafeIsDualSenseEdge { return .dualSenseEdge }
        if controllerService.threadSafeIsPlayStation { return .dualSense }
        if controllerService.threadSafeIsNintendo { return .nintendo }
        if controllerService.threadSafeIsXboxElite { return .xboxElite }
        return .xbox
    }

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if isAppleTVRemote {
                    appleTVRemoteGraphic
                } else {
                    controllerGraphic
                }
            }
            // Display-only: let clicks anywhere drag the panel
            .allowsHitTesting(false)

            // Last action line — shows held actions while held, otherwise last single action
            Text(displayActionText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .frame(height: 16)
                .opacity(displayActionOpacity)
                .animation(.easeInOut(duration: 0.2), value: displayActionOpacity)
        }
        .padding(10)
        .background(overlayBackground)
        .onChange(of: inputLogService.entries) { _, entries in
            if let latest = entries.first {
                showAction(latest)
            }
        }
        .onDisappear {
            hideTimer?.invalidate()
        }
        .accessibilityHidden(true)
    }

    // MARK: - Background

    @ViewBuilder
    private var overlayBackground: some View {
        let style = StreamOverlayManager.backgroundStyle
        switch style {
        case .semiTransparent:
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.5))
        case .chromaGreen, .chromaMagenta, .solid:
            RoundedRectangle(cornerRadius: 12)
                .fill(style.color)
        }
    }

    // MARK: - Controller Graphic

    private var controllerGraphic: some View {
        let style = minimapStyle
        let size = style.previewSize
        let scale = graphicWidth / size.width

        return ZStack {
            ControllerBodyView(style: style)
                .frame(width: size.width, height: size.height)

            ControllerAnalogOverlay(
                controllerService: controllerService,
                isPlayStation: controllerService.threadSafeIsPlayStation,
                isNintendo: controllerService.threadSafeIsNintendo,
                isXboxElite: controllerService.threadSafeIsXboxElite,
                isSteamController: controllerService.threadSafeIsSteamController,
                isDualShock: controllerService.threadSafeIsDualShock,
                isDualSenseEdge: controllerService.threadSafeIsDualSenseEdge,
                onButtonTap: { _ in }
            )
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(scale)
        .frame(width: graphicWidth, height: (size.height * scale).rounded())
    }

    // MARK: - Apple TV Remote Graphic

    /// Compact Siri Remote: aluminum body, live clickpad, system buttons.
    private var appleTVRemoteGraphic: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.88), Color(white: 0.64)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
                )
                .frame(width: 48, height: 148)

            VStack(spacing: 7) {
                // Clickpad with live touch indicator
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.14), Color(white: 0.05)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)

                    if isPressed(.touchpadButton) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.65))
                            .frame(width: 22, height: 22)
                    }

                    if controllerService.displayIsTouchpadTouching {
                        let pos = boundedTouchPosition
                        Circle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 5, height: 5)
                            .offset(x: pos.x * 14, y: -pos.y * 14)
                    }
                }

                HStack(spacing: 7) {
                    remoteDot(.view, systemImage: "chevron.left")
                    remoteDot(.xbox, systemImage: "tv.fill")
                }
                HStack(spacing: 7) {
                    remoteDot(.menu, systemImage: "playpause.fill")
                    remoteDot(.appleTVRemoteMute, systemImage: "speaker.slash.fill")
                }

                // Volume rocker
                VStack(spacing: 1) {
                    remoteDot(.appleTVRemoteVolumeUp, systemImage: "plus", capsuleHalf: true)
                    remoteDot(.appleTVRemoteVolumeDown, systemImage: "minus", capsuleHalf: true)
                }
            }
        }
        .frame(width: graphicWidth, height: 156)
    }

    private func remoteDot(_ button: ControllerButton, systemImage: String, capsuleHalf: Bool = false) -> some View {
        let pressed = isPressed(button)
        let shape = RoundedRectangle(cornerRadius: capsuleHalf ? 4 : 7.5, style: .continuous)

        return Image(systemName: systemImage)
            .font(.system(size: 6.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 15, height: capsuleHalf ? 13 : 15)
            .background(shape.fill(pressed ? Color.accentColor : Color(white: 0.10)))
    }

    private var boundedTouchPosition: CGPoint {
        let raw = controllerService.displayTouchpadPosition
        let x = min(max(raw.x, -1), 1)
        let y = min(max(raw.y, -1), 1)
        let distance = hypot(x, y)
        guard distance > 1 else { return CGPoint(x: x, y: y) }
        return CGPoint(x: x / distance, y: y / distance)
    }

    // MARK: - Display Logic

    /// Shows held actions when modifiers are held, otherwise shows last single action.
    /// When a non-held action fires while modifiers are held, combines both (e.g. "⌘ + →").
    private var displayActionText: String {
        if !inputLogService.heldActions.isEmpty {
            var parts = inputLogService.heldActions
            // Include the latest non-held action alongside held modifiers
            if !lastActionText.isEmpty && !parts.contains(lastActionText) {
                parts.append(lastActionText)
            }
            return parts.joined(separator: " + ")
        }
        return lastActionText
    }

    private var displayActionOpacity: Double {
        if !inputLogService.heldActions.isEmpty {
            return 1.0
        }
        return lastActionOpacity
    }

    // MARK: - Helpers

    private func isPressed(_ button: ControllerButton) -> Bool {
        controllerService.activeButtons.contains(button)
    }

    private func showAction(_ entry: InputLogEntry) {
        hideTimer?.invalidate()
        lastActionText = entry.actionDescription
        lastActionOpacity = 1.0

        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            Task { @MainActor in
                self.lastActionOpacity = 0
            }
        }
    }
}
