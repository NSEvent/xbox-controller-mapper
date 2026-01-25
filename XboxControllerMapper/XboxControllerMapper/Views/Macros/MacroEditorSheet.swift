import SwiftUI

/// Wrapper to give MacroStep a stable identity for drag-and-drop
private struct IdentifiedStep: Identifiable, Equatable {
    let id: UUID
    var step: MacroStep

    init(_ step: MacroStep) {
        self.id = UUID()
        self.step = step
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

    let originalMacro: Macro?

    init(macro: Macro?) {
        self.originalMacro = macro
        _name = State(initialValue: macro?.name ?? "")
        _identifiedSteps = State(initialValue: (macro?.steps ?? []).map { IdentifiedStep($0) })
    }

    private var canSave: Bool {
        !name.isEmpty && !identifiedSteps.isEmpty
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

            List {
                ForEach(Array(identifiedSteps.enumerated()), id: \.element.id) { index, identifiedStep in
                    MacroStepRow(
                        step: identifiedStep.step,
                        index: index,
                        onMoveUp: index > 0 ? { moveStep(from: index, to: index - 1) } : nil,
                        onMoveDown: index < identifiedSteps.count - 1 ? { moveStep(from: index, to: index + 1) } : nil,
                        onDuplicate: { duplicateStep(at: index) },
                        onDelete: { deleteStep(at: index) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingStepIndex = index
                        showingStepEditor = true
                    }
                }
            }
            .listStyle(.inset)
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
            
            HStack {
                Menu {
                    Button {
                        addStep(.press(KeyMapping()))
                    } label: {
                        Label("Key Press", systemImage: "keyboard")
                    }
                    
                    Button {
                        addStep(.hold(KeyMapping(), duration: 1.0))
                    } label: {
                        Label("Hold Key", systemImage: "hand.tap")
                    }
                    
                    Button {
                        addStep(.typeText("", speed: 0))
                    } label: {
                        Label("Type Text", systemImage: "textformat")
                    }
                    
                    Button {
                        addStep(.delay(0.5))
                    } label: {
                        Label("Delay", systemImage: "timer")
                    }

                    Divider()

                    Button {
                        addStep(.openApp(bundleIdentifier: "", newWindow: false))
                    } label: {
                        Label("Open App", systemImage: "app.fill")
                    }

                    Button {
                        addStep(.openLink(url: ""))
                    } label: {
                        Label("Open Link", systemImage: "link")
                    }
                } label: {
                    Label("Add Step", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
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
                StepEditorSheet(step: Binding(
                    get: { identifiedSteps[index].step },
                    set: { identifiedSteps[index].step = $0 }
                ))
            } else {
                Text("Error: No step selected")
            }
        }
        // Sheet for adding new steps - only adds on save
        .sheet(isPresented: $showingNewStepEditor) {
            if let step = pendingNewStep {
                NewStepEditorSheet(
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

    private func moveStep(from source: Int, to destination: Int) {
        guard source >= 0 && source < identifiedSteps.count &&
              destination >= 0 && destination < identifiedSteps.count else { return }
        let item = identifiedSteps.remove(at: source)
        identifiedSteps.insert(item, at: destination)
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
        if let original = originalMacro {
            var updated = original
            updated.name = name
            updated.steps = steps
            profileManager.updateMacro(updated)
        } else {
            let newMacro = Macro(name: name, steps: steps)
            profileManager.addMacro(newMacro)
        }
        dismiss()
    }
}

struct MacroStepRow: View {
    let step: MacroStep
    let index: Int
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
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

            // Move up button
            Button {
                onMoveUp?()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.caption)
                    .foregroundColor(onMoveUp != nil ? .secondary : .secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(onMoveUp == nil)
            .help("Move up")

            // Move down button
            Button {
                onMoveDown?()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(onMoveDown != nil ? .secondary : .secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(onMoveDown == nil)
            .help("Move down")

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
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.vertical, 4)
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
        }
    }
}

struct StepEditorSheet: View {
    @Binding var step: MacroStep
    @Environment(\.dismiss) private var dismiss
    
    // Temporary state for editing
    @State private var keyCode: CGKeyCode?
    @State private var modifiers = ModifierFlags()
    @State private var duration: TimeInterval = 0.5
    @State private var text: String = ""
    @State private var speed: Int = 0 // 0 = Paste
    @State private var appBundleIdentifier: String = ""
    @State private var openNewWindow: Bool = false
    @State private var linkURL: String = ""
    @State private var showingAppPicker = false
    @State private var showingBookmarkPicker = false

    @State private var showingKeyboard = false
    
    // To track type changes
    @State private var selectedType: StepType
    
    enum StepType: String, CaseIterable, Identifiable {
        case press = "Key Press"
        case hold = "Hold Key"
        case typeText = "Type Text"
        case delay = "Delay"
        case openApp = "Open App"
        case openLink = "Open Link"
        var id: String { rawValue }
    }
    
    init(step: Binding<MacroStep>) {
        _step = step
        
        // Initialize state based on current step
        switch step.wrappedValue {
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
        case .typeText(let txt, let spd):
            _selectedType = State(initialValue: .typeText)
            _text = State(initialValue: txt)
            _speed = State(initialValue: spd)
        case .openApp(let bundleId, let newWindow):
            _selectedType = State(initialValue: .openApp)
            _appBundleIdentifier = State(initialValue: bundleId)
            _openNewWindow = State(initialValue: newWindow)
        case .openLink(let url):
            _selectedType = State(initialValue: .openLink)
            _linkURL = State(initialValue: url)
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Step")
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
                    Section("Text to Type") {
                        TextField("Enter text...", text: $text)
                            .textFieldStyle(.roundedBorder)
                    }

                    Section("Typing Speed") {
                        Picker("Speed", selection: $speed) {
                            Text("Instant (Paste)").tag(0)
                            Text("Fast (1200 CPM)").tag(1200)
                            Text("Natural (600 CPM)").tag(600)
                            Text("Slow (300 CPM)").tag(300)
                        }
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
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onSubmit { if canSave { save(); dismiss() } }
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
        }
    }
    
    private func save() {
        switch selectedType {
        case .press:
            let mapping = KeyMapping(keyCode: keyCode, modifiers: modifiers)
            step = .press(mapping)
        case .hold:
            let mapping = KeyMapping(keyCode: keyCode, modifiers: modifiers)
            step = .hold(mapping, duration: duration)
        case .delay:
            step = .delay(duration)
        case .typeText:
            step = .typeText(text, speed: speed)
        case .openApp:
            step = .openApp(bundleIdentifier: appBundleIdentifier, newWindow: openNewWindow)
        case .openLink:
            step = .openLink(url: linkURL)
        }
    }
}

/// Sheet for adding a new step - only adds to list when Save is clicked
struct NewStepEditorSheet: View {
    let initialStep: MacroStep
    let onSave: (MacroStep) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    // Temporary state for editing
    @State private var keyCode: CGKeyCode?
    @State private var modifiers = ModifierFlags()
    @State private var duration: TimeInterval = 0.5
    @State private var text: String = ""
    @State private var speed: Int = 0
    @State private var appBundleIdentifier: String = ""
    @State private var openNewWindow: Bool = false
    @State private var linkURL: String = ""
    @State private var showingAppPicker = false
    @State private var showingBookmarkPicker = false
    @State private var showingKeyboard = false

    @State private var selectedType: StepType

    enum StepType: String, CaseIterable, Identifiable {
        case press = "Key Press"
        case hold = "Hold Key"
        case typeText = "Type Text"
        case delay = "Delay"
        case openApp = "Open App"
        case openLink = "Open Link"
        var id: String { rawValue }
    }

    init(initialStep: MacroStep, onSave: @escaping (MacroStep) -> Void, onCancel: @escaping () -> Void) {
        self.initialStep = initialStep
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
        case .typeText(let txt, let spd):
            _selectedType = State(initialValue: .typeText)
            _text = State(initialValue: txt)
            _speed = State(initialValue: spd)
        case .openApp(let bundleId, let newWindow):
            _selectedType = State(initialValue: .openApp)
            _appBundleIdentifier = State(initialValue: bundleId)
            _openNewWindow = State(initialValue: newWindow)
        case .openLink(let url):
            _selectedType = State(initialValue: .openLink)
            _linkURL = State(initialValue: url)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Step")
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
                    Section("Text to Type") {
                        TextField("Enter text...", text: $text)
                            .textFieldStyle(.roundedBorder)
                    }
                    Section("Typing Speed") {
                        Picker("Speed", selection: $speed) {
                            Text("Instant (Paste)").tag(0)
                            Text("Fast (1200 CPM)").tag(1200)
                            Text("Natural (600 CPM)").tag(600)
                            Text("Slow (300 CPM)").tag(300)
                        }
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
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    if canSave {
                        onSave(buildStep())
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
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
        }
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
            return .typeText(text, speed: speed)
        case .openApp:
            return .openApp(bundleIdentifier: appBundleIdentifier, newWindow: openNewWindow)
        case .openLink:
            return .openLink(url: linkURL)
        }
    }
}
