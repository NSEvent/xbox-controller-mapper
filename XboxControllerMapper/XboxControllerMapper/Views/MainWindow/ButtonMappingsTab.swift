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
    @AppStorage(ButtonMappingsTabSection.hiddenDefaultsKey) private var hiddenSectionTags = ""

    private var hiddenSections: Set<ButtonMappingsTabSection> {
        ButtonMappingsTabSection.hiddenSections(from: hiddenSectionTags)
    }

    private func isSectionVisible(_ section: ButtonMappingsTabSection) -> Bool {
        !hiddenSections.contains(section)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                LayerTabBar(
                    selectedLayerId: $selectedLayerId,
                    isSwapMode: $isSwapMode,
                    swapFirstButton: $swapFirstButton,
                    showingAddLayerSheet: $showingAddLayerSheet,
                    editingLayerId: $editingLayerId,
                    actionFeedbackEnabled: actionFeedbackEnabled,
                    streamOverlayEnabled: streamOverlayEnabled
                )

                InputLogView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        }

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
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .clipped()

            // Mapped Chords Display
            if isSectionVisible(.activeChords) {
                removableSection(.activeChords) {
                    ActiveChordsView(editingChord: $editingChord)
                }
            }

            // Mapped Sequences Display
            if isSectionVisible(.activeSequences) {
                removableSection(.activeSequences) {
                    ActiveSequencesView(editingSequence: $editingSequence)
                }
            }
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
				if let activator = layer.activatorButton,
				   activeButtonsContain(activator, in: activeButtons) {
                    selectedLayerId = layer.id
                    return
                }
            }

            // No layer activator held - return to base layer
            selectedLayerId = nil
        }
    }

    // MARK: - Swap Mode

	private func activeButtonsContain(
		_ button: ControllerButton,
		in activeButtons: Set<ControllerButton>
	) -> Bool {
		activeButtons.contains(button) ||
			button.physicalEquivalentButtons.contains { activeButtons.contains($0) }
	}

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

    @ViewBuilder
    private func removableSection<Content: View>(
        _ section: ButtonMappingsTabSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .overlay(alignment: .topTrailing) {
                Button {
                    hideSection(section)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.secondary)
                        .background(.regularMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("Hide \(section.label)")
                .padding(.top, 6)
                .padding(.trailing, 8)
            }
    }

    private func hideSection(_ section: ButtonMappingsTabSection) {
        var currentHiddenSections = hiddenSections
        currentHiddenSections.insert(section)
        hiddenSectionTags = ButtonMappingsTabSection.encodedHiddenSections(currentHiddenSections)
    }
}

enum ButtonMappingsTabSection: Int, CaseIterable, Identifiable {
    case activeChords = 3
    case activeSequences = 4

    static let hiddenDefaultsKey = "hiddenButtonMappingsTabSectionTags"

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .activeChords: return "Active Chords"
        case .activeSequences: return "Active Sequences"
        }
    }

    static func hiddenSections(from rawValue: String) -> Set<ButtonMappingsTabSection> {
        Set(rawValue
            .split(separator: ",")
            .compactMap { Int(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .compactMap(ButtonMappingsTabSection.init(rawValue:))
        )
    }

    static func encodedHiddenSections(_ sections: Set<ButtonMappingsTabSection>) -> String {
        sections
            .map(\.rawValue)
            .sorted()
            .map { String($0) }
            .joined(separator: ",")
    }
}
