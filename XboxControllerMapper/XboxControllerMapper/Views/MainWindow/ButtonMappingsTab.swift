import SwiftUI

/// The main controller visual tab showing the button mapping diagram, layer bar,
/// and active chords/sequences.
struct ButtonMappingsTab: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @Binding var selectedButton: ControllerButton?
    @Binding var configuringButton: ControllerButton?
    @Binding var selectedLayerId: UUID?
    @Binding var isSwapMode: Bool
    @Binding var swapFirstButton: ControllerButton?
    @Binding var showingAddLayerSheet: Bool
    @Binding var editingLayerId: UUID?
    @Binding var editingChord: ChordMapping?
    @Binding var editingSequence: SequenceMapping?
    @Binding var isMagnifying: Bool
    var actionFeedbackEnabled: Binding<Bool>
    var streamOverlayEnabled: Binding<Bool>

    var body: some View {
        VStack(spacing: 0) {
            InputLogView()
                .padding(.top, 8)

            // Layer Tab Bar
            LayerTabBar(
                selectedLayerId: $selectedLayerId,
                isSwapMode: $isSwapMode,
                swapFirstButton: $swapFirstButton,
                showingAddLayerSheet: $showingAddLayerSheet,
                editingLayerId: $editingLayerId,
                actionFeedbackEnabled: actionFeedbackEnabled,
                streamOverlayEnabled: streamOverlayEnabled
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            GeometryReader { geometry in
                // Base size of ControllerVisualView content
                let baseWidth: CGFloat = 920
                let baseHeight: CGFloat = 580

                // Calculate scale to fit available space (allow both up and down scaling)
                let scaleX = geometry.size.width / baseWidth
                let scaleY = geometry.size.height / baseHeight
                let autoScale = min(scaleX, scaleY)

                // Combine with user's manual zoom setting
                let finalScale = autoScale * profileManager.uiScale

                ControllerVisualView(
                    selectedButton: $selectedButton,
                    selectedLayerId: selectedLayerId,
                    swapFirstButton: swapFirstButton,
                    isSwapMode: isSwapMode,
                    onButtonTap: { button in
                        // Ignore taps during magnification gestures to prevent accidental triggers
                        guard !isMagnifying else { return }
                        // Async dispatch to avoid layout recursion if triggered during layout pass
                        DispatchQueue.main.async {
                            if isSwapMode {
                                handleSwapButtonTap(button)
                            } else {
                                selectedButton = button
                                configuringButton = button
                            }
                        }
                    }
                )
                .scaleEffect(finalScale)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(!isMagnifying)
            }
            .clipped()

            // Mapped Chords Display
            ActiveChordsView(editingChord: $editingChord)

            // Mapped Sequences Display
            ActiveSequencesView(editingSequence: $editingSequence)
        }
        .sheet(isPresented: $showingAddLayerSheet) {
            AddLayerSheet()
        }
        .sheet(item: $editingLayerId) { layerId in
            if let profile = profileManager.activeProfile,
               let layer = profile.layers.first(where: { $0.id == layerId }) {
                EditLayerSheet(layer: layer)
            }
        }
        .onChange(of: controllerService.activeButtons) { _, activeButtons in
            guard let profile = profileManager.activeProfile else { return }

            // Check if any layer activator is being held
            for layer in profile.layers {
                if let activator = layer.activatorButton, activeButtons.contains(activator) {
                    selectedLayerId = layer.id
                    return
                }
            }

            // No layer activator held - return to base layer
            selectedLayerId = nil
        }
    }

    // MARK: - Swap Mode

    private func handleSwapButtonTap(_ button: ControllerButton) {
        if let firstButton = swapFirstButton {
            // Second button selected - perform the swap
            if let layerId = selectedLayerId {
                profileManager.swapLayerMappings(button1: firstButton, button2: button, in: layerId)
            } else {
                profileManager.swapMappings(button1: firstButton, button2: button)
            }
            // Exit swap mode
            swapFirstButton = nil
            isSwapMode = false
        } else {
            // First button selected
            swapFirstButton = button
        }
    }
}
