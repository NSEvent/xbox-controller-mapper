import SwiftUI
import AppKit

/// Empty-state shown above the controller canvas when nothing is connected.
///
/// Two modes, driven entirely by the active preview layout:
/// - **Chooser** (`previewLayout == .active`): the app can't know which device
///   the user owns, so it invites them to pair (it'll auto-connect) and offers a
///   chip for every controller family — picking one flips this view into…
/// - **Guide** (a concrete layout): the step-by-step pairing instructions for
///   that specific controller, plus quick links to Bluetooth Settings and the
///   full web guide.
///
/// The parent (`ButtonMappingsTab`) gates rendering on `!isConnected`, so this
/// view never needs to observe the controller service itself.
struct ControllerPairingHintView: View {
    let previewLayout: ControllerPreviewLayout
    /// Change the previewed controller (also drives the picker above).
    let onSelectLayout: (ControllerPreviewLayout) -> Void

    /// Every concrete family, in picker order, for the chooser grid.
    private static let selectableLayouts: [ControllerPreviewLayout] =
        ControllerPreviewLayout.concreteLayouts

    var body: some View {
        Group {
            if let guide = previewLayout.pairingGuide {
                guideCard(guide)
            } else {
                chooserCard
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassCardBackground(cornerRadius: 14))
    }

    // MARK: - Chooser (no specific controller)

    private var chooserCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                headerIcon("dot.radiowaves.left.and.right")

                VStack(alignment: .leading, spacing: 2) {
                    Text("No controller connected")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Turn your controller on and put it in pairing mode — it connects automatically. Need the steps? Pick your controller:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(Self.selectableLayouts) { layout in
                    ChooserChip(layout: layout) { onSelectLayout(layout) }
                }
            }
        }
    }

    // MARK: - Guide (specific controller)

    private func guideCard(_ guide: ControllerPairingGuide) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                headerIcon(guide.systemImage)

                VStack(alignment: .leading, spacing: 2) {
                    Text(guide.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(guide.tagline)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    onSelectLayout(.active)
                } label: {
                    Label("Choose different", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .hoverable()
                .help("Back to controller list")
                .accessibilityLabel("Back to controller list")
            }

            // Minimap of the controller, with the pairing buttons lit so the
            // user can see where to press. The caption only appears when those
            // buttons live on the front face (some controllers pair via a top
            // sync / Pair button the minimap can't show).
            VStack(spacing: 6) {
                PairingMinimapView(layout: previewLayout, pressedButtons: guide.pairingButtons)
                if !guide.pairingButtons.isEmpty {
                    Text("The buttons you press to pair are highlighted")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)

            // Numbered Bluetooth steps
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(guide.bluetoothSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.accentColor.opacity(0.85)))
                        Text(inlineMarkdown: step)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            // Supplementary notes
            VStack(alignment: .leading, spacing: 7) {
                if let wiredNote = guide.wiredNote {
                    noteRow(systemImage: "cable.connector", text: wiredNote)
                }
                if let nativeSupportNote = guide.nativeSupportNote {
                    noteRow(systemImage: "info.circle", text: nativeSupportNote)
                }
                if let tip = guide.tip {
                    noteRow(systemImage: "lightbulb", text: tip, tint: .yellow)
                }
            }

            // Actions
            HStack(spacing: 10) {
                Button {
                    openBluetoothSettings()
                } label: {
                    Label("Open Bluetooth Settings", systemImage: "bolt.horizontal.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .hoverable()
                .accessibilityLabel("Open Bluetooth Settings")

                if let guideURL = guide.guideURL {
                    Button {
                        NSWorkspace.shared.open(guideURL)
                    } label: {
                        Label("Full Guide", systemImage: "safari")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .hoverable()
                    .help("Open the full guide on the web")
                    .accessibilityLabel("Open the full guide on the web")
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func noteRow(systemImage: String, text: String, tint: Color = .secondary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(inlineMarkdown: text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    /// The accent disc + glyph shown beside each card heading; decorative, so
    /// it's hidden from VoiceOver (the adjacent title carries the meaning).
    private func headerIcon(_ systemImage: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 40, height: 40)
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityHidden(true)
    }

    private func openBluetoothSettings() {
        // Ventura+ pane id; if it can't resolve, fall back to the legacy id, then
        // to System Settings at large.
        let candidates = [
            "x-apple.systempreferences:com.apple.BluetoothSettings",
            "x-apple.systempreferences:com.apple.preferences.Bluetooth",
            "x-apple.systempreferences:"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

// MARK: - Chooser chip

/// A controller-family pick in the chooser grid. A real `Button` (so it keeps
/// keyboard focus/activation) styled with the app's shared `GlassCardBackground`
/// so it highlights on hover like every other glass row.
private struct ChooserChip: View {
    let layout: ControllerPreviewLayout
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: layout.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                Text(layout.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(GlassCardBackground(isHovered: isHovered, cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help("Show pairing steps for \(layout.displayName)")
        .accessibilityLabel("\(layout.displayName) pairing steps")
    }
}
