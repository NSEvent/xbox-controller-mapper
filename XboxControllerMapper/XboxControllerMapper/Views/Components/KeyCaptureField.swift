import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A field that captures keyboard shortcuts from user input
struct KeyCaptureField: View {
    @Binding var keyCode: CGKeyCode?
    @Binding var modifiers: ModifierFlags

    @State private var isCapturing = false
    @State private var displayText = ""

    var body: some View {
        HStack {
            Text(displayText.isEmpty ? "Click to record" : displayText)
                .foregroundColor(displayText.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !displayText.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCapturing ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isCapturing ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                )
        )
        .overlay(
            KeyCaptureOverlay(isCapturing: $isCapturing, keyCode: $keyCode, modifiers: $modifiers)
                .opacity(0.01) // Nearly invisible but captures events
        )
        .onTapGesture {
            isCapturing = true
        }
        .onChange(of: keyCode) { _, _ in
            updateDisplayText()
        }
        .onChange(of: modifiers) { _, _ in
            updateDisplayText()
        }
        .onAppear {
            updateDisplayText()
        }
    }

    private func updateDisplayText() {
        var parts: [String] = []

        if modifiers.command { parts.append("⌘") }
        if modifiers.option { parts.append("⌥") }
        if modifiers.shift { parts.append("⇧") }
        if modifiers.control { parts.append("⌃") }

        if let keyCode = keyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        }

        displayText = parts.joined(separator: " + ")
    }

    private func clear() {
        keyCode = nil
        modifiers = ModifierFlags()
        displayText = ""
    }
}

/// NSView-based overlay to capture keyboard events
struct KeyCaptureOverlay: NSViewRepresentable {
    @Binding var isCapturing: Bool
    @Binding var keyCode: CGKeyCode?
    @Binding var modifiers: ModifierFlags

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyCapture = { code, mods in
            self.keyCode = code
            self.modifiers = mods
            self.isCapturing = false
        }
        view.onEscape = {
            self.isCapturing = false
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.isCapturing = isCapturing
        if isCapturing {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class KeyCaptureNSView: NSView {
    var isCapturing = false
    var onKeyCapture: ((CGKeyCode, ModifierFlags) -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        let keyCode = CGKeyCode(event.keyCode)

        // Check for escape to cancel
        if keyCode == CGKeyCode(kVK_Escape) {
            onEscape?()
            return
        }

        // Skip modifier-only key presses
        let modifierOnlyKeys: Set<Int> = [
            kVK_Command, kVK_Shift, kVK_Option, kVK_Control,
            kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl
        ]
        if modifierOnlyKeys.contains(Int(event.keyCode)) {
            return
        }

        // Capture the key with modifiers
        var mods = ModifierFlags()
        if event.modifierFlags.contains(.command) { mods.command = true }
        if event.modifierFlags.contains(.option) { mods.option = true }
        if event.modifierFlags.contains(.shift) { mods.shift = true }
        if event.modifierFlags.contains(.control) { mods.control = true }

        onKeyCapture?(keyCode, mods)
    }

    override func flagsChanged(with event: NSEvent) {
        // Could capture modifier-only shortcuts here if needed
        super.flagsChanged(with: event)
    }
}

/// A picker for selecting from predefined keys
struct KeyPicker: View {
    @Binding var keyCode: CGKeyCode?

    var body: some View {
        Picker("Key", selection: $keyCode) {
            Text("None").tag(nil as CGKeyCode?)

            ForEach(KeyCodeMapping.allKeyOptions, id: \.code) { option in
                Text(option.name).tag(option.code as CGKeyCode?)
            }
        }
    }
}

/// Checkboxes for modifier selection
struct ModifierPicker: View {
    @Binding var modifiers: ModifierFlags

    var body: some View {
        HStack(spacing: 16) {
            Toggle("⌘", isOn: $modifiers.command)
                .toggleStyle(.checkbox)

            Toggle("⌥", isOn: $modifiers.option)
                .toggleStyle(.checkbox)

            Toggle("⇧", isOn: $modifiers.shift)
                .toggleStyle(.checkbox)

            Toggle("⌃", isOn: $modifiers.control)
                .toggleStyle(.checkbox)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        KeyCaptureField(keyCode: .constant(nil), modifiers: .constant(ModifierFlags()))

        KeyCaptureField(keyCode: .constant(KeyCodeMapping.space), modifiers: .constant(.command))
    }
    .padding()
    .frame(width: 300)
}
