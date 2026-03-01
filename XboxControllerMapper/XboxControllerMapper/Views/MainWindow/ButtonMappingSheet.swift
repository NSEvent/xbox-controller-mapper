import SwiftUI
import AppKit

/// Sheet for configuring a button mapping
struct ButtonMappingSheet: View {
    let button: ControllerButton
    @Binding var mapping: KeyMapping?
    var isDualSense: Bool = false
    var selectedLayerId: UUID? = nil  // nil = editing base layer

    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var appMonitor: AppMonitor

    @Environment(\.dismiss) private var dismiss

    // MARK: - Per-variant editing state (replaces ~60 individual @State vars)

    @State private var primaryState = MappingEditorState()
    @State private var longHoldState = MappingEditorState()
    @State private var doubleTapState = MappingEditorState()

    // MARK: - Sheet-level state

    @State private var isHoldModifier = false
    @State private var enableLongHold = false
    @State private var longHoldThreshold: Double = 0.5
    @State private var enableDoubleTap = false
    @State private var doubleTapThreshold: Double = 0.4
    @State private var enableRepeat = false
    @State private var repeatRate: Double = 5.0  // Actions per second

    // Track if user manually overrode the hold setting
    @State private var userHasInteractedWithHold = false

    // Prevent auto-logic from running during initial load
    @State private var isLoading = true

    // Layer activator support
    @State private var isLayerActivator = false
    @State private var layerName: String = ""
    @State private var existingLayerId: UUID? = nil  // Tracks if editing existing layer (already has this button as activator)
    @State private var selectedExistingLayerId: UUID? = nil  // For assigning this button to an existing unassigned layer
    @State private var createNewLayer = true  // true = create new, false = use existing unassigned layer

    private var showingAnyKeyboard: Bool {
        primaryState.showingKeyboard || longHoldState.showingKeyboard || doubleTapState.showingKeyboard
    }

    /// Check if the primary action is a mouse click - disables double tap/long hold
    private var primaryIsMouseClick: Bool {
        guard let code = primaryState.keyCode else { return false }
        return KeyCodeMapping.isMouseButton(code)
    }

    /// Check if the primary action is on-screen keyboard - disables double tap/long hold/repeat
    private var primaryIsOnScreenKeyboard: Bool {
        guard let code = primaryState.keyCode else { return false }
        return KeyCodeMapping.isSpecialAction(code)
    }

    /// Check if the primary action disables advanced features (mouse click or special action)
    private var primaryDisablesAdvancedFeatures: Bool {
        primaryIsMouseClick || primaryIsOnScreenKeyboard
    }

    /// Whether this button is already a layer activator
    private var existingLayer: Layer? {
        profileManager.layerForActivator(button)
    }

    /// Whether max layers have been reached (and this button isn't already an activator)
    private var canCreateNewLayer: Bool {
        guard let profile = profileManager.activeProfile else { return false }
        return profile.layers.count < ProfileManager.maxLayers || existingLayer != nil
    }

    /// Layers that don't have an activator button assigned
    private var unassignedLayers: [Layer] {
        profileManager.unassignedLayers()
    }

    /// Whether we're editing a layer mapping (vs base layer)
    private var isEditingLayer: Bool {
        selectedLayerId != nil
    }

    /// Whether this button is a layer activator (in the base layer)
    /// Layer activators cannot be mapped to actions in any layer
    private var isBaseLayerActivator: Bool {
        profileManager.layerForActivator(button) != nil
    }

    /// The layer we're editing, if any
    private var editingLayer: Layer? {
        guard let layerId = selectedLayerId,
              let profile = profileManager.activeProfile else { return nil }
        return profile.layers.first(where: { $0.id == layerId })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Layer context indicator when editing a layer
                    if let layer = editingLayer {
                        HStack(spacing: 8) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundColor(.purple)
                            Text("Editing layer: \(layer.name)")
                                .font(.subheadline)
                                .foregroundColor(.purple)
                            Spacer()
                            Text("Unmapped buttons fall through to base layer")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // Show warning if this button is a layer activator and we're editing a layer
                    if isEditingLayer && isBaseLayerActivator {
                        if let activatorLayer = profileManager.layerForActivator(button) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .foregroundColor(.purple)
                                    Text("Layer Activator")
                                        .font(.headline)
                                }
                                Text("This button activates the \"\(activatorLayer.name)\" layer. Layer activators cannot have additional mappings - they are reserved for switching between layers.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)
                        }
                    } else {
                        // Only show mapping sections if not a layer activator
                        if !isLayerActivator {
                            primaryMappingSection
                            longHoldSection
                            doubleTapSection
                        }

                        // Layer activator section at the bottom (only show when editing base layer, not layer mappings)
                        if !isEditingLayer && canCreateNewLayer {
                            layerActivatorSection
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer
            footer
        }
        .onSubmit { saveMapping() }
        .frame(width: showingAnyKeyboard ? 750 : (primaryState.mappingType == .systemCommand ? 580 : 520), height: showingAnyKeyboard ? 700 : 550)
        .animation(.easeInOut(duration: 0.2), value: primaryState.showingKeyboard)
        .animation(.easeInOut(duration: 0.2), value: longHoldState.showingKeyboard)
        .animation(.easeInOut(duration: 0.2), value: doubleTapState.showingKeyboard)
        .animation(.easeInOut(duration: 0.2), value: primaryState.mappingType)
        .onAppear {
            loadCurrentMapping()
            // Initialize selectedExistingLayerId if there are unassigned layers
            if let firstUnassigned = unassignedLayers.first {
                selectedExistingLayerId = firstUnassigned.id
            }
            // Allow state updates to settle before enabling auto-logic
            Task { @MainActor in
                isLoading = false
            }
        }
        .sheet(isPresented: $primaryState.showingMacroCreation) {
            MacroEditorSheet(macro: nil, onSave: { newMacro in
                primaryState.selectedMacroId = newMacro.id
            })
        }
        .sheet(isPresented: $longHoldState.showingMacroCreation) {
            MacroEditorSheet(macro: nil, onSave: { newMacro in
                longHoldState.selectedMacroId = newMacro.id
            })
        }
        .sheet(isPresented: $doubleTapState.showingMacroCreation) {
            MacroEditorSheet(macro: nil, onSave: { newMacro in
                doubleTapState.selectedMacroId = newMacro.id
            })
        }
        .sheet(isPresented: $primaryState.showingScriptCreation) {
            ScriptEditorSheet(script: nil, onSave: { newScript in
                primaryState.selectedScriptId = newScript.id
            })
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            ButtonIconView(button: button, isPressed: false, isDualSense: isDualSense)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Configure \(button.displayName(forDualSense: isDualSense))")
                    .font(.headline)

                if let currentMapping = mapping {
                    HStack(spacing: 4) {
                        Text("Current:")

                        if let macroId = currentMapping.macroId,
                           let profile = profileManager.activeProfile,
                           let macro = profile.macros.first(where: { $0.id == macroId }) {
                            Text("Macro: \(macro.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let scriptId = currentMapping.scriptId,
                                  let profile = profileManager.activeProfile,
                                  let script = profile.scripts.first(where: { $0.id == scriptId }) {
                            Text("Script: \(script.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            MappingLabelView(
                                mapping: currentMapping,
                                horizontal: true,
                                font: .caption,
                                foregroundColor: .secondary
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    Text("No mapping configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Primary Mapping Section

    private var primaryMappingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Primary Action")
                    .font(.headline)

                Spacer()

                Picker("", selection: $primaryState.mappingType) {
                    Text("Key").tag(MappingEditorState.MappingType.singleKey)
                    Text("Macro").tag(MappingEditorState.MappingType.macro)
                    Text("Script").tag(MappingEditorState.MappingType.script)
                    Text("System").tag(MappingEditorState.MappingType.systemCommand)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .padding(.trailing, 8)

                if primaryState.mappingType == .singleKey {
                    Button(action: { primaryState.showingKeyboard.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: primaryState.showingKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                            Text(primaryState.showingKeyboard ? "Hide Keyboard" : "Show Keyboard")
                        }
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if primaryState.mappingType == .singleKey {
                    ActionMappingEditor(state: $primaryState, variant: .primary)

                    // Show hold option if any mapping is configured
                    if primaryState.keyCode != nil || primaryState.modifiers.hasAny {
                        Divider()

                        Toggle("Hold action while button is held", isOn: Binding(
                            get: { isHoldModifier },
                            set: { newValue in
                                isHoldModifier = newValue
                                userHasInteractedWithHold = true
                                // Disable repeat and long hold when enabling hold modifier (mutually exclusive)
                                if newValue {
                                    enableRepeat = false
                                    enableLongHold = false
                                    longHoldState.keyCode = nil
                                    longHoldState.modifiers = ModifierFlags()
                                }
                            }
                        ))
                        .font(.caption)
                        .disabled(enableRepeat)

                        Text(holdDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Repeat section (moved inside Primary Action)
                        repeatContent
                    }
                } else {
                    ActionMappingEditor(state: $primaryState, variant: .primary)
                }
            }
            .onChange(of: primaryState.keyCode) { _, newValue in
                guard !isLoading else { return }

                if let code = newValue, KeyCodeMapping.isMouseButton(code) || KeyCodeMapping.isSpecialAction(code) {
                    // Mouse clicks and special actions: auto-enable hold and disable long hold/double tap/repeat
                    // Exception: laser pointer defaults to toggle mode (isHoldModifier = false)
                    if !userHasInteractedWithHold {
                        isHoldModifier = code != KeyCodeMapping.showLaserPointer
                    }
                    // Clear long hold, double tap, and repeat
                    enableLongHold = false
                    enableDoubleTap = false
                    enableRepeat = false
                    longHoldState.keyCode = nil
                    longHoldState.modifiers = ModifierFlags()
                    doubleTapState.keyCode = nil
                    doubleTapState.modifiers = ModifierFlags()
                } else if !userHasInteractedWithHold {
                    if newValue != nil {
                        // Auto-disable hold modifier for regular keys
                        isHoldModifier = false
                    } else if primaryState.modifiers.hasAny {
                        // Auto-enable hold modifier for modifier-only mappings
                        isHoldModifier = true
                    }
                }
            }
            .onChange(of: primaryState.modifiers) { _, newValue in
                guard !isLoading else { return }
                guard !userHasInteractedWithHold else { return }

                if primaryState.keyCode == nil && newValue.hasAny {
                    // Auto-enable hold for modifier-only mappings
                    isHoldModifier = true
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var holdDescription: String {
        if let code = primaryState.keyCode, KeyCodeMapping.isMouseButton(code) {
            return "When enabled, the mouse button stays pressed for dragging"
        } else if primaryState.keyCode == nil && primaryState.modifiers.hasAny {
            return "When enabled, the modifier stays pressed while the button is held"
        } else {
            return "When enabled, the key action stays active while the button is held"
        }
    }

    // MARK: - Layer Activator Section

    private var layerActivatorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $isLayerActivator) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundColor(.purple)
                    Text("Use as Layer Activator")
                        .font(.headline)
                }
            }
            .toggleStyle(.switch)

            if isLayerActivator {
                VStack(alignment: .leading, spacing: 8) {
                    // If this button already activates a layer, just show name editor
                    if existingLayerId != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Layer Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("e.g., Combat Mode, Navigation", text: $layerName)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        // Show option to create new or select existing unassigned layer
                        if !unassignedLayers.isEmpty {
                            Picker("", selection: $createNewLayer) {
                                Text("Create New Layer").tag(true)
                                Text("Use Existing Layer").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        if createNewLayer || unassignedLayers.isEmpty {
                            // Create new layer
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Layer Name")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("e.g., Combat Mode, Navigation", text: $layerName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        } else {
                            // Select existing unassigned layer
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Select Layer")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Picker("Layer", selection: $selectedExistingLayerId) {
                                    ForEach(unassignedLayers) { layer in
                                        Text(layer.name).tag(layer.id as UUID?)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.purple.opacity(0.7))
                        Text("When this button is held, the layer's alternate button mappings become active. Other buttons not mapped in the layer fall through to the base layer.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
            } else if existingLayer != nil {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue.opacity(0.7))
                    Text("This button currently activates a layer. Disabling will unassign the button but keep the layer.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Long Hold Section

    /// Whether long hold should be disabled (mouse click, special action, or hold modifier enabled)
    private var longHoldDisabled: Bool {
        primaryDisablesAdvancedFeatures || (primaryState.mappingType == .singleKey && (isHoldModifier || enableRepeat))
    }

    private var longHoldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Enable Long Hold Action", isOn: $enableLongHold)
                    .font(.headline)
                    .disabled(longHoldDisabled)

                Spacer()

                if enableLongHold && !longHoldDisabled && longHoldState.mappingType == .singleKey {
                    Button(action: { longHoldState.showingKeyboard.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: longHoldState.showingKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                            Text(longHoldState.showingKeyboard ? "Hide" : "Show Keyboard")
                        }
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            if primaryDisablesAdvancedFeatures {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Long hold is not available for \(primaryIsMouseClick ? "mouse clicks" : "special actions").")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else if primaryState.mappingType == .singleKey && isHoldModifier {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Long hold is not available when \"Hold action\" is enabled.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else if primaryState.mappingType == .singleKey && enableRepeat {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Long hold is not available when \"Repeat Action\" is enabled.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else if enableLongHold {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Hold Duration:")
                            .font(.subheadline)

                        Slider(value: $longHoldThreshold, in: 0.2...2.0, step: 0.1)

                        Text("\(longHoldThreshold, specifier: "%.1f")s")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40)
                    }

                    Picker("", selection: $longHoldState.mappingType) {
                        Text("Key").tag(MappingEditorState.MappingType.singleKey)
                        Text("Macro").tag(MappingEditorState.MappingType.macro)
                        Text("System").tag(MappingEditorState.MappingType.systemCommand)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    ActionMappingEditor(state: $longHoldState, variant: .longHold)

                    HStack {
                        Text("Hint:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("e.g. Copy, Paste, Switch App...", text: $longHoldState.hint)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                    }

                    HapticStylePicker(hapticStyle: $longHoldState.hapticStyle)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Double Tap Section

    private var doubleTapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Enable Double Tap Action", isOn: $enableDoubleTap)
                    .font(.headline)
                    .disabled(primaryDisablesAdvancedFeatures)

                Spacer()

                if enableDoubleTap && !primaryDisablesAdvancedFeatures && doubleTapState.mappingType == .singleKey {
                    Button(action: { doubleTapState.showingKeyboard.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: doubleTapState.showingKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                            Text(doubleTapState.showingKeyboard ? "Hide" : "Show Keyboard")
                        }
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            if primaryDisablesAdvancedFeatures {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text(primaryIsMouseClick
                         ? "Double tap is not available when the primary action is a mouse click. Press the button twice quickly to double-click, or three times for triple-click."
                         : "Double tap is not available for special actions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else if enableDoubleTap {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tap Window:")
                            .font(.subheadline)

                        Slider(value: $doubleTapThreshold, in: 0.2...0.6, step: 0.05)

                        Text("\(doubleTapThreshold, specifier: "%.2f")s")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 45)
                    }

                    Text("Two taps within this time window trigger the double-tap action")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: $doubleTapState.mappingType) {
                        Text("Key").tag(MappingEditorState.MappingType.singleKey)
                        Text("Macro").tag(MappingEditorState.MappingType.macro)
                        Text("System").tag(MappingEditorState.MappingType.systemCommand)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    ActionMappingEditor(state: $doubleTapState, variant: .doubleTap)

                    HStack {
                        Text("Hint:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("e.g. Copy, Paste, Switch App...", text: $doubleTapState.hint)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                    }

                    HapticStylePicker(hapticStyle: $doubleTapState.hapticStyle)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Repeat Content

    @ViewBuilder
    private var repeatContent: some View {
        Divider()
            .padding(.vertical, 4)

        Toggle("Repeat Action While Held", isOn: Binding(
            get: { enableRepeat },
            set: { newValue in
                enableRepeat = newValue
                // Disable hold modifier when enabling repeat (mutually exclusive)
                if newValue {
                    isHoldModifier = false
                    enableLongHold = false
                    longHoldState.keyCode = nil
                    longHoldState.modifiers = ModifierFlags()
                    userHasInteractedWithHold = true
                }
            }
        ))
        .font(.caption)
        .disabled(primaryDisablesAdvancedFeatures || isHoldModifier)

        if primaryDisablesAdvancedFeatures {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Repeat is not available for \(primaryIsMouseClick ? "mouse clicks" : "special actions").")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if isHoldModifier {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Repeat is not available when \"Hold action\" is enabled.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if enableRepeat {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Repeat Rate:")
                        .font(.caption)

                    Slider(value: $repeatRate, in: 5...50, step: 1)

                    Text("\(Int(repeatRate))/s")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 35)
                }

                Text("The action will be triggered \(Int(repeatRate)) times per second while the button is held")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Don't show Clear/Save when editing a layer activator in a layer context
            if isEditingLayer && isBaseLayerActivator {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button("Clear Mapping") {
                    clearMapping()
                }
                .foregroundColor(.red)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveMapping()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    // MARK: - Actions

    private func loadCurrentMapping() {
        guard let profile = profileManager.activeProfile else { return }

        // If editing a layer, don't show layer activator option
        // (that's only for base layer)
        if !isEditingLayer {
            // Check if this button is a layer activator
            if let layer = profile.layers.first(where: { $0.activatorButton == button }) {
                isLayerActivator = true
                layerName = layer.name
                existingLayerId = layer.id
                return  // Layer activators don't have regular mappings
            }
        }

        // Get the mapping from the appropriate source
        let existingMapping: KeyMapping?
        if let layer = editingLayer {
            existingMapping = layer.buttonMappings[button]
        } else {
            existingMapping = profile.buttonMappings[button]
        }

        if let existingMapping = existingMapping {
            primaryState.hint = existingMapping.hint ?? ""
            primaryState.hapticStyle = existingMapping.hapticStyle

            if let systemCommand = existingMapping.systemCommand {
                primaryState.mappingType = .systemCommand
                primaryState.loadSystemCommand(systemCommand)
            } else if let macroId = existingMapping.macroId {
                primaryState.mappingType = .macro
                primaryState.selectedMacroId = macroId
            } else if let scriptId = existingMapping.scriptId {
                primaryState.mappingType = .script
                primaryState.selectedScriptId = scriptId
            } else {
                primaryState.mappingType = .singleKey
                primaryState.keyCode = existingMapping.keyCode
                primaryState.modifiers = existingMapping.modifiers
                isHoldModifier = existingMapping.isHoldModifier
            }

            // Long hold, double tap, and repeat apply to all primary mapping types
            if let longHold = existingMapping.longHoldMapping {
                enableLongHold = true
                longHoldThreshold = longHold.threshold
                longHoldState.hint = longHold.hint ?? ""
                longHoldState.hapticStyle = longHold.hapticStyle
                if let systemCommand = longHold.systemCommand {
                    longHoldState.mappingType = .systemCommand
                    longHoldState.loadSystemCommand(systemCommand)
                } else if let macroId = longHold.macroId {
                    longHoldState.mappingType = .macro
                    longHoldState.selectedMacroId = macroId
                } else {
                    longHoldState.mappingType = .singleKey
                    longHoldState.keyCode = longHold.keyCode
                    longHoldState.modifiers = longHold.modifiers
                }
            }

            if let doubleTap = existingMapping.doubleTapMapping {
                enableDoubleTap = true
                doubleTapThreshold = doubleTap.threshold
                doubleTapState.hint = doubleTap.hint ?? ""
                doubleTapState.hapticStyle = doubleTap.hapticStyle
                if let systemCommand = doubleTap.systemCommand {
                    doubleTapState.mappingType = .systemCommand
                    doubleTapState.loadSystemCommand(systemCommand)
                } else if let macroId = doubleTap.macroId {
                    doubleTapState.mappingType = .macro
                    doubleTapState.selectedMacroId = macroId
                } else {
                    doubleTapState.mappingType = .singleKey
                    doubleTapState.keyCode = doubleTap.keyCode
                    doubleTapState.modifiers = doubleTap.modifiers
                }
            }

            if let repeatConfig = existingMapping.repeatMapping, repeatConfig.enabled {
                enableRepeat = true
                repeatRate = repeatConfig.ratePerSecond
            }
        }
    }

    private func saveMapping() {
        // Handle layer activator
        if isLayerActivator {
            if let existingId = existingLayerId,
               var layer = profileManager.activeProfile?.layers.first(where: { $0.id == existingId }) {
                // Update existing layer that this button already activates
                layer.name = layerName
                profileManager.updateLayer(layer)
            } else if !createNewLayer, let selectedId = selectedExistingLayerId,
                      let layer = profileManager.activeProfile?.layers.first(where: { $0.id == selectedId }) {
                // Assign this button to an existing unassigned layer
                _ = profileManager.setLayerActivator(layer, button: button)
            } else {
                // Create new layer
                guard !layerName.isEmpty else { return }
                _ = profileManager.createLayer(name: layerName, activatorButton: button)
            }
            // Clear any existing button mapping for this button
            profileManager.removeMapping(for: button)
            mapping = nil
            dismiss()
            return
        } else if let existingId = existingLayerId {
            // Was a layer activator, now isn't - just remove the activator button (keep the layer)
            if let layer = profileManager.activeProfile?.layers.first(where: { $0.id == existingId }) {
                _ = profileManager.setLayerActivator(layer, button: nil)
            }
        }

        var newMapping: KeyMapping

        if primaryState.mappingType == .systemCommand {
            guard let command = primaryState.buildSystemCommand() else { return }
            newMapping = KeyMapping(systemCommand: command, hint: primaryState.hint.isEmpty ? nil : primaryState.hint, hapticStyle: primaryState.hapticStyle)
        } else if primaryState.mappingType == .macro {
            guard let macroId = primaryState.selectedMacroId else { return }
            newMapping = KeyMapping(macroId: macroId, hint: primaryState.hint.isEmpty ? nil : primaryState.hint, hapticStyle: primaryState.hapticStyle)
        } else if primaryState.mappingType == .script {
            guard let scriptId = primaryState.selectedScriptId else { return }
            newMapping = KeyMapping(scriptId: scriptId, hint: primaryState.hint.isEmpty ? nil : primaryState.hint, hapticStyle: primaryState.hapticStyle)
        } else {
            newMapping = KeyMapping(
                keyCode: primaryState.keyCode,
                modifiers: primaryState.modifiers,
                isHoldModifier: isHoldModifier,
                hint: primaryState.hint.isEmpty ? nil : primaryState.hint,
                hapticStyle: primaryState.hapticStyle
            )

            if enableRepeat {
                newMapping.repeatMapping = RepeatMapping(
                    enabled: true,
                    interval: 1.0 / repeatRate
                )
            }
        }

        // Long hold and double tap apply to all primary mapping types
        if enableLongHold && !longHoldDisabled {
            let longHoldValid: Bool
            switch longHoldState.mappingType {
            case .singleKey:
                longHoldValid = longHoldState.keyCode != nil || longHoldState.modifiers.hasAny
            case .macro:
                longHoldValid = longHoldState.selectedMacroId != nil
            case .systemCommand:
                longHoldValid = longHoldState.buildSystemCommand() != nil
            case .script:
                longHoldValid = false
            }
            if longHoldValid {
                newMapping.longHoldMapping = LongHoldMapping(
                    keyCode: longHoldState.mappingType == .singleKey ? longHoldState.keyCode : nil,
                    modifiers: longHoldState.mappingType == .singleKey ? longHoldState.modifiers : ModifierFlags(),
                    threshold: longHoldThreshold,
                    macroId: longHoldState.mappingType == .macro ? longHoldState.selectedMacroId : nil,
                    systemCommand: longHoldState.mappingType == .systemCommand ? longHoldState.buildSystemCommand() : nil,
                    hint: longHoldState.hint.isEmpty ? nil : longHoldState.hint,
                    hapticStyle: longHoldState.hapticStyle
                )
            }
        }

        if enableDoubleTap && !primaryDisablesAdvancedFeatures {
            let doubleTapValid: Bool
            switch doubleTapState.mappingType {
            case .singleKey:
                doubleTapValid = doubleTapState.keyCode != nil || doubleTapState.modifiers.hasAny
            case .macro:
                doubleTapValid = doubleTapState.selectedMacroId != nil
            case .systemCommand:
                doubleTapValid = doubleTapState.buildSystemCommand() != nil
            case .script:
                doubleTapValid = false
            }
            if doubleTapValid {
                newMapping.doubleTapMapping = DoubleTapMapping(
                    keyCode: doubleTapState.mappingType == .singleKey ? doubleTapState.keyCode : nil,
                    modifiers: doubleTapState.mappingType == .singleKey ? doubleTapState.modifiers : ModifierFlags(),
                    threshold: doubleTapThreshold,
                    macroId: doubleTapState.mappingType == .macro ? doubleTapState.selectedMacroId : nil,
                    systemCommand: doubleTapState.mappingType == .systemCommand ? doubleTapState.buildSystemCommand() : nil,
                    hint: doubleTapState.hint.isEmpty ? nil : doubleTapState.hint,
                    hapticStyle: doubleTapState.hapticStyle
                )
            }
        }

        // Save to the appropriate place (layer or base)
        if let layer = editingLayer {
            profileManager.setLayerMapping(newMapping, for: button, in: layer)
        } else {
            profileManager.setMapping(newMapping, for: button)
        }

        mapping = newMapping
        dismiss()
    }

    private func clearMapping() {
        // If this was a layer activator, delete the layer
        if let existingId = existingLayerId,
           let layer = profileManager.activeProfile?.layers.first(where: { $0.id == existingId }) {
            profileManager.deleteLayer(layer)
        }

        // Clear from the appropriate place (layer or base)
        if let layer = editingLayer {
            profileManager.removeLayerMapping(for: button, from: layer)
        } else {
            profileManager.removeMapping(for: button)
        }

        mapping = nil
        dismiss()
    }
}

#Preview {
    ButtonMappingSheet(button: .a, mapping: .constant(nil))
        .environmentObject(ProfileManager())
        .environmentObject(AppMonitor())
}
