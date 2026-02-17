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

    // Local state for editing
    @State private var keyCode: CGKeyCode?
    @State private var modifiers = ModifierFlags()
    @State private var isHoldModifier = false

    @State private var enableLongHold = false
    @State private var longHoldKeyCode: CGKeyCode?
    @State private var longHoldModifiers = ModifierFlags()
    @State private var longHoldThreshold: Double = 0.5
    @State private var longHoldHint: String = ""

    @State private var enableDoubleTap = false
    @State private var doubleTapKeyCode: CGKeyCode?
    @State private var doubleTapModifiers = ModifierFlags()
    @State private var doubleTapThreshold: Double = 0.4
    @State private var doubleTapHint: String = ""

    @State private var enableRepeat = false
    @State private var repeatRate: Double = 5.0  // Actions per second

    // Track if user manually overrode the hold setting
    @State private var userHasInteractedWithHold = false
    
    // Prevent auto-logic from running during initial load
    @State private var isLoading = true

    // Hint
    @State private var hint: String = ""

    // Keyboard visual state
    @State private var showingKeyboardForPrimary = false
    @State private var showingKeyboardForLongHold = false
    @State private var showingKeyboardForDoubleTap = false

    // Macro support
    @State private var mappingType: MappingType = .singleKey
    @State private var selectedMacroId: UUID?

    // System command support
    @State private var systemCommandCategory: SystemCommandCategory = .shell
    @State private var appBundleIdentifier: String = ""
    @State private var appNewWindow: Bool = false
    @State private var shellCommandText: String = ""
    @State private var shellRunInTerminal: Bool = true
    @State private var linkURL: String = ""
    @State private var webhookURL: String = ""
    @State private var webhookMethod: HTTPMethod = .POST
    @State private var webhookBody: String = ""
    @State private var webhookHeaders: [String: String] = [:]
    @State private var newWebhookHeaderKey: String = ""
    @State private var newWebhookHeaderValue: String = ""
    @State private var showingPrimaryAppPicker = false
    @State private var showingLongHoldAppPicker = false
    @State private var showingDoubleTapAppPicker = false
    @State private var showingPrimaryBookmarkPicker = false
    @State private var showingLongHoldBookmarkPicker = false
    @State private var showingDoubleTapBookmarkPicker = false

    // Long hold type support
    @State private var longHoldMappingType: MappingType = .singleKey
    @State private var longHoldMacroId: UUID?
    @State private var longHoldSystemCommandCategory: SystemCommandCategory = .shell
    @State private var longHoldAppBundleIdentifier: String = ""
    @State private var longHoldAppNewWindow: Bool = false
    @State private var longHoldShellCommandText: String = ""
    @State private var longHoldShellRunInTerminal: Bool = true
    @State private var longHoldLinkURL: String = ""

    // Double tap type support
    @State private var doubleTapMappingType: MappingType = .singleKey
    @State private var doubleTapMacroId: UUID?
    @State private var doubleTapSystemCommandCategory: SystemCommandCategory = .shell
    @State private var doubleTapAppBundleIdentifier: String = ""
    @State private var doubleTapAppNewWindow: Bool = false
    @State private var doubleTapShellCommandText: String = ""
    @State private var doubleTapShellRunInTerminal: Bool = true
    @State private var doubleTapLinkURL: String = ""

    // Layer activator support
    @State private var isLayerActivator = false
    @State private var layerName: String = ""
    @State private var existingLayerId: UUID? = nil  // Tracks if editing existing layer (already has this button as activator)
    @State private var selectedExistingLayerId: UUID? = nil  // For assigning this button to an existing unassigned layer
    @State private var createNewLayer = true  // true = create new, false = use existing unassigned layer

    enum MappingType: Int {
        case singleKey = 0
        case macro = 1
        case systemCommand = 2
    }

    private var showingAnyKeyboard: Bool {
        showingKeyboardForPrimary || showingKeyboardForLongHold || showingKeyboardForDoubleTap
    }

    /// Check if the primary action is a mouse click - disables double tap/long hold
    private var primaryIsMouseClick: Bool {
        guard let code = keyCode else { return false }
        return KeyCodeMapping.isMouseButton(code)
    }

    /// Check if the primary action is on-screen keyboard - disables double tap/long hold/repeat
    private var primaryIsOnScreenKeyboard: Bool {
        guard let code = keyCode else { return false }
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
        .frame(width: showingAnyKeyboard ? 750 : 500, height: showingAnyKeyboard ? 700 : 550)
        .animation(.easeInOut(duration: 0.2), value: showingKeyboardForPrimary)
        .animation(.easeInOut(duration: 0.2), value: showingKeyboardForLongHold)
        .animation(.easeInOut(duration: 0.2), value: showingKeyboardForDoubleTap)
        .onAppear {
            loadCurrentMapping()
            // Initialize selectedExistingLayerId if there are unassigned layers
            if let firstUnassigned = unassignedLayers.first {
                selectedExistingLayerId = firstUnassigned.id
            }
            // Allow state updates to settle before enabling auto-logic
            DispatchQueue.main.async {
                isLoading = false
            }
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
                
                Picker("", selection: $mappingType) {
                    Text("Key").tag(MappingType.singleKey)
                    Text("Macro").tag(MappingType.macro)
                    Text("System").tag(MappingType.systemCommand)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .padding(.trailing, 8)

                if mappingType == .singleKey {
                    Button(action: { showingKeyboardForPrimary.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: showingKeyboardForPrimary ? "keyboard.chevron.compact.down" : "keyboard")
                            Text(showingKeyboardForPrimary ? "Hide Keyboard" : "Show Keyboard")
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
                if mappingType == .singleKey {
                    // Current selection display
                    HStack {
                        Text("Selected:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(currentMappingDisplay)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        if keyCode != nil || modifiers.hasAny {
                            Button("Clear") {
                                keyCode = nil
                                modifiers = ModifierFlags()
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    }

                    if showingKeyboardForPrimary {
                        KeyboardVisualView(selectedKeyCode: $keyCode, modifiers: $modifiers)
                    } else {
                        KeyCaptureField(keyCode: $keyCode, modifiers: $modifiers)

                        Text("Click to type a shortcut, or show keyboard to select visually")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Hint field
                    HStack {
                        Text("Hint:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("e.g. Copy, Paste, Switch App...", text: $hint)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                    }

                    // Show hold option if any mapping is configured
                    if keyCode != nil || modifiers.hasAny {
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
                                    longHoldKeyCode = nil
                                    longHoldModifiers = ModifierFlags()
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
                } else if mappingType == .macro {
                    // MACRO SELECTION
                    if let profile = profileManager.activeProfile, !profile.macros.isEmpty {
                        Picker("Select Macro", selection: $selectedMacroId) {
                            Text("Select a Macro...").tag(nil as UUID?)
                            ForEach(profile.macros) { macro in
                                Text(macro.name).tag(macro.id as UUID?)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                        // Hint field for macros
                        HStack {
                            Text("Hint:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            TextField("e.g. Open Editor, Run Script...", text: $hint)
                                .textFieldStyle(.roundedBorder)
                                .font(.subheadline)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Text("No macros defined in this profile.")
                                .foregroundColor(.secondary)
                                .italic()

                            Text("Go to the Macros tab to create a new macro.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                    }
                } else {
                    // SYSTEM COMMAND SELECTION
                    systemCommandContent
                }
            }
            .onChange(of: keyCode) { _, newValue in
                guard !isLoading else { return }

                if let code = newValue, KeyCodeMapping.isMouseButton(code) || KeyCodeMapping.isSpecialAction(code) {
                    // Mouse clicks and special actions: auto-enable hold and disable long hold/double tap/repeat
                    if !userHasInteractedWithHold {
                        isHoldModifier = true
                    }
                    // Clear long hold, double tap, and repeat
                    enableLongHold = false
                    enableDoubleTap = false
                    enableRepeat = false
                    longHoldKeyCode = nil
                    longHoldModifiers = ModifierFlags()
                    doubleTapKeyCode = nil
                    doubleTapModifiers = ModifierFlags()
                } else if !userHasInteractedWithHold {
                    if newValue != nil {
                        // Auto-disable hold modifier for regular keys
                        isHoldModifier = false
                    } else if modifiers.hasAny {
                        // Auto-enable hold modifier for modifier-only mappings
                        isHoldModifier = true
                    }
                }
            }
            .onChange(of: modifiers) { _, newValue in
                guard !isLoading else { return }
                guard !userHasInteractedWithHold else { return }

                if keyCode == nil && newValue.hasAny {
                    // Auto-enable hold for modifier-only mappings
                    isHoldModifier = true
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var currentMappingDisplay: String {
        var parts: [String] = []
        if modifiers.command { parts.append("⌘") }
        if modifiers.option { parts.append("⌥") }
        if modifiers.shift { parts.append("⇧") }
        if modifiers.control { parts.append("⌃") }
        if let keyCode = keyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    private var holdDescription: String {
        if let code = keyCode, KeyCodeMapping.isMouseButton(code) {
            return "When enabled, the mouse button stays pressed for dragging"
        } else if keyCode == nil && modifiers.hasAny {
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

    // MARK: - System Command Section

    @ViewBuilder
    private var systemCommandContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category picker
            Picker("Category", selection: $systemCommandCategory) {
                ForEach(SystemCommandCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            // Category-specific content
            switch systemCommandCategory {
            case .shell:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Command (e.g. say \"Hello\")", text: $shellCommandText)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Toggle("Run silently (no terminal window)", isOn: Binding(
                        get: { !shellRunInTerminal },
                        set: { shellRunInTerminal = !$0 }
                    ))
                        .font(.caption)

                    Text(shellRunInTerminal
                        ? "Opens a terminal window and executes the command"
                        : "Runs silently in the background (no visible output)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if shellRunInTerminal {
                        Divider()
                        TerminalAppPickerRow()
                    }
                }
            case .app:
                AppSelectionButton(bundleId: appBundleIdentifier, showingPicker: $showingPrimaryAppPicker)
                    .sheet(isPresented: $showingPrimaryAppPicker) {
                        SystemActionAppPickerSheet(
                            currentBundleIdentifier: appBundleIdentifier.isEmpty ? nil : appBundleIdentifier
                        ) { app in
                            appBundleIdentifier = app.bundleIdentifier
                        }
                    }
                Toggle("Open in new window (Cmd+N)", isOn: $appNewWindow)
                    .font(.caption)
            case .link:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("URL (e.g. https://google.com)", text: $linkURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Button {
                        showingPrimaryBookmarkPicker = true
                    } label: {
                        Label("Browse Bookmarks", systemImage: "book")
                            .font(.subheadline)
                    }
                    .sheet(isPresented: $showingPrimaryBookmarkPicker) {
                        BookmarkPickerSheet { url in
                            linkURL = url
                        }
                    }
                }
            case .webhook:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("URL (e.g. https://api.example.com/webhook)", text: $webhookURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Picker("Method", selection: $webhookMethod) {
                        ForEach(HTTPMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    if [.POST, .PUT, .PATCH].contains(webhookMethod) {
                        TextField("Body (JSON)", text: $webhookBody, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .lineLimit(3...6)
                    }

                    DisclosureGroup("Headers") {
                        ForEach(Array(webhookHeaders.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text(key)
                                    .font(.caption)
                                Spacer()
                                Text(webhookHeaders[key] ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Button {
                                    webhookHeaders.removeValue(forKey: key)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack {
                            TextField("Header", text: $newWebhookHeaderKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            TextField("Value", text: $newWebhookHeaderValue)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            Button {
                                if !newWebhookHeaderKey.isEmpty {
                                    webhookHeaders[newWebhookHeaderKey] = newWebhookHeaderValue
                                    newWebhookHeaderKey = ""
                                    newWebhookHeaderValue = ""
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                            .disabled(newWebhookHeaderKey.isEmpty)
                        }
                    }

                    Text("Fires an HTTP request when triggered. Use for webhooks, APIs, home automation, etc.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Hint field for system commands
            HStack {
                Text("Hint:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("e.g. Launch Safari, Say Hello...", text: $hint)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }
        }
    }

    /// Compact system command fields for long hold and double tap sections
    @ViewBuilder
    private func compactSystemCommandFields(
        category: SystemCommandCategory,
        shellText: Binding<String>,
        inTerminal: Binding<Bool>,
        bundleId: Binding<String>,
        newWindow: Binding<Bool>,
        linkURL: Binding<String>,
        showingAppPicker: Binding<Bool>,
        showingBookmarkPicker: Binding<Bool>
    ) -> some View {
        switch category {
        case .shell:
            TextField("Command", text: shellText)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            Toggle("Run silently (no terminal window)", isOn: Binding(
                get: { !inTerminal.wrappedValue },
                set: { inTerminal.wrappedValue = !$0 }
            ))
                .font(.caption)
            if inTerminal.wrappedValue {
                TerminalAppPickerRow()
            }
        case .app:
            AppSelectionButton(bundleId: bundleId.wrappedValue, showingPicker: showingAppPicker)
                .sheet(isPresented: showingAppPicker) {
                    SystemActionAppPickerSheet(
                        currentBundleIdentifier: bundleId.wrappedValue.isEmpty ? nil : bundleId.wrappedValue
                    ) { app in
                        bundleId.wrappedValue = app.bundleIdentifier
                    }
                }
            Toggle("Open in new window (Cmd+N)", isOn: newWindow)
                .font(.caption)
        case .link:
            TextField("URL (e.g. https://google.com)", text: linkURL)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            Button {
                showingBookmarkPicker.wrappedValue = true
            } label: {
                Label("Browse Bookmarks", systemImage: "book")
                    .font(.subheadline)
            }
            .sheet(isPresented: showingBookmarkPicker) {
                BookmarkPickerSheet { url in
                    linkURL.wrappedValue = url
                }
            }
        case .webhook:
            Text("Webhook not supported for long hold / double tap. Use primary mapping.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// Builds a SystemCommand from the given state values, or nil if invalid
    private func buildCommand(category: SystemCommandCategory, shellText: String, inTerminal: Bool, bundleId: String, newWindow: Bool, linkURL: String) -> SystemCommand? {
        switch category {
        case .shell:
            guard !shellText.isEmpty else { return nil }
            return .shellCommand(command: shellText, inTerminal: inTerminal)
        case .app:
            guard !bundleId.isEmpty else { return nil }
            return .launchApp(bundleIdentifier: bundleId, newWindow: newWindow)
        case .link:
            guard !linkURL.isEmpty else { return nil }
            return .openLink(url: linkURL)
        case .webhook:
            // Webhook is handled separately in buildSystemCommand
            return nil
        }
    }

    private func buildSystemCommand() -> SystemCommand? {
        if systemCommandCategory == .webhook {
            guard !webhookURL.isEmpty else { return nil }
            let headers = webhookHeaders.isEmpty ? nil : webhookHeaders
            let body = webhookBody.isEmpty ? nil : webhookBody
            return .httpRequest(url: webhookURL, method: webhookMethod, headers: headers, body: body)
        }
        return buildCommand(category: systemCommandCategory, shellText: shellCommandText, inTerminal: shellRunInTerminal, bundleId: appBundleIdentifier, newWindow: appNewWindow, linkURL: linkURL)
    }

    private func buildLongHoldSystemCommand() -> SystemCommand? {
        buildCommand(category: longHoldSystemCommandCategory, shellText: longHoldShellCommandText, inTerminal: longHoldShellRunInTerminal, bundleId: longHoldAppBundleIdentifier, newWindow: longHoldAppNewWindow, linkURL: longHoldLinkURL)
    }

    private func buildDoubleTapSystemCommand() -> SystemCommand? {
        buildCommand(category: doubleTapSystemCommandCategory, shellText: doubleTapShellCommandText, inTerminal: doubleTapShellRunInTerminal, bundleId: doubleTapAppBundleIdentifier, newWindow: doubleTapAppNewWindow, linkURL: doubleTapLinkURL)
    }

    // MARK: - Long Hold Section

    /// Whether long hold should be disabled (mouse click, special action, or hold modifier enabled)
    private var longHoldDisabled: Bool {
        primaryDisablesAdvancedFeatures || (mappingType == .singleKey && (isHoldModifier || enableRepeat))
    }

    private var longHoldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Enable Long Hold Action", isOn: $enableLongHold)
                    .font(.headline)
                    .disabled(longHoldDisabled)

                Spacer()

                if enableLongHold && !longHoldDisabled && longHoldMappingType == .singleKey {
                    Button(action: { showingKeyboardForLongHold.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: showingKeyboardForLongHold ? "keyboard.chevron.compact.down" : "keyboard")
                            Text(showingKeyboardForLongHold ? "Hide" : "Show Keyboard")
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
                    Text("Long hold is not available for \(primaryIsMouseClick ? "mouse clicks" : "on-screen keyboard").")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else if mappingType == .singleKey && isHoldModifier {
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
            } else if mappingType == .singleKey && enableRepeat {
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

                    Picker("", selection: $longHoldMappingType) {
                        Text("Key").tag(MappingType.singleKey)
                        Text("Macro").tag(MappingType.macro)
                        Text("System").tag(MappingType.systemCommand)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    if longHoldMappingType == .singleKey {
                        // Current selection display
                        HStack {
                            Text("Long Hold Action:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(longHoldMappingDisplay)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        if showingKeyboardForLongHold {
                            KeyboardVisualView(selectedKeyCode: $longHoldKeyCode, modifiers: $longHoldModifiers)
                        } else {
                            KeyCaptureField(keyCode: $longHoldKeyCode, modifiers: $longHoldModifiers)
                        }
                    } else if longHoldMappingType == .macro {
                        longHoldMacroContent
                    } else {
                        longHoldSystemCommandContent
                    }

                    HStack {
                        Text("Hint:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("e.g. Copy, Paste, Switch App...", text: $longHoldHint)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    private var longHoldMappingDisplay: String {
        var parts: [String] = []
        if longHoldModifiers.command { parts.append("⌘") }
        if longHoldModifiers.option { parts.append("⌥") }
        if longHoldModifiers.shift { parts.append("⇧") }
        if longHoldModifiers.control { parts.append("⌃") }
        if let keyCode = longHoldKeyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    @ViewBuilder
    private var longHoldMacroContent: some View {
        if let profile = profileManager.activeProfile, !profile.macros.isEmpty {
            Picker("Select Macro", selection: $longHoldMacroId) {
                Text("None").tag(nil as UUID?)
                ForEach(profile.macros) { macro in
                    Text(macro.name).tag(macro.id as UUID?)
                }
            }
        } else {
            Text("No macros defined in this profile.")
                .foregroundColor(.secondary)
                .italic()
                .font(.caption)
        }
    }

    @ViewBuilder
    private var longHoldSystemCommandContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Category", selection: $longHoldSystemCommandCategory) {
                ForEach(SystemCommandCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            compactSystemCommandFields(
                category: longHoldSystemCommandCategory,
                shellText: $longHoldShellCommandText,
                inTerminal: $longHoldShellRunInTerminal,
                bundleId: $longHoldAppBundleIdentifier,
                newWindow: $longHoldAppNewWindow,
                linkURL: $longHoldLinkURL,
                showingAppPicker: $showingLongHoldAppPicker,
                showingBookmarkPicker: $showingLongHoldBookmarkPicker
            )
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

                if enableDoubleTap && !primaryDisablesAdvancedFeatures && doubleTapMappingType == .singleKey {
                    Button(action: { showingKeyboardForDoubleTap.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: showingKeyboardForDoubleTap ? "keyboard.chevron.compact.down" : "keyboard")
                            Text(showingKeyboardForDoubleTap ? "Hide" : "Show Keyboard")
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
                         : "Double tap is not available when the primary action is the on-screen keyboard.")
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

                    Picker("", selection: $doubleTapMappingType) {
                        Text("Key").tag(MappingType.singleKey)
                        Text("Macro").tag(MappingType.macro)
                        Text("System").tag(MappingType.systemCommand)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    if doubleTapMappingType == .singleKey {
                        // Current selection display
                        HStack {
                            Text("Double Tap Action:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(doubleTapMappingDisplay)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        if showingKeyboardForDoubleTap {
                            KeyboardVisualView(selectedKeyCode: $doubleTapKeyCode, modifiers: $doubleTapModifiers)
                        } else {
                            KeyCaptureField(keyCode: $doubleTapKeyCode, modifiers: $doubleTapModifiers)
                        }
                    } else if doubleTapMappingType == .macro {
                        doubleTapMacroContent
                    } else {
                        doubleTapSystemCommandContent
                    }

                    HStack {
                        Text("Hint:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("e.g. Copy, Paste, Switch App...", text: $doubleTapHint)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    private var doubleTapMappingDisplay: String {
        var parts: [String] = []
        if doubleTapModifiers.command { parts.append("⌘") }
        if doubleTapModifiers.option { parts.append("⌥") }
        if doubleTapModifiers.shift { parts.append("⇧") }
        if doubleTapModifiers.control { parts.append("⌃") }
        if let keyCode = doubleTapKeyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    @ViewBuilder
    private var doubleTapMacroContent: some View {
        if let profile = profileManager.activeProfile, !profile.macros.isEmpty {
            Picker("Select Macro", selection: $doubleTapMacroId) {
                Text("None").tag(nil as UUID?)
                ForEach(profile.macros) { macro in
                    Text(macro.name).tag(macro.id as UUID?)
                }
            }
        } else {
            Text("No macros defined in this profile.")
                .foregroundColor(.secondary)
                .italic()
                .font(.caption)
        }
    }

    @ViewBuilder
    private var doubleTapSystemCommandContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Category", selection: $doubleTapSystemCommandCategory) {
                ForEach(SystemCommandCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            compactSystemCommandFields(
                category: doubleTapSystemCommandCategory,
                shellText: $doubleTapShellCommandText,
                inTerminal: $doubleTapShellRunInTerminal,
                bundleId: $doubleTapAppBundleIdentifier,
                newWindow: $doubleTapAppNewWindow,
                linkURL: $doubleTapLinkURL,
                showingAppPicker: $showingDoubleTapAppPicker,
                showingBookmarkPicker: $showingDoubleTapBookmarkPicker
            )
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
                    longHoldKeyCode = nil
                    longHoldModifiers = ModifierFlags()
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
                Text("Repeat is not available for \(primaryIsMouseClick ? "mouse clicks" : "on-screen keyboard").")
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
            hint = existingMapping.hint ?? ""

            if let systemCommand = existingMapping.systemCommand {
                mappingType = .systemCommand
                loadSystemCommandState(systemCommand)
            } else if let macroId = existingMapping.macroId {
                mappingType = .macro
                selectedMacroId = macroId
            } else {
                mappingType = .singleKey
                keyCode = existingMapping.keyCode
                modifiers = existingMapping.modifiers
                isHoldModifier = existingMapping.isHoldModifier
            }

            // Long hold, double tap, and repeat apply to all primary mapping types
            if let longHold = existingMapping.longHoldMapping {
                enableLongHold = true
                longHoldThreshold = longHold.threshold
                longHoldHint = longHold.hint ?? ""
                if let systemCommand = longHold.systemCommand {
                    longHoldMappingType = .systemCommand
                    loadLongHoldSystemCommandState(systemCommand)
                } else if let macroId = longHold.macroId {
                    longHoldMappingType = .macro
                    longHoldMacroId = macroId
                } else {
                    longHoldMappingType = .singleKey
                    longHoldKeyCode = longHold.keyCode
                    longHoldModifiers = longHold.modifiers
                }
            }

            if let doubleTap = existingMapping.doubleTapMapping {
                enableDoubleTap = true
                doubleTapThreshold = doubleTap.threshold
                doubleTapHint = doubleTap.hint ?? ""
                if let systemCommand = doubleTap.systemCommand {
                    doubleTapMappingType = .systemCommand
                    loadDoubleTapSystemCommandState(systemCommand)
                } else if let macroId = doubleTap.macroId {
                    doubleTapMappingType = .macro
                    doubleTapMacroId = macroId
                } else {
                    doubleTapMappingType = .singleKey
                    doubleTapKeyCode = doubleTap.keyCode
                    doubleTapModifiers = doubleTap.modifiers
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

        if mappingType == .systemCommand {
            guard let command = buildSystemCommand() else { return }
            newMapping = KeyMapping(systemCommand: command, hint: hint.isEmpty ? nil : hint)
        } else if mappingType == .macro {
            guard let macroId = selectedMacroId else { return }
            newMapping = KeyMapping(macroId: macroId, hint: hint.isEmpty ? nil : hint)
        } else {
            newMapping = KeyMapping(
                keyCode: keyCode,
                modifiers: modifiers,
                isHoldModifier: isHoldModifier,
                hint: hint.isEmpty ? nil : hint
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
            switch longHoldMappingType {
            case .singleKey:
                longHoldValid = longHoldKeyCode != nil || longHoldModifiers.hasAny
            case .macro:
                longHoldValid = longHoldMacroId != nil
            case .systemCommand:
                longHoldValid = buildLongHoldSystemCommand() != nil
            }
            if longHoldValid {
                newMapping.longHoldMapping = LongHoldMapping(
                    keyCode: longHoldMappingType == .singleKey ? longHoldKeyCode : nil,
                    modifiers: longHoldMappingType == .singleKey ? longHoldModifiers : ModifierFlags(),
                    threshold: longHoldThreshold,
                    macroId: longHoldMappingType == .macro ? longHoldMacroId : nil,
                    systemCommand: longHoldMappingType == .systemCommand ? buildLongHoldSystemCommand() : nil,
                    hint: longHoldHint.isEmpty ? nil : longHoldHint
                )
            }
        }

        if enableDoubleTap && !primaryDisablesAdvancedFeatures {
            let doubleTapValid: Bool
            switch doubleTapMappingType {
            case .singleKey:
                doubleTapValid = doubleTapKeyCode != nil || doubleTapModifiers.hasAny
            case .macro:
                doubleTapValid = doubleTapMacroId != nil
            case .systemCommand:
                doubleTapValid = buildDoubleTapSystemCommand() != nil
            }
            if doubleTapValid {
                newMapping.doubleTapMapping = DoubleTapMapping(
                    keyCode: doubleTapMappingType == .singleKey ? doubleTapKeyCode : nil,
                    modifiers: doubleTapMappingType == .singleKey ? doubleTapModifiers : ModifierFlags(),
                    threshold: doubleTapThreshold,
                    macroId: doubleTapMappingType == .macro ? doubleTapMacroId : nil,
                    systemCommand: doubleTapMappingType == .systemCommand ? buildDoubleTapSystemCommand() : nil,
                    hint: doubleTapHint.isEmpty ? nil : doubleTapHint
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

    /// Loads system command state into the given bindings
    private func loadCommandState(_ command: SystemCommand, category: inout SystemCommandCategory, bundleId: inout String, newWindow: inout Bool, shellText: inout String, inTerminal: inout Bool, linkURL: inout String) {
        category = command.category
        switch command {
        case .launchApp(let id, let nw):
            bundleId = id
            newWindow = nw
        case .shellCommand(let cmd, let terminal):
            shellText = cmd
            inTerminal = terminal
        case .openLink(let url):
            linkURL = url
        case .httpRequest:
            // Webhook is handled separately in loadSystemCommandState
            break
        }
    }

    private func loadSystemCommandState(_ command: SystemCommand) {
        if case .httpRequest(let url, let method, let headers, let body) = command {
            systemCommandCategory = .webhook
            webhookURL = url
            webhookMethod = method
            webhookHeaders = headers ?? [:]
            webhookBody = body ?? ""
        } else {
            loadCommandState(command, category: &systemCommandCategory, bundleId: &appBundleIdentifier, newWindow: &appNewWindow, shellText: &shellCommandText, inTerminal: &shellRunInTerminal, linkURL: &linkURL)
        }
    }

    private func loadLongHoldSystemCommandState(_ command: SystemCommand) {
        loadCommandState(command, category: &longHoldSystemCommandCategory, bundleId: &longHoldAppBundleIdentifier, newWindow: &longHoldAppNewWindow, shellText: &longHoldShellCommandText, inTerminal: &longHoldShellRunInTerminal, linkURL: &longHoldLinkURL)
    }

    private func loadDoubleTapSystemCommandState(_ command: SystemCommand) {
        loadCommandState(command, category: &doubleTapSystemCommandCategory, bundleId: &doubleTapAppBundleIdentifier, newWindow: &doubleTapAppNewWindow, shellText: &doubleTapShellCommandText, inTerminal: &doubleTapShellRunInTerminal, linkURL: &doubleTapLinkURL)
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
