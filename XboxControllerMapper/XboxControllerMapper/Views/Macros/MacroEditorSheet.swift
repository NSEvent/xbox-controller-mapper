import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Wrapper to give MacroStep a stable identity for drag-and-drop
private struct IdentifiedStep: Identifiable, Equatable {
    let id: UUID
    var step: MacroStep

    init(_ step: MacroStep) {
        self.id = UUID()
        self.step = step
    }
}

/// Drop delegate for reordering macro steps
private struct MacroStepDropDelegate: DropDelegate {
    let item: IdentifiedStep
    @Binding var items: [IdentifiedStep]
    @Binding var draggedItem: IdentifiedStep?

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              draggedItem.id != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct MacroEditorSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var identifiedSteps: [IdentifiedStep] = []

    // For editing existing steps
    @State private var editingStepIndex: Int?
    @State private var showingStepEditor = false

    // For adding new steps - step is only added on save, not on open
    @State private var pendingNewStep: MacroStep?
    @State private var showingNewStepEditor = false

    // For drag and drop reordering
    @State private var draggedStep: IdentifiedStep?

    let originalMacro: Macro?

    init(macro: Macro?) {
        self.originalMacro = macro
        _name = State(initialValue: macro?.name ?? "")
        _identifiedSteps = State(initialValue: (macro?.steps ?? []).map { IdentifiedStep($0) })
    }

    private var canSave: Bool {
        !identifiedSteps.isEmpty
    }

    private var steps: [MacroStep] {
        identifiedSteps.map { $0.step }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(originalMacro == nil ? "Add Macro" : "Edit Macro")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Macro Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(identifiedSteps.enumerated()), id: \.element.id) { index, identifiedStep in
                        MacroStepRow(
                            step: identifiedStep.step,
                            index: index,
                            onDuplicate: { duplicateStep(at: index) },
                            onDelete: { deleteStep(at: index) }
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingStepIndex = index
                            showingStepEditor = true
                        }
                        .onDrag {
                            draggedStep = identifiedStep
                            return NSItemProvider(object: identifiedStep.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: MacroStepDropDelegate(
                            item: identifiedStep,
                            items: $identifiedSteps,
                            draggedItem: $draggedStep
                        ))
                    }

                    // Add Step row as last item in list
                    AddStepRow {
                        addStep(.press(KeyMapping()))
                    }
                }
                .padding(8)
            }
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal)
        }
        .onSubmit { save() }
        .padding(.vertical, 20)
        .frame(width: 600, height: 600)
        // Sheet for editing existing steps
        .sheet(isPresented: $showingStepEditor) {
            if let index = editingStepIndex, index < identifiedSteps.count {
                MacroStepEditorSheet(
                    initialStep: identifiedSteps[index].step,
                    onSave: { identifiedSteps[index].step = $0 }
                )
            } else {
                Text("Error: No step selected")
            }
        }
        // Sheet for adding new steps - only adds on save
        .sheet(isPresented: $showingNewStepEditor) {
            if let step = pendingNewStep {
                MacroStepEditorSheet(
                    title: "Add Step",
                    actionLabel: "Add",
                    initialStep: step,
                    onSave: { savedStep in
                        identifiedSteps.append(IdentifiedStep(savedStep))
                        pendingNewStep = nil
                    },
                    onCancel: {
                        pendingNewStep = nil
                    }
                )
            }
        }
    }

    private func addStep(_ step: MacroStep) {
        pendingNewStep = step
        showingNewStepEditor = true
    }

    private func duplicateStep(at index: Int) {
        guard index >= 0 && index < identifiedSteps.count else { return }
        let stepCopy = IdentifiedStep(identifiedSteps[index].step)
        identifiedSteps.insert(stepCopy, at: index + 1)
    }

    private func deleteStep(at index: Int) {
        guard index >= 0 && index < identifiedSteps.count else { return }
        identifiedSteps.remove(at: index)
    }

    private func save() {
        guard canSave else { return }
        let macroName = name.isEmpty ? "Macro \(Date().formatted(date: .abbreviated, time: .shortened))" : name
        if let original = originalMacro {
            var updated = original
            updated.name = macroName
            updated.steps = steps
            profileManager.updateMacro(updated)
        } else {
            let newMacro = Macro(name: macroName, steps: steps)
            profileManager.addMacro(newMacro)
        }
        dismiss()
    }
}

struct AddStepRow: View {
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
            Text("Add Step")
                .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
        .background(isHovered ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            onTap()
        }
    }
}

struct MacroStepRow: View {
    let step: MacroStep
    let index: Int
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))

            Text("\(index + 1).")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .leading)

            icon
                .frame(width: 20)

            Text(step.displayString)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            Button {
                onDuplicate()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Duplicate step")

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Delete step")

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(isHovered ? .accentColor : .secondary.opacity(0.5))
        }
        .padding(.vertical, 4)
        .background(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    var icon: some View {
        switch step {
        case .press:
            Image(systemName: "keyboard")
                .foregroundColor(.blue)
        case .hold:
            Image(systemName: "hand.tap")
                .foregroundColor(.orange)
        case .delay:
            Image(systemName: "timer")
                .foregroundColor(.gray)
        case .typeText:
            Image(systemName: "textformat")
                .foregroundColor(.purple)
        case .openApp:
            Image(systemName: "app.fill")
                .foregroundColor(.green)
        case .openLink:
            Image(systemName: "link")
                .foregroundColor(.teal)
        case .shellCommand:
            Image(systemName: "terminal")
                .foregroundColor(.indigo)
        case .webhook:
            Image(systemName: "arrow.up.right.circle")
                .foregroundColor(.pink)
        case .obsWebSocket:
            Image(systemName: "video.fill")
                .foregroundColor(.red)
        }
    }
}

/// Unified sheet for adding or editing a macro step
struct MacroStepEditorSheet: View {
    let title: String
    let actionLabel: String
    let onSave: (MacroStep) -> Void
    var onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    // Temporary state for editing
    @State private var keyCode: CGKeyCode?
    @State private var modifiers = ModifierFlags()
    @State private var duration: TimeInterval = 0.5
    @State private var text: String = ""
    @State private var speed: Int = 0 // 0 = Paste
    @State private var pressEnter: Bool = false
    @State private var appBundleIdentifier: String = ""
    @State private var openNewWindow: Bool = false
    @State private var linkURL: String = ""
    @State private var showingAppPicker = false
    @State private var showingBookmarkPicker = false

    @State private var showingKeyboard = false

    // System command state
    @State private var shellCommandText: String = ""
    @State private var shellRunInTerminal: Bool = true
    @State private var webhookURL: String = ""
    @State private var webhookMethod: HTTPMethod = .POST
    @State private var webhookBody: String = ""
    @State private var webhookHeaders: [String: String] = [:]
    @State private var newWebhookHeaderKey: String = ""
    @State private var newWebhookHeaderValue: String = ""
    @State private var obsWebSocketURL: String = "ws://127.0.0.1:4455"
    @State private var obsWebSocketPassword: String = ""
    @State private var obsRequestType: String = ""
    @State private var obsRequestData: String = ""

    // To track type changes
    @State private var selectedType: StepType

    enum StepType: String, CaseIterable, Identifiable {
        case press = "Key Press"
        case hold = "Key Hold"
        case typeText = "Type Text"
        case delay = "Delay"
        case openApp = "Open App"
        case openLink = "Open Link"
        case shellCommand = "Shell Command"
        case webhook = "Webhook"
        case obsWebSocket = "OBS WebSocket"
        var id: String { rawValue }
    }

    init(title: String = "Edit Step", actionLabel: String = "Save", initialStep: MacroStep, onSave: @escaping (MacroStep) -> Void, onCancel: (() -> Void)? = nil) {
        self.title = title
        self.actionLabel = actionLabel
        self.onSave = onSave
        self.onCancel = onCancel

        switch initialStep {
        case .press(let mapping):
            _selectedType = State(initialValue: .press)
            _keyCode = State(initialValue: mapping.keyCode)
            _modifiers = State(initialValue: mapping.modifiers)
        case .hold(let mapping, let dur):
            _selectedType = State(initialValue: .hold)
            _keyCode = State(initialValue: mapping.keyCode)
            _modifiers = State(initialValue: mapping.modifiers)
            _duration = State(initialValue: dur)
        case .delay(let dur):
            _selectedType = State(initialValue: .delay)
            _duration = State(initialValue: dur)
        case .typeText(let txt, let spd, let enter):
            _selectedType = State(initialValue: .typeText)
            _text = State(initialValue: txt)
            _speed = State(initialValue: spd)
            _pressEnter = State(initialValue: enter)
        case .openApp(let bundleId, let newWindow):
            _selectedType = State(initialValue: .openApp)
            _appBundleIdentifier = State(initialValue: bundleId)
            _openNewWindow = State(initialValue: newWindow)
        case .openLink(let url):
            _selectedType = State(initialValue: .openLink)
            _linkURL = State(initialValue: url)
        case .shellCommand(let cmd, let inTerminal):
            _selectedType = State(initialValue: .shellCommand)
            _shellCommandText = State(initialValue: cmd)
            _shellRunInTerminal = State(initialValue: inTerminal)
        case .webhook(let url, let method, let headers, let body):
            _selectedType = State(initialValue: .webhook)
            _webhookURL = State(initialValue: url)
            _webhookMethod = State(initialValue: method)
            _webhookHeaders = State(initialValue: headers ?? [:])
            _webhookBody = State(initialValue: body ?? "")
        case .obsWebSocket(let url, let password, let requestType, let requestData):
            _selectedType = State(initialValue: .obsWebSocket)
            _obsWebSocketURL = State(initialValue: url)
            _obsWebSocketPassword = State(initialValue: password ?? "")
            _obsRequestType = State(initialValue: requestType)
            _obsRequestData = State(initialValue: requestData ?? "")
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.headline)
                .padding(.top, 20)

            Picker("Step Type", selection: $selectedType) {
                ForEach(StepType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)

            Form {
                switch selectedType {
                case .press:
                    Section {
                        if showingKeyboard {
                            KeyboardVisualView(selectedKeyCode: $keyCode, modifiers: $modifiers)
                        } else {
                            KeyCaptureField(keyCode: $keyCode, modifiers: $modifiers)
                        }
                    } header: {
                        HStack {
                            Text("Key Combination")
                            Spacer()
                            Button(action: { showingKeyboard.toggle() }) {
                                Text(showingKeyboard ? "Hide Keyboard" : "Show Keyboard")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                    }

                case .hold:
                    Section {
                        if showingKeyboard {
                            KeyboardVisualView(selectedKeyCode: $keyCode, modifiers: $modifiers)
                        } else {
                            KeyCaptureField(keyCode: $keyCode, modifiers: $modifiers)
                        }
                    } header: {
                        HStack {
                            Text("Key Combination")
                            Spacer()
                            Button(action: { showingKeyboard.toggle() }) {
                                Text(showingKeyboard ? "Hide Keyboard" : "Show Keyboard")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                    }
                    Section("Duration") {
                        TextField("Seconds", value: $duration, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }

                case .delay:
                    Section("Duration") {
                        TextField("Seconds", value: $duration, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }

                case .typeText:
                    Section {
                        TextEditor(text: $text)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 60, maxHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                        if text.hasSuffix(" ") || text.hasPrefix(" ") {
                            HStack(spacing: 4) {
                                Image(systemName: "space")
                                    .font(.caption2)
                                Text(whitespaceIndicator)
                                    .font(.caption)
                            }
                            .foregroundColor(.orange)
                        }
                        Text("\(text.count) characters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } header: {
                        Text("Text to Type")
                    }

                    Section("Typing Speed") {
                        Picker("Speed", selection: $speed) {
                            Text("Instant (Paste)").tag(0)
                            Text("Fast (1200 CPM)").tag(1200)
                            Text("Natural (600 CPM)").tag(600)
                            Text("Slow (300 CPM)").tag(300)
                        }
                    }

                    Section {
                        Toggle("Press Enter after typing", isOn: $pressEnter)
                    }

                case .openApp:
                    Section("Application") {
                        AppSelectionButton(bundleId: appBundleIdentifier, showingPicker: $showingAppPicker)
                            .sheet(isPresented: $showingAppPicker) {
                                SystemActionAppPickerSheet(
                                    currentBundleIdentifier: appBundleIdentifier.isEmpty ? nil : appBundleIdentifier
                                ) { app in
                                    appBundleIdentifier = app.bundleIdentifier
                                }
                            }
                    }
                    Section {
                        Toggle("Open in new window (Cmd+N)", isOn: $openNewWindow)
                    }

                case .openLink:
                    Section("URL") {
                        TextField("https://example.com", text: $linkURL)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            showingBookmarkPicker = true
                        } label: {
                            Label("Browse Bookmarks", systemImage: "book")
                        }
                        .sheet(isPresented: $showingBookmarkPicker) {
                            BookmarkPickerSheet { url in
                                linkURL = url
                            }
                        }
                    }

                case .shellCommand:
                    Section("Command") {
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

                case .webhook:
                    Section("Request") {
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
                    }

                    Section("Headers") {
                        ForEach(Array(webhookHeaders.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text(key).font(.caption)
                                Spacer()
                                Text(webhookHeaders[key] ?? "").font(.caption).foregroundColor(.secondary)
                                Button { webhookHeaders.removeValue(forKey: key) } label: {
                                    Image(systemName: "minus.circle.fill").foregroundColor(.red)
                                }.buttonStyle(.plain)
                            }
                        }
                        HStack {
                            TextField("Header", text: $newWebhookHeaderKey)
                                .textFieldStyle(.roundedBorder).font(.caption)
                            TextField("Value", text: $newWebhookHeaderValue)
                                .textFieldStyle(.roundedBorder).font(.caption)
                            Button {
                                if !newWebhookHeaderKey.isEmpty {
                                    webhookHeaders[newWebhookHeaderKey] = newWebhookHeaderValue
                                    newWebhookHeaderKey = ""
                                    newWebhookHeaderValue = ""
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill").foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                            .disabled(newWebhookHeaderKey.isEmpty)
                        }
                    }

                case .obsWebSocket:
                    Section("OBS WebSocket") {
                        TextField("WebSocket URL (e.g. ws://127.0.0.1:4455)", text: $obsWebSocketURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)

                        SecureField("Password (optional)", text: $obsWebSocketPassword)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)

                        TextField("Request Type (e.g. StartRecord)", text: $obsRequestType)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)

                        TextField("Request Data (JSON object, optional)", text: $obsRequestData, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .lineLimit(3...6)

                        Text("Sends any OBS WebSocket v5 request type with optional requestData JSON.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    onCancel?()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(actionLabel) {
                    if canSave {
                        onSave(buildStep())
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)

                // Hidden button for plain Return key
                Button("") { if canSave { onSave(buildStep()); dismiss() } }
                    .keyboardShortcut(.defaultAction)
                    .hidden()
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onSubmit { if canSave { onSave(buildStep()); dismiss() } }
        .frame(width: showingKeyboard ? 850 : 400, height: showingKeyboard ? 750 : 450)
        .animation(.easeInOut, value: showingKeyboard)
    }

    private var canSave: Bool {
        switch selectedType {
        case .press, .hold:
            return keyCode != nil
        case .typeText:
            return !text.isEmpty
        case .delay:
            return true
        case .openApp:
            return !appBundleIdentifier.isEmpty
        case .openLink:
            return !linkURL.isEmpty
        case .shellCommand:
            return !shellCommandText.isEmpty
        case .webhook:
            return !webhookURL.isEmpty
        case .obsWebSocket:
            return !obsRequestType.isEmpty
        }
    }

    private var whitespaceIndicator: String {
        var parts: [String] = []
        if text.hasPrefix(" ") {
            let count = text.prefix(while: { $0 == " " }).count
            parts.append("\(count) leading space\(count > 1 ? "s" : "")")
        }
        if text.hasSuffix(" ") {
            let count = text.reversed().prefix(while: { $0 == " " }).count
            parts.append("\(count) trailing space\(count > 1 ? "s" : "")")
        }
        return parts.joined(separator: ", ")
    }

    private func buildStep() -> MacroStep {
        switch selectedType {
        case .press:
            return .press(KeyMapping(keyCode: keyCode, modifiers: modifiers))
        case .hold:
            return .hold(KeyMapping(keyCode: keyCode, modifiers: modifiers), duration: duration)
        case .delay:
            return .delay(duration)
        case .typeText:
            return .typeText(text, speed: speed, pressEnter: pressEnter)
        case .openApp:
            return .openApp(bundleIdentifier: appBundleIdentifier, newWindow: openNewWindow)
        case .openLink:
            return .openLink(url: linkURL)
        case .shellCommand:
            return .shellCommand(command: shellCommandText, inTerminal: shellRunInTerminal)
        case .webhook:
            return .webhook(
                url: webhookURL,
                method: webhookMethod,
                headers: webhookHeaders.isEmpty ? nil : webhookHeaders,
                body: webhookBody.isEmpty ? nil : webhookBody
            )
        case .obsWebSocket:
            return .obsWebSocket(
                url: obsWebSocketURL,
                password: obsWebSocketPassword.isEmpty ? nil : obsWebSocketPassword,
                requestType: obsRequestType,
                requestData: obsRequestData.isEmpty ? nil : obsRequestData
            )
        }
    }
}
