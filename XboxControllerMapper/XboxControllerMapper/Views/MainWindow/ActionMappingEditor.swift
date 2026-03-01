import SwiftUI

/// A reusable view that edits a single MappingEditorState.
/// Used for the primary, long hold, and double tap mapping sections.
struct ActionMappingEditor: View {
    @Binding var state: MappingEditorState
    @EnvironmentObject var profileManager: ProfileManager

    /// Which variant is being edited (controls which features are available)
    let variant: Variant

    enum Variant {
        case primary
        case longHold
        case doubleTap
    }

    /// Whether to show the full system command categories (webhook/OBS) - only for primary
    private var showFullSystemCategories: Bool {
        variant == .primary
    }

    /// Whether script selection is available (only for primary)
    private var showScriptOption: Bool {
        variant == .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.mappingType == .singleKey {
                singleKeyContent
            } else if state.mappingType == .macro {
                macroContent
            } else if state.mappingType == .script {
                scriptContent
            } else {
                systemCommandContent
            }
        }
    }

    // MARK: - Single Key

    @ViewBuilder
    private var singleKeyContent: some View {
        // Current selection display
        HStack {
            Text(variant == .primary ? "Selected:" : "\(variant == .longHold ? "Long Hold" : "Double Tap") Action:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(state.mappingDisplayString)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            if variant == .primary && (state.keyCode != nil || state.modifiers.hasAny) {
                Button("Clear") {
                    state.keyCode = nil
                    state.modifiers = ModifierFlags()
                }
                .font(.caption)
                .foregroundColor(.red)
            }
        }

        if state.showingKeyboard {
            KeyboardVisualView(selectedKeyCode: $state.keyCode, modifiers: $state.modifiers)
        } else {
            KeyCaptureField(keyCode: $state.keyCode, modifiers: $state.modifiers)
        }

        if variant == .primary && !state.showingKeyboard {
            Text("Click to type a shortcut, or show keyboard to select visually")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        // Hint field (only for primary; long hold/double tap have their own hint in ButtonMappingSheet)
        if variant == .primary {
            HStack {
                Text("Hint:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("e.g. Copy, Paste, Switch App...", text: $state.hint)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }

            HapticStylePicker(hapticStyle: $state.hapticStyle)
        }
    }

    // MARK: - Macro

    @ViewBuilder
    private var macroContent: some View {
        if let profile = profileManager.activeProfile, !profile.macros.isEmpty {
            Picker("Select Macro", selection: $state.selectedMacroId) {
                Text(variant == .primary ? "Select a Macro..." : "None").tag(nil as UUID?)
                ForEach(profile.macros) { macro in
                    Text(macro.name).tag(macro.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(maxWidth: variant == .primary ? .infinity : nil)

            Button { state.showingMacroCreation = true } label: {
                Label("Create New Macro...", systemImage: "plus.circle")
                    .font(variant == .primary ? .subheadline : .caption)
            }

            if variant == .primary {
                // Hint field for macros
                HStack {
                    Text("Hint:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("e.g. Open Editor, Run Script...", text: $state.hint)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                }

                HapticStylePicker(hapticStyle: $state.hapticStyle)
            }
        } else {
            VStack(spacing: 8) {
                Text("No macros defined in this profile.")
                    .foregroundColor(.secondary)
                    .italic()
                    .font(variant == .primary ? .body : .caption)

                Button { state.showingMacroCreation = true } label: {
                    Label("Create New Macro...", systemImage: "plus.circle")
                        .font(variant == .primary ? .subheadline : .caption)
                }
            }
            .frame(maxWidth: variant == .primary ? .infinity : nil)
            .padding(variant == .primary ? 16 : 0)
            .background(variant == .primary ? Color.black.opacity(0.05) : Color.clear)
            .cornerRadius(variant == .primary ? 8 : 0)
        }
    }

    // MARK: - Script (primary only)

    @ViewBuilder
    private var scriptContent: some View {
        if let profile = profileManager.activeProfile, !profile.scripts.isEmpty {
            Picker("Select Script", selection: $state.selectedScriptId) {
                Text("Select a Script...").tag(nil as UUID?)
                ForEach(profile.scripts) { script in
                    Text(script.name).tag(script.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button { state.showingScriptCreation = true } label: {
                Label("Create New Script...", systemImage: "plus.circle")
                    .font(.subheadline)
            }

            // Hint field for scripts
            HStack {
                Text("Hint:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("e.g. Smart Spacebar, Toggle Mode...", text: $state.hint)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }

            HapticStylePicker(hapticStyle: $state.hapticStyle)
        } else {
            VStack(spacing: 8) {
                Text("No scripts defined in this profile.")
                    .foregroundColor(.secondary)
                    .italic()

                Button { state.showingScriptCreation = true } label: {
                    Label("Create New Script...", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
        }
    }

    // MARK: - System Command

    @ViewBuilder
    private var systemCommandContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category picker
            if showFullSystemCategories {
                Picker("", selection: $state.systemCommandCategory) {
                    ForEach(SystemCommandCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Picker("", selection: $state.systemCommandCategory) {
                    ForEach(SystemCommandCategory.allCases.filter { ![.webhook, .obs].contains($0) }, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Category-specific content
            systemCommandFields

            // Hint field for system commands (primary only shows inline; long hold/double tap have separate hint)
            if variant == .primary {
                HStack {
                    Text("Hint:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("e.g. Launch Safari, Say Hello...", text: $state.hint)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                }

                HapticStylePicker(hapticStyle: $state.hapticStyle)
            }
        }
    }

    @ViewBuilder
    private var systemCommandFields: some View {
        switch state.systemCommandCategory {
        case .shell:
            shellFields
        case .app:
            appFields
        case .link:
            linkFields
        case .webhook:
            if showFullSystemCategories {
                webhookFields
            } else {
                Text("Webhook not supported for long hold / double tap. Use primary mapping.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .obs:
            if showFullSystemCategories {
                obsFields
            } else {
                Text("OBS WebSocket not supported for long hold / double tap. Use primary mapping.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var shellFields: some View {
        TextField(variant == .primary ? "Command (e.g. say \"Hello\")" : "Command", text: $state.shellCommandText)
            .textFieldStyle(.roundedBorder)
            .font(.subheadline)

        Toggle("Run silently (no terminal window)", isOn: Binding(
            get: { !state.shellRunInTerminal },
            set: { state.shellRunInTerminal = !$0 }
        ))
            .font(.caption)

        if variant == .primary {
            Text(state.shellRunInTerminal
                ? "Opens a terminal window and executes the command"
                : "Runs silently in the background (no visible output)")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if state.shellRunInTerminal {
            if variant == .primary {
                Divider()
            }
            TerminalAppPickerRow()
        }
    }

    @ViewBuilder
    private var appFields: some View {
        AppSelectionButton(bundleId: state.appBundleIdentifier, showingPicker: $state.showingAppPicker)
            .sheet(isPresented: $state.showingAppPicker) {
                SystemActionAppPickerSheet(
                    currentBundleIdentifier: state.appBundleIdentifier.isEmpty ? nil : state.appBundleIdentifier
                ) { app in
                    state.appBundleIdentifier = app.bundleIdentifier
                }
            }
        Toggle("Open in new window (Cmd+N)", isOn: $state.appNewWindow)
            .font(.caption)
    }

    @ViewBuilder
    private var linkFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("URL (e.g. https://google.com)", text: $state.linkURL)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

            Button {
                state.showingBookmarkPicker = true
            } label: {
                Label("Browse Bookmarks", systemImage: "book")
                    .font(.subheadline)
            }
            .sheet(isPresented: $state.showingBookmarkPicker) {
                BookmarkPickerSheet { url in
                    state.linkURL = url
                }
            }
        }
    }

    @ViewBuilder
    private var webhookFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("URL (e.g. https://api.example.com/webhook)", text: $state.webhookURL)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

            Picker("Method", selection: $state.webhookMethod) {
                ForEach(HTTPMethod.allCases) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)

            if [.POST, .PUT, .PATCH].contains(state.webhookMethod) {
                TextField("Body (JSON)", text: $state.webhookBody, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .lineLimit(3...6)
            }

            DisclosureGroup("Headers") {
                ForEach(Array(state.webhookHeaders.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key)
                            .font(.caption)
                        Spacer()
                        Text(state.webhookHeaders[key] ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button {
                            state.webhookHeaders.removeValue(forKey: key)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("Header", text: $state.newWebhookHeaderKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    TextField("Value", text: $state.newWebhookHeaderValue)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button {
                        if !state.newWebhookHeaderKey.isEmpty {
                            state.webhookHeaders[state.newWebhookHeaderKey] = state.newWebhookHeaderValue
                            state.newWebhookHeaderKey = ""
                            state.newWebhookHeaderValue = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.newWebhookHeaderKey.isEmpty)
                }
            }

            Text("Fires an HTTP request when triggered. Use for webhooks, APIs, home automation, etc.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var obsFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("WebSocket URL (e.g. ws://127.0.0.1:4455)", text: $state.obsWebSocketURL)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

            SecureField("Password (optional)", text: $state.obsWebSocketPassword)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

            TextField("Request Type (e.g. StartRecord)", text: $state.obsRequestType)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

            TextField("Request Data (JSON object, optional)", text: $state.obsRequestData, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
                .lineLimit(3...6)

            Text("Sends any OBS WebSocket v5 request type with optional requestData JSON.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
