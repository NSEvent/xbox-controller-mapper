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
    @State private var isHoveringPanel = false

    /// Width the controller graphic is scaled to fit in the overlay panel.
    private let graphicWidth: CGFloat = 200

    private var isAppleTVRemote: Bool {
        visualDescriptor.isAppleTVRemote
    }

    /// Resolved from the connected controller so the overlay always matches
    /// the active hardware (previously this was hardcoded to Xbox vs
    /// PlayStation only).
    private var visualDescriptor: ControllerVisualDescriptor {
        ControllerVisualDescriptor.active(using: controllerService)
    }

    private var minimapStyle: ControllerMinimapStyle {
        visualDescriptor.minimapStyle ?? .xbox
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
        .overlay(alignment: .topTrailing) {
            // Close button, shown while the pointer is over the panel so
            // OBS captures stay clean.
            if isHoveringPanel {
                Button {
                    StreamOverlayManager.shared.hide()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.9), Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(5)
                .help("Close stream overlay")
                .accessibilityLabel("Close stream overlay")
            }
        }
        .onHover { isHoveringPanel = $0 }
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
                descriptor: visualDescriptor,
                onButtonTap: { _ in }
            )
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(scale)
        .frame(width: graphicWidth, height: (size.height * scale).rounded())
    }

    // MARK: - Apple TV Remote Graphic

    /// The exact same Siri Remote minimap as the Buttons tab, scaled down.
    private var appleTVRemoteGraphic: some View {
        let size = AppleTVRemoteMinimapView.previewSize
        let height: CGFloat = 165
        let scale = height / size.height

        return AppleTVRemoteMinimapView(controllerService: controllerService)
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .frame(width: graphicWidth, height: height)
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
