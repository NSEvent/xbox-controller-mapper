import SwiftUI

struct MacroEditorSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var steps: [MacroStep] = []
    @State private var selection: Set<UUID> = []
    
    // For editing steps
    @State private var editingStepIndex: Int?
    @State private var showingStepEditor = false
    
    let originalMacro: Macro?
    
    init(macro: Macro?) {
        self.originalMacro = macro
        _name = State(initialValue: macro?.name ?? "")
        _steps = State(initialValue: macro?.steps ?? [])
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
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    MacroStepRow(step: step, index: index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingStepIndex = index
                            showingStepEditor = true
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                steps.remove(at: index)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onMove { source, dest in
                    steps.move(fromOffsets: source, toOffset: dest)
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
                        addStep(.delay(0.5))
                    } label: {
                        Label("Delay", systemImage: "timer")
                    }
                    
                    Button {
                        addStep(.typeText("Hello", speed: 0))
                    } label: {
                        Label("Type Text", systemImage: "textformat")
                    }
                    
                    Button {
                        addStep(.hold(KeyMapping(), duration: 1.0))
                    } label: {
                        Label("Hold Key", systemImage: "hand.tap")
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
                .disabled(name.isEmpty || steps.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 20)
        .frame(width: 500, height: 600)
        .sheet(isPresented: $showingStepEditor) {
            if let index = editingStepIndex, index < steps.count {
                StepEditorSheet(step: $steps[index])
            } else {
                // Fallback for new step (not really used this way but safe)
                Text("Error: No step selected")
            }
        }
    }
    
    private func addStep(_ step: MacroStep) {
        steps.append(step)
        editingStepIndex = steps.count - 1
        showingStepEditor = true
    }
    
    private func save() {
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
    
    var body: some View {
        HStack {
            Text("\(index + 1).")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .leading)
            
            icon
                .frame(width: 20)
            
            Text(step.displayString)
                .font(.system(size: 13))
            
            Spacer()
            
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
    
    // To track type changes
    @State private var selectedType: StepType
    
    enum StepType: String, CaseIterable, Identifiable {
        case press = "Key Press"
        case hold = "Hold Key"
        case delay = "Delay"
        case typeText = "Type Text"
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
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Step")
                .font(.headline)
                .padding(.top, 20)
            
            Picker("Type", selection: $selectedType) {
                ForEach(StepType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            Form {
                switch selectedType {
                case .press:
                    Section("Key Combination") {
                        KeyCaptureField(keyCode: $keyCode, modifiers: $modifiers)
                    }
                    
                case .hold:
                    Section("Key Combination") {
                        KeyCaptureField(keyCode: $keyCode, modifiers: $modifiers)
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
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Done") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom)
        }
        .frame(width: 400, height: 450)
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
        }
    }
}
