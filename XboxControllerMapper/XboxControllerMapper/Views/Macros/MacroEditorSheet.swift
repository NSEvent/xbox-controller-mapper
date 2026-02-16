import SwiftUI
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

                    // Add Step button as last item in list
                    Button {
                        addStep(.press(KeyMapping()))
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.accentColor)
                            Text("Add Step")
                                .font(.system(size: 13))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    .cornerRadius(6)
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
    @State private var pressEnter: Bool = false
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
        case hold = "Key Hold"
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

                // Hidden button for plain Return key
                Button("") { if canSave { save(); dismiss() } }
                    .keyboardShortcut(.defaultAction)
                    .hidden()
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
            step = .typeText(text, speed: speed, pressEnter: pressEnter)
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
    @State private var pressEnter: Bool = false
    @State private var appBundleIdentifier: String = ""
    @State private var openNewWindow: Bool = false
    @State private var linkURL: String = ""
    @State private var showingAppPicker = false
    @State private var showingBookmarkPicker = false
    @State private var showingKeyboard = false

    @State private var selectedType: StepType

    enum StepType: String, CaseIterable, Identifiable {
        case press = "Key Press"
        case hold = "Key Hold"
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
        }
    }
}
