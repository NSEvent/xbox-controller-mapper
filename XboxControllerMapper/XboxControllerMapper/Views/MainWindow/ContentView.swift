import SwiftUI
import UniformTypeIdentifiers

/// Main window content view
struct ContentView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var appMonitor: AppMonitor
    @EnvironmentObject var mappingEngine: MappingEngine
    @EnvironmentObject var inputLogService: InputLogService
    @EnvironmentObject var usageStatsService: UsageStatsService
    @State private var selectedButton: ControllerButton?
    @State private var configuringButton: ControllerButton?
    @State private var showingChordSheet = false
    @State private var editingChord: ChordMapping?
    @State private var showingSequenceSheet = false
    @State private var editingSequence: SequenceMapping?
    @State private var showingSettingsSheet = false
    @State private var selectedTab = 0
    @State private var lastScale: CGFloat = 1.0 // Track last scale for gesture
    @State private var isMagnifying = false // Track active magnification to prevent tap conflicts
    @State private var selectedLayerId: UUID? = nil // nil = base layer
    @State private var showingAddLayerSheet = false
    @State private var editingLayerId: UUID? = nil
    @State private var actionFeedbackEnabled: Bool = ActionFeedbackIndicator.isEnabled
    @State private var streamOverlayEnabled: Bool = StreamOverlayManager.isEnabled
    @State private var isSwapMode: Bool = false
    @State private var swapFirstButton: ControllerButton? = nil
    var body: some View {
        HSplitView {
            // Sidebar: Profile management
            ProfileSidebar()
                .frame(minWidth: 200, maxWidth: 260)
                .background(Color.black.opacity(0.2)) // Subtle darkening for sidebar

            // Main content
            VStack(spacing: 0) {
                // Toolbar
                toolbar
                    .zIndex(1) // Keep above content

                // Tab content
                TabView(selection: $selectedTab) {
                    // Controller Visual
                    controllerTab
                        .tabItem { Text("Buttons") }
                        .tag(0)

                    // Chords
                    chordsTab
                        .tabItem { Text("Chords") }
                        .tag(1)

                    // Sequences
                    sequencesTab
                        .tabItem { Text("Sequences") }
                        .tag(9)

                    // Macros Tab
                    macroListTab
                        .tabItem { Text("Macros") }
                        .tag(7)

                    // Scripts Tab
                    scriptListTab
                        .tabItem { Text("Scripts") }
                        .tag(10)

                    // On-Screen Keyboard Settings
                    keyboardSettingsTab
                        .tabItem { Text("Keyboard") }
                        .tag(3)

                    // Joystick Settings
                    joystickSettingsTab
                        .tabItem { Text("Joysticks") }
                        .tag(2)

                    // Touchpad Settings (only shown when controller has touchpad - DualSense/DualShock)
                    if controllerService.threadSafeIsPlayStation {
                        touchpadSettingsTab
                            .tabItem { Text("Touchpad") }
                            .tag(4)
                    }

                    // LED Settings (only shown for DualSense - DualShock LED control not supported)
                    if controllerService.threadSafeIsDualSense {
                        ledSettingsTab
                            .tabItem { Text("LEDs") }
                            .tag(5)
                    }

                    // Microphone Settings (only shown for DualSense)
                    if controllerService.threadSafeIsDualSense {
                        microphoneSettingsTab
                            .tabItem { Text("Microphone") }
                            .tag(6)
                    }

                    // Stats
                    StatsView()
                        .tabItem { Text("Stats") }
                        .tag(8)
                }
                .tabViewStyle(.automatic)
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        // Global Glass Background
        .background(
            ZStack {
                Color.black.opacity(0.92) // Dark tint
                GlassVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            }
            .ignoresSafeArea()
        )
        .sheet(item: $configuringButton) { button in
            ButtonMappingSheet(
                button: button,
                mapping: Binding(
                    get: {
                        // Get mapping from layer if editing a layer, otherwise from base
                        if let layerId = selectedLayerId,
                           let layer = profileManager.activeProfile?.layers.first(where: { $0.id == layerId }) {
                            return layer.buttonMappings[button]
                        }
                        return profileManager.activeProfile?.buttonMappings[button]
                    },
                    set: { _ in } // Read-only: ButtonMappingSheet saves directly via ProfileManager (see saveMapping())
                ),
                isDualSense: controllerService.threadSafeIsPlayStation,
                selectedLayerId: selectedLayerId
            )
        }
        .sheet(isPresented: $showingChordSheet) {
            ChordMappingSheet()
        }
        .sheet(item: $editingChord) { chord in
            ChordMappingSheet(editingChord: chord)
        }
        .sheet(isPresented: $showingSequenceSheet) {
            SequenceMappingSheet()
        }
        .sheet(item: $editingSequence) { sequence in
            SequenceMappingSheet(editingSequence: sequence)
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsSheet()
        }
        // Add keyboard shortcuts for scaling
        .background(
            Button("Zoom In") { profileManager.setUiScale(min(profileManager.uiScale + 0.1, 2.0)) }
                .keyboardShortcut("+", modifiers: .command)
                .hidden()
        )
        .background(
            Button("Zoom Out") { profileManager.setUiScale(max(profileManager.uiScale - 0.1, 0.5)) }
                .keyboardShortcut("-", modifiers: .command)
                .hidden()
        )
        .background(
            Button("Reset Zoom") { profileManager.setUiScale(1.0) }
                .keyboardShortcut("0", modifiers: .command)
                .hidden()
        )
        .highPriorityGesture(
            MagnificationGesture()
                .onChanged { value in
                    isMagnifying = true
                    let delta = value / lastScale
                    lastScale = value
                    profileManager.uiScale = min(max(profileManager.uiScale * delta, 0.5), 2.0)
                }
                .onEnded { _ in
                    lastScale = 1.0
                    profileManager.setUiScale(profileManager.uiScale)
                    // Delay resetting isMagnifying to prevent tap events that fire at gesture end
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isMagnifying = false
                    }
                }
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            // Connection status
            HStack(spacing: 8) {
                Circle()
                    .fill(controllerService.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: (controllerService.isConnected ? Color.green : Color.red).opacity(0.6), radius: 4)

                Text(controllerService.isConnected ? controllerService.controllerName : "No Controller")
                    .font(.caption.bold())
                    .foregroundColor(controllerService.isConnected ? .white : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

            Spacer()

            Spacer()

            // Enable/disable toggle
            MappingActiveToggle(isEnabled: $mappingEngine.isEnabled)

            Button {
                showingSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .hoverableIconButton()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Transparent toolbar to let glass show through
    }

    // MARK: - Controller Tab

    private var controllerTab: some View {
        VStack(spacing: 0) {
            InputLogView()
                .padding(.top, 8)

            // Layer Tab Bar
            layerTabBar
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
            if let profile = profileManager.activeProfile, !profile.chordMappings.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.1))

                VStack(alignment: .leading, spacing: 12) {
                    Text("ACTIVE CHORDS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    FlowLayout(data: profile.chordMappings, spacing: 10) { chord in
                        HStack(spacing: 10) {
                            HStack(spacing: 2) {
                                ForEach(Array(chord.buttons).sorted(by: { $0.category.chordDisplayOrder < $1.category.chordDisplayOrder }), id: \.self) { button in
                                    ButtonIconView(button: button, isDualSense: controllerService.threadSafeIsPlayStation)
                                }
                            }

                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.3))

                            if let systemCommand = chord.systemCommand {
                                Text(chord.hint ?? systemCommand.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                                    .lineLimit(1)
                                    .tooltipIfPresent(chord.hint != nil ? systemCommand.displayName : nil)
                            } else if let macroId = chord.macroId,
                               let macro = profile.macros.first(where: { $0.id == macroId }) {
                                Text(chord.hint ?? macro.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.purple)
                                    .lineLimit(1)
                                    .tooltipIfPresent(chord.hint != nil ? macro.name : nil)
                            } else {
                                Text(chord.hint ?? chord.actionDisplayString)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .tooltipIfPresent(chord.hint != nil ? chord.actionDisplayString : nil)
                            }
                        }
                        .frame(minHeight: 28)  // Consistent height regardless of button types
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .cornerRadius(10)
                        .hoverableGlassRow {
                            editingChord = chord
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                .padding(.top, 12)
            }

            // Mapped Sequences Display
            if let profile = profileManager.activeProfile, !profile.sequenceMappings.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.1))

                VStack(alignment: .leading, spacing: 12) {
                    Text("ACTIVE SEQUENCES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    FlowLayout(data: profile.sequenceMappings.filter { $0.isValid }, spacing: 10) { sequence in
                        HStack(spacing: 10) {
                            HStack(spacing: 2) {
                                ForEach(Array(sequence.steps.enumerated()), id: \.offset) { index, button in
                                    if index > 0 {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 7))
                                            .foregroundColor(.white.opacity(0.2))
                                    }
                                    ButtonIconView(button: button, isDualSense: controllerService.threadSafeIsPlayStation)
                                }
                            }

                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.3))

                            if let systemCommand = sequence.systemCommand {
                                Text(sequence.hint ?? systemCommand.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                                    .lineLimit(1)
                                    .tooltipIfPresent(sequence.hint != nil ? systemCommand.displayName : nil)
                            } else if let macroId = sequence.macroId,
                               let macro = profile.macros.first(where: { $0.id == macroId }) {
                                Text(sequence.hint ?? macro.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.purple)
                                    .lineLimit(1)
                                    .tooltipIfPresent(sequence.hint != nil ? macro.name : nil)
                            } else {
                                Text(sequence.hint ?? sequence.actionDisplayString)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .tooltipIfPresent(sequence.hint != nil ? sequence.actionDisplayString : nil)
                            }
                        }
                        .frame(minHeight: 28)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .cornerRadius(10)
                        .hoverableGlassRow {
                            editingSequence = sequence
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                .padding(.top, 12)
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
                if let activator = layer.activatorButton, activeButtons.contains(activator) {
                    selectedLayerId = layer.id
                    return
                }
            }

            // No layer activator held - return to base layer
            selectedLayerId = nil
        }
    }

    // MARK: - Layer Tab Bar

    private var layerTabBar: some View {
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
            Toggle(isOn: $actionFeedbackEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 10))
                    Text("Cursor Hints")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(actionFeedbackEnabled ? Color.accentColor : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundColor(actionFeedbackEnabled ? .white : .secondary)
            .hoverableButton()
            .onChange(of: actionFeedbackEnabled) { _, newValue in
                ActionFeedbackIndicator.isEnabled = newValue
            }

            // Stream overlay toggle
            Toggle(isOn: $streamOverlayEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 10))
                    Text("Stream")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(streamOverlayEnabled ? Color.purple : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundColor(streamOverlayEnabled ? .white : .secondary)
            .hoverableButton()
            .onChange(of: streamOverlayEnabled) { _, newValue in
                if newValue {
                    StreamOverlayManager.shared.show(
                        controllerService: controllerService,
                        inputLogService: inputLogService
                    )
                } else {
                    StreamOverlayManager.shared.hide()
                }
            }
        }
    }

    // MARK: - Chords Tab

    private var chordsTab: some View {
        Form {
            Section {
                Button(action: { showingChordSheet = true }) {
                    Label("Add New Chord", systemImage: "plus")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)

                if let profile = profileManager.activeProfile, !profile.chordMappings.isEmpty {
                    ChordListView(
                        chords: profile.chordMappings,
                        isDualSense: controllerService.threadSafeIsPlayStation,
                        onEdit: { chord in
                            editingChord = chord
                        },
                        onDelete: { chord in
                            profileManager.removeChord(chord)
                        },
                        onMove: { source, destination in
                            profileManager.moveChords(from: source, to: destination)
                        }
                    )
                    .equatable()
                } else {
                    Text("No chords configured")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                }
            } header: {
                Text("Chord Mappings")
                    .foregroundColor(.secondary)
            } footer: {
                Text("Chords let you map multiple button presses to a single action.")
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }

    // MARK: - Sequences Tab

    private var sequencesTab: some View {
        Form {
            Section {
                Button(action: { showingSequenceSheet = true }) {
                    Label("Add New Sequence", systemImage: "plus")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)

                if let profile = profileManager.activeProfile, !profile.sequenceMappings.isEmpty {
                    SequenceListView(
                        sequences: profile.sequenceMappings,
                        isDualSense: controllerService.threadSafeIsPlayStation,
                        onEdit: { sequence in
                            editingSequence = sequence
                        },
                        onDelete: { sequence in
                            profileManager.removeSequence(sequence)
                        },
                        onMove: { source, destination in
                            profileManager.moveSequences(from: source, to: destination)
                        }
                    )
                    .equatable()
                } else {
                    Text("No sequences configured")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                }
            } header: {
                Text("Sequence Mappings")
                    .foregroundColor(.secondary)
            } footer: {
                Text("Sequences fire an extra action when buttons are pressed in order within a time window. Individual button actions still fire normally (zero added latency).")
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }

    // MARK: - Joystick Settings Tab

    private var joystickSettingsTab: some View {
        JoystickSettingsView()
            .scrollContentBackground(.hidden)
    }

    // MARK: - Touchpad Settings Tab

    private var touchpadSettingsTab: some View {
        TouchpadSettingsView()
            .scrollContentBackground(.hidden)
    }

    // MARK: - LED Settings Tab

    private var ledSettingsTab: some View {
        LEDSettingsView()
            .scrollContentBackground(.hidden)
    }

    // MARK: - Microphone Settings Tab

    private var microphoneSettingsTab: some View {
        MicrophoneSettingsView()
            .scrollContentBackground(.hidden)
    }

    private var keyboardSettingsTab: some View {
        OnScreenKeyboardSettingsView()
            .scrollContentBackground(.hidden)
    }

    // MARK: - Macro List Tab

    private var macroListTab: some View {
        MacroListView()
            .scrollContentBackground(.hidden)
    }

    // MARK: - Script List Tab

    private var scriptListTab: some View {
        ScriptListView()
            .scrollContentBackground(.hidden)
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

// MARK: - Mapping Active Toggle

struct MappingActiveToggle: View {
    @Binding var isEnabled: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(isEnabled ? "MAPPING ACTIVE" : "DISABLED")
                .font(.caption.bold())
                .foregroundColor(isEnabled ? .accentColor : .secondary)

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isEnabled.toggle()
        }
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

// MARK: - Legend Item

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.5), radius: 2)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Glass Aesthetic Components

/// A view that wraps NSVisualEffectView for SwiftUI
struct GlassVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// A standardized glass tile background for cards and rows
struct GlassCardBackground: View {
    var isActive: Bool = false
    var isHovered: Bool = false
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            if isActive {
                Color.accentColor.opacity(0.2)
            } else if isHovered {
                Color.accentColor.opacity(0.08)
            } else {
                Color.black.opacity(0.4)
            }

            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderColor, lineWidth: isActive ? 1.5 : 1)
        }
        .cornerRadius(cornerRadius)
        .shadow(color: isActive ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.2), radius: isActive ? 8 : 4)
    }

    private var borderColor: Color {
        if isActive { return Color.accentColor.opacity(0.8) }
        if isHovered { return Color.white.opacity(0.3) }
        return Color.white.opacity(0.1)
    }
}

// MARK: - UUID Identifiable Extension

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

#Preview {
    let controllerService = ControllerService()
    let profileManager = ProfileManager()
    let appMonitor = AppMonitor()
    let inputLogService = InputLogService()
    let mappingEngine = MappingEngine(
        controllerService: controllerService,
        profileManager: profileManager,
        appMonitor: appMonitor,
        inputLogService: inputLogService
    )

    return ContentView()
        .environmentObject(controllerService)
        .environmentObject(profileManager)
        .environmentObject(appMonitor)
        .environmentObject(mappingEngine)
        .environmentObject(inputLogService)
}
