import SwiftUI

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

    var body: some View {
        HStack(spacing: 8) {
            // Base Layer tab (always present)
            Button {
                selectedLayerId = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.caption)
                    Text("Base Layer")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedLayerId == nil ? Color.accentColor : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .foregroundColor(selectedLayerId == nil ? .white : .secondary)
            .hoverableButton()

            // Layer tabs
            if let profile = profileManager.activeProfile {
                ForEach(profile.layers) { layer in
                    Button {
                        selectedLayerId = layer.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(layer.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            // Activator button badge (or "No Activator" if unassigned)
                            if let activator = layer.activatorButton {
                                Text(activator.shortLabel(forDualSense: controllerService.threadSafeIsPlayStation))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.8))
                                    .cornerRadius(4)
                            } else {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedLayerId == layer.id ? Color.accentColor : Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(selectedLayerId == layer.id ? .white : .secondary)
                    .hoverableButton()
                    .contextMenu {
                        Button("Rename...") {
                            editingLayerId = layer.id
                        }
                        Button("Delete", role: .destructive) {
                            profileManager.deleteLayer(layer)
                            if selectedLayerId == layer.id {
                                selectedLayerId = nil
                            }
                        }
                    }
                }
            }

            // Add Layer button (if under max)
            if let profile = profileManager.activeProfile, profile.layers.count < ProfileManager.maxLayers {
                Button {
                    showingAddLayerSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption)
                        Text("Add Layer")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .hoverableButton()
            }

            Spacer()

            // Swap mode toggle
            Toggle(isOn: $isSwapMode) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10))
                    Text(swapFirstButton != nil ? "Select 2nd" : "Swap")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSwapMode ? Color.orange : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundColor(isSwapMode ? .white : .secondary)
            .hoverableButton()
            .onChange(of: isSwapMode) { _, newValue in
                if !newValue {
                    swapFirstButton = nil
                }
            }

            // Action feedback toggle (styled like layer tabs)
            Toggle(isOn: actionFeedbackEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 10))
                    Text("Cursor Hints")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(actionFeedbackEnabled.wrappedValue ? Color.accentColor : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundColor(actionFeedbackEnabled.wrappedValue ? .white : .secondary)
            .hoverableButton()

            // Stream overlay toggle
            Toggle(isOn: streamOverlayEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 10))
                    Text("Stream")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(streamOverlayEnabled.wrappedValue ? Color.purple : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundColor(streamOverlayEnabled.wrappedValue ? .white : .secondary)
            .hoverableButton()
        }
    }
}
