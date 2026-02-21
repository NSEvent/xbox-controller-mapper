import SwiftUI

struct ScriptEditorSheet: View {
    let script: Script?
    var prefilledExample: ScriptExample?

    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var source: String = ""
    @State private var scriptDescription: String = ""
    @State private var showingAPIReference = false
    @State private var showingExamplesGallery = false
    @State private var showingAIPrompt = false
    @State private var testOutput: String?
    @State private var showingTestResult = false

    private var isEditing: Bool { script != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Script" : "New Script")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name
                    HStack {
                        Text("Name:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        TextField("Script name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Code editor
                    VStack(alignment: .leading, spacing: 4) {
                        Text("JavaScript:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        CodeEditorView(source: $source)
                            .frame(minHeight: 200, maxHeight: 400)
                    }

                    // Description
                    HStack(alignment: .top) {
                        Text("Notes:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        TextField("Optional description", text: $scriptDescription)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Test result
                    if showingTestResult, let output = testOutput {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Test Output:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            ScrollView {
                                Text(output)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.green)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(maxHeight: 100)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer buttons
            HStack {
                Button(action: { showingAPIReference = true }) {
                    Label("API Reference", systemImage: "book")
                }

                Button(action: { showingExamplesGallery = true }) {
                    Label("Examples", systemImage: "square.grid.2x2")
                }

                Button(action: { showingAIPrompt = true }) {
                    Label("AI", systemImage: "sparkles")
                }

                Button(action: runTest) {
                    Label("Test", systemImage: "play.fill")
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Save" : "Add") {
                    saveScript()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 550)
        .onAppear {
            if let script {
                name = script.name
                source = script.source
                scriptDescription = script.description ?? ""
            } else if let example = prefilledExample {
                name = example.name
                source = example.source
                scriptDescription = example.description
            }
        }
        .sheet(isPresented: $showingAPIReference) {
            ScriptAPIReferenceSheet()
        }
        .sheet(isPresented: $showingExamplesGallery) {
            ScriptExamplesGalleryView { example in
                name = example.name
                source = example.source
                scriptDescription = example.description
            }
        }
        .sheet(isPresented: $showingAIPrompt) {
            ScriptAIPromptSheet()
        }
    }

    private func saveScript() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if var existing = script {
            existing.name = trimmedName
            existing.source = source
            existing.description = scriptDescription.isEmpty ? nil : scriptDescription
            existing.modifiedAt = Date()
            profileManager.updateScript(existing)
        } else {
            let newScript = Script(
                name: trimmedName,
                source: source,
                description: scriptDescription.isEmpty ? nil : scriptDescription
            )
            profileManager.addScript(newScript)
        }

        dismiss()
    }

    private func runTest() {
        // Create a temporary ScriptEngine for testing
        let engine = ScriptEngine(
            inputSimulator: MockInputSimulator(),
            inputQueue: DispatchQueue(label: "com.xboxmapper.scripttest")
        )

        let testScript = Script(name: name, source: source)
        let trigger = ScriptTrigger(button: .a, pressType: .press)
        let (result, logs) = engine.executeTest(script: testScript, trigger: trigger)

        var output = logs.joined(separator: "\n")
        switch result {
        case .success:
            if output.isEmpty {
                output = "(Script executed successfully, no output)"
            }
        case .error(let message):
            output += "\nERROR: \(message)"
        }

        testOutput = output
        showingTestResult = true
    }
}

// MARK: - Code Editor

struct CodeEditorView: View {
    @Binding var source: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $source)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)

            if source.isEmpty {
                Text("// Write your JavaScript here...\n// Use press(), type(), app.bundleId, etc.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.black.opacity(0.2))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - API Reference

struct ScriptAPIReferenceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Script API Reference")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    apiSection("Input Simulation", items: [
                        ("press(keyCode)", "Press a key. e.g. press(49) for spacebar"),
                        ("press(keyCode, {command: true})", "Press key with modifiers"),
                        ("hold(keyCode, seconds)", "Hold a key for duration"),
                        ("click()", "Left mouse click. Also: click(\"right\"), click(\"middle\")"),
                        ("type(\"text\")", "Type text character by character"),
                        ("paste(\"text\")", "Paste text via clipboard"),
                        ("pressKey(\"space\")", "Press named key: space, return, tab, escape, up, down, left, right, f1-f15, delete, home, end, pageup, pagedown"),
                    ])

                    apiSection("Application Context", items: [
                        ("app.name", "Frontmost app name (e.g. \"Safari\")"),
                        ("app.bundleId", "Frontmost app bundle ID"),
                        ("app.is(\"com.apple.Safari\")", "Check if specific app is focused"),
                    ])

                    apiSection("System", items: [
                        ("clipboard.get()", "Read clipboard text"),
                        ("clipboard.set(\"text\")", "Set clipboard text"),
                        ("shell(\"command\")", "Run shell command, returns stdout (5s timeout)"),
                        ("shellAsync(\"cmd\", callback?)", "Run in background, controller stays active. Callback receives stdout."),
                        ("openURL(\"https://...\")", "Open URL in default browser"),
                        ("openApp(\"com.apple.Safari\")", "Launch app by bundle ID"),
                        ("expand(\"{date} {time}\")", "Expand variables: {date}, {time}, {app}, etc."),
                        ("delay(seconds)", "Pause execution (max 5s)"),
                    ])

                    apiSection("Persistent State", items: [
                        ("state.get(\"key\")", "Read stored value (survives across invocations)"),
                        ("state.set(\"key\", value)", "Store a value"),
                        ("state.toggle(\"key\")", "Toggle boolean, returns new value"),
                    ])

                    apiSection("Feedback", items: [
                        ("haptic()", "Trigger haptic feedback. Also: haptic(\"light\"), haptic(\"heavy\")"),
                        ("notify(\"message\")", "Show floating HUD notification"),
                    ])

                    apiSection("Trigger Context", items: [
                        ("trigger.button", "Button that triggered: \"a\", \"b\", \"dpadUp\", etc."),
                        ("trigger.pressType", "\"press\", \"longHold\", or \"doubleTap\""),
                        ("trigger.holdDuration", "Hold duration in seconds (for longHold)"),
                    ])

                    apiSection("Logging", items: [
                        ("log(\"message\")", "Log to input log for debugging"),
                    ])
                }
                .padding()
            }
        }
        .frame(width: 550, height: 500)
    }

    private func apiSection(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)

            ForEach(items, id: \.0) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text(item.0)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.orange)
                        .frame(minWidth: 200, alignment: .leading)

                    Text(item.1)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Mock Input Simulator for Testing

/// Minimal mock that does nothing - used for script test execution
private class MockInputSimulator: InputSimulatorProtocol {
    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags) {}
    func keyDown(_ keyCode: CGKeyCode, modifiers: CGEventFlags) {}
    func keyUp(_ keyCode: CGKeyCode) {}
    func holdModifier(_ modifier: CGEventFlags) {}
    func releaseModifier(_ modifier: CGEventFlags) {}
    func releaseAllModifiers() {}
    func isHoldingModifiers(_ modifier: CGEventFlags) -> Bool { false }
    func getHeldModifiers() -> CGEventFlags { [] }
    func moveMouse(dx: CGFloat, dy: CGFloat) {}
    func moveMouseNative(dx: Int, dy: Int) {}
    func warpMouseTo(point: CGPoint) {}
    var isLeftMouseButtonHeld: Bool { false }
    func scroll(dx: CGFloat, dy: CGFloat, phase: CGScrollPhase?, momentumPhase: CGMomentumScrollPhase?, isContinuous: Bool, flags: CGEventFlags) {}
    func executeMapping(_ mapping: KeyMapping) {}
    func startHoldMapping(_ mapping: KeyMapping) {}
    func stopHoldMapping(_ mapping: KeyMapping) {}
    func executeMacro(_ macro: Macro) {}
}
