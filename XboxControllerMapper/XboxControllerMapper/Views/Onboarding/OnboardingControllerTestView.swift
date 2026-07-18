import SwiftUI

/// The first-run "try your controller" step.
///
/// Shows the live controller visualization and lets the user press buttons to
/// see them light up and learn what each one does — the app's first legible
/// "it works" moment. Three jobs at once:
///  1. **Connection check** — proves the controller is detected before the user
///     is loose in the app (half of support tickets are "is it even connected?").
///  2. **Safe aha** — the mapping engine is muted while this step is on screen,
///     so a curious button-masher can't fire real actions (Paste, Cmd+W, app
///     switch) into their documents on first contact. Presses only drive the
///     on-screen diagram.
///  3. **Teaching** — each press surfaces its binding ("A → Left Click") instead
///     of making the user decode a settings tab.
///
/// When no controller is connected the step shows pairing guidance and swaps to
/// the live view automatically the moment one connects (SwiftUI reactivity on
/// `ControllerService.isConnected`).
struct OnboardingControllerTestView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var mappingEngine: MappingEngine

    /// Distinct buttons the user has pressed during this step (drives the
    /// encouraging progress line).
    @State private var buttonsSeen: Set<ControllerButton> = []
    /// Most recently pressed button, for the "what it does" caption.
    @State private var lastPressed: ControllerButton?
    /// The engine's `isEnabled` value before this step muted it, restored on exit.
    @State private var savedEngineEnabled: Bool?

    /// Width the controller minimap is scaled to inside the 480pt sheet. Leaves
    /// comfortable side margins so nothing crowds the edges.
    private let minimapWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if controllerService.isConnected {
                connectedContent
            } else {
                noControllerContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { muteEngineForSafePreview() }
        .onDisappear { restoreEngine() }
        .onChange(of: controllerService.activeButtons) { _, active in
            trackPresses(active)
        }
    }

    // MARK: - Connected

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("**\(controllerService.controllerName)** is connected.")
                    .font(.callout)
                Text("Press any button — it lights up below and shows what it does. Nothing you press here touches your Mac.")
                    .font(.callout)
            }

            controllerCanvas

            captionCard

            progressLine
        }
    }

    /// A clean, label-free controller minimap that lights up pressed buttons.
    /// Deliberately *not* the full Buttons-tab canvas — that fans binding labels
    /// out on both sides and is far too wide for the sheet. The "what it does"
    /// teaching is carried by `captionCard` instead, so a minimal body that
    /// highlights on press is both legible and uncramped. Passing a concrete
    /// layout resolves the actual connected controller regardless of the
    /// minimap's own hardware-free service.
    private var controllerCanvas: some View {
        PairingMinimapView(
            layout: connectedLayout,
            pressedButtons: controllerService.activeButtons,
            targetWidth: minimapWidth
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.13))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The concrete preview layout for the currently connected controller, so the
    /// minimap renders the right body (DualSense, Xbox, 8BitDo, …) rather than a
    /// generic fallback.
    private var connectedLayout: ControllerPreviewLayout {
        let descriptor = ControllerVisualDescriptor.resolved(previewLayout: .active, using: controllerService)
        switch descriptor.family {
        case .xbox: return .xbox
        case .xboxElite: return .xboxElite
        case .dualSense: return .dualSense
        case .dualSenseEdge: return .dualSenseEdge
        case .dualShock: return .dualShock
        case .nintendo: return .nintendo
        case .steam: return .steam
        case .eightBitDo(let model):
            switch model {
            case .zero2: return .eightBitDoZero2
            case .micro: return .eightBitDoMicro
            case .lite2: return .eightBitDoLite2
            case .liteSE: return .eightBitDoLiteSE
            }
        case .appleTVRemote: return .appleTVRemote
        case .ouraRing: return .ouraRing
        case .beamdeskHands: return .beamdeskHands
        }
    }

    @ViewBuilder
    private var captionCard: some View {
        HStack(spacing: 8) {
            if let button = lastPressed {
                Image(systemName: "hand.point.up.left.fill")
                    .foregroundStyle(.tint)
                Text("**\(button.shortLabel)** → \(bindingLabel(for: button))")
                    .font(.callout)
            } else {
                Image(systemName: "hand.tap")
                    .foregroundStyle(.secondary)
                Text("Press a button to see what it does.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    @ViewBuilder
    private var progressLine: some View {
        if !buttonsSeen.isEmpty {
            let count = buttonsSeen.count
            Text(progressMessage(for: count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func progressMessage(for count: Int) -> String {
        switch count {
        case 0: return ""
        case 1: return "1 button tried — go ahead, try a few more."
        case 2...4: return "\(count) buttons tried — nice."
        default: return "\(count) buttons tried. You've got the idea — hit Continue when you're ready."
        }
    }

    // MARK: - No controller

    private var noControllerContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No controller connected yet")
                    .font(.title3.weight(.semibold))
            }

            Text("Turn your controller on and pair it over Bluetooth, or plug it in with a cable. This page updates the moment it connects.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                pairingHintRow(icon: "dot.radiowaves.left.and.right", text: "**Xbox / PlayStation:** hold the pairing button until the light flashes, then add it in **System Settings ▸ Bluetooth**.")
                pairingHintRow(icon: "cable.connector", text: "**Wired:** connect a USB cable — no pairing needed.")
                pairingHintRow(icon: "hand.tap", text: "You can skip this and try your controller later — everything still works.")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
    }

    private func pairingHintRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(.init(text))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Binding label

    /// The active profile's binding for `button`, as a short human phrase.
    private func bindingLabel(for button: ControllerButton) -> String {
        guard let profile = profileManager.activeProfile,
              let mapping = profile.buttonMappings[button] else {
            return "Not mapped"
        }
        return mapping.hint ?? mapping.displayString
    }

    // MARK: - Press tracking

    private func trackPresses(_ active: Set<ControllerButton>) {
        guard !active.isEmpty else { return }
        buttonsSeen.formUnion(active)
        if let mostRecent = active.first {
            lastPressed = mostRecent
        }
    }

    // MARK: - Safe-preview muting

    /// Disable the mapping engine while this step is visible so button presses
    /// only drive the diagram, never fire real keyboard/mouse actions. Saves the
    /// prior state so a user who had the engine turned off stays off on exit.
    private func muteEngineForSafePreview() {
        guard savedEngineEnabled == nil else { return }
        savedEngineEnabled = mappingEngine.isEnabled
        mappingEngine.disable()
    }

    private func restoreEngine() {
        if savedEngineEnabled == true {
            mappingEngine.enable()
        }
        savedEngineEnabled = nil
    }
}
