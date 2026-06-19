import SwiftUI

/// Width probe for the layer bar — lets the bar collapse its pills to icon-only
/// when the available width drops below what the full text labels need.
private struct LayerBarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

/// Tab bar for switching between base layer and custom layers, with swap mode
/// and overlay toggles.
struct LayerTabBar: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    @Binding var selectedLayerId: UUID?
    @Binding var isSwapMode: Bool
    @Binding var swapFirstButton: ControllerButton?
    @Binding var showingAddLayerSheet: Bool
    @Binding var editingLayerId: UUID?
    var actionFeedbackEnabled: Binding<Bool>
    var streamOverlayEnabled: Binding<Bool>

    @State private var colorEditingLayerId: UUID? = nil
    @State private var colorEditingColor: Color = .blue
    /// Measured outer width of the bar; drives the compact (icon-only) collapse.
    @State private var barWidth: CGFloat = 0

    /// Fixed height for every pill in the bar. Combined with single-line labels
    /// this keeps the buttons a consistent height — at narrow widths the labels
    /// truncate instead of wrapping to a second line and growing tall.
    private let controlHeight: CGFloat = 28

    /// SF Symbol that stands in for a layer (Base layer and, when collapsed,
    /// each custom layer tab) — keeps the bar legible once labels are dropped.
    private let layerSymbol = "square.stack.3d.up"

    /// Below this width the pills drop their text and show icons only. Scales
    /// with layer count since each extra layer tab needs room for its label.
    private var compactThreshold: CGFloat {
        let layerCount = profileManager.activeProfile?.layers.count ?? 0
        return 470 + CGFloat(layerCount) * 96
    }

    /// True once measured and the bar is too narrow for full text labels.
    private var compact: Bool { barWidth > 1 && barWidth < compactThreshold }

    /// Returns the layer's configured LED color, or a fallback purple if none is set.
    private func layerBadgeColor(_ layer: Layer) -> Color {
        if let led = layer.dualSenseLEDSettings, led.lightBarEnabled {
            return led.lightBarColor.color
        }
        return Color.purple.opacity(0.8)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Base Layer tab (always present)
            Button {
                selectedLayerId = nil
            } label: {
                HStack(spacing: compact ? 0 : 6) {
                    Image(systemName: layerSymbol)
                        .font(.caption)
                    if !compact {
                        Text("Base")
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, compact ? 8 : 12)
                .frame(height: controlHeight)
                .background(selectedLayerId == nil ? Color.accentColor : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .foregroundColor(selectedLayerId == nil ? .white : .secondary)
            .help("Base layer")
            .accessibilityLabel("Base layer")
            .hoverableButton()

            // Layer tabs
            if let profile = profileManager.activeProfile {
                ForEach(profile.layers) { layer in
                    Button {
                        selectedLayerId = layer.id
                    } label: {
                        HStack(spacing: 6) {
                            // Compact: reuse the layer symbol in place of the name.
                            // The activator badge stays, so layers remain
                            // distinguishable by their colored shortcut chip.
                            if compact {
                                Image(systemName: layerSymbol)
                                    .font(.caption)
                            } else {
                                Text(layer.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                            }
                            // Activator button badge (or "No Activator" if unassigned)
                            if let activator = layer.activatorButton {
									Text(activator.shortLabel(forDualSense: controllerService.threadSafeIsPlayStation, forNintendo: controllerService.threadSafeIsNintendo, forAppleTVRemote: controllerService.threadSafeIsAppleTVRemote))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(layerBadgeColor(layer))
                                    .cornerRadius(4)
                            } else {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal, compact ? 8 : 12)
                        .frame(height: controlHeight)
                        .background(selectedLayerId == layer.id ? Color.accentColor : Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(selectedLayerId == layer.id ? .white : .secondary)
                    .help(layer.name)
                    .accessibilityLabel("Layer \(layer.name)")
                    .hoverableButton()
                    .contextMenu {
                        Button("Rename...") {
                            editingLayerId = layer.id
                        }
                        Button("Change Color...") {
                            colorEditingColor = layer.dualSenseLEDSettings?.lightBarColor.color ?? .blue
                            colorEditingLayerId = layer.id
                        }
                        Button("Delete", role: .destructive) {
                            profileManager.deleteLayer(layer)
                            if selectedLayerId == layer.id {
                                selectedLayerId = nil
                            }
                        }
                    }
                    .popover(isPresented: Binding(
                        get: { colorEditingLayerId == layer.id },
                        set: { if !$0 { colorEditingLayerId = nil } }
                    )) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Layer Color: \(layer.name)")
                                .font(.headline)
                            Text("Lightbar color shown when this layer is active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ColorPicker("Color", selection: $colorEditingColor, supportsOpacity: false)
                            HStack {
                                Button("Done") {
                                    var updated = layer
                                    var led = updated.dualSenseLEDSettings ?? DualSenseLEDSettings()
                                    led.lightBarColor = CodableColor(color: colorEditingColor)
                                    led.lightBarEnabled = true
                                    updated.dualSenseLEDSettings = led
                                    profileManager.updateLayer(updated)
                                    colorEditingLayerId = nil
                                }
                                .keyboardShortcut(.defaultAction)
                            }
                        }
                        .padding()
                        .frame(width: 280)
                    }
                }
            }

            // Add Layer button (if under max)
            if let profile = profileManager.activeProfile, profile.layers.count < ProfileManager.maxLayers {
                Button {
                    showingAddLayerSheet = true
                } label: {
                    HStack(spacing: compact ? 0 : 4) {
                        Image(systemName: "plus")
                            .font(.caption)
                        if !compact {
                            Text("Add Layer")
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, compact ? 8 : 10)
                    .frame(height: controlHeight)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Add Layer")
                .accessibilityLabel("Add Layer")
                .foregroundColor(.secondary)
                .hoverableButton()
            }

            Spacer()

            // Swap mode toggle
            Toggle(isOn: $isSwapMode) {
                HStack(spacing: compact ? 0 : 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10))
                    if !compact {
                        Text(swapFirstButton != nil ? "Select 2nd" : "Swap")
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, compact ? 8 : 10)
                .frame(height: controlHeight)
                .background(isSwapMode ? Color.orange : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundColor(isSwapMode ? .white : .secondary)
            .help(swapFirstButton != nil ? "Select the second button to swap" : "Swap two buttons' mappings")
            .accessibilityLabel("Swap mappings")
            .hoverableButton()
            .onChange(of: isSwapMode) { _, newValue in
                if !newValue {
                    swapFirstButton = nil
                }
            }

            // Action feedback toggle (styled like layer tabs). Plain Button —
            // not Toggle(.button) — so the highlight is a pure function of the
            // bound value with no internal selected-state to desync.
            Button {
                actionFeedbackEnabled.wrappedValue.toggle()
            } label: {
                HStack(spacing: compact ? 0 : 4) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 10))
                    if !compact {
                        Text("Cursor Hints")
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, compact ? 8 : 10)
                .frame(height: controlHeight)
                .background(actionFeedbackEnabled.wrappedValue ? Color.accentColor : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .foregroundColor(actionFeedbackEnabled.wrappedValue ? .white : .secondary)
            .help("Cursor Hints")
            .accessibilityLabel("Cursor Hints")
            .hoverableButton()

            // Stream overlay toggle (plain Button, same rationale as above).
            Button {
                streamOverlayEnabled.wrappedValue.toggle()
            } label: {
                HStack(spacing: compact ? 0 : 4) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 10))
                    if !compact {
                        Text("Stream")
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, compact ? 8 : 10)
                .frame(height: controlHeight)
                .background(streamOverlayEnabled.wrappedValue ? Color.purple : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .foregroundColor(streamOverlayEnabled.wrappedValue ? .white : .secondary)
            .help("Stream overlay")
            .accessibilityLabel("Stream overlay")
            .hoverableButton()
        }
        .padding(6)
        .background(Color.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
        // Measure the bar's actual width so the pills can collapse to icons when
        // the row gets too narrow for full labels. The bar fills its allotted
        // width (trailing Spacer), so this is stable as `compact` toggles.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LayerBarWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        )
	.onPreferenceChange(LayerBarWidthPreferenceKey.self) { newValue in
		scheduleBarWidthUpdate(newValue)
	}
	}

	private func scheduleBarWidthUpdate(_ newValue: CGFloat) {
		let normalized = LayoutMeasurementPolicy.normalizedDimension(newValue)
		guard LayoutMeasurementPolicy.shouldUpdate(current: barWidth, proposed: normalized) else { return }

		DispatchQueue.main.async {
			guard LayoutMeasurementPolicy.shouldUpdate(current: barWidth, proposed: normalized) else { return }
			barWidth = normalized
		}
	}
}
