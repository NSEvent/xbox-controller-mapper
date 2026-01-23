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
            // code is nil for modifier-only shortcuts
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
        if isCapturing {
            nsView.startCapturing()
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else {
            nsView.stopCapturing()
        }
    }
}

class KeyCaptureNSView: NSView {
    var onKeyCapture: ((CGKeyCode?, ModifierFlags) -> Void)?
    var onEscape: (() -> Void)?

    private var localMonitor: Any?
    private var currentModifiers = ModifierFlags()
    private var peakModifiers = ModifierFlags()  // Tracks the maximum set of modifiers held
    private var hasNonModifierKey = false

    override var acceptsFirstResponder: Bool { true }

    func startCapturing() {
        guard localMonitor == nil else { return }

        // Reset state
        currentModifiers = ModifierFlags()
        peakModifiers = ModifierFlags()
        hasNonModifierKey = false

        let eventMask: NSEvent.EventTypeMask = [
            .keyDown, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown
        ]

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            guard let self = self else { return event }

            // Handle mouse clicks - only capture if within our view's bounds
            // (activation click happens via onTapGesture before monitor starts)
            if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
                // Check if click is within our bounds; if outside, stop capturing and pass through
                if let window = self.window {
                    let locationInView = self.convert(event.locationInWindow, from: nil)
                    if !self.bounds.contains(locationInView) {
                        self.stopCapturing()
                        self.onEscape?()
                        return event
                    }
                }

                let mouseKeyCode: CGKeyCode
                switch event.type {
                case .leftMouseDown:
                    mouseKeyCode = KeyCodeMapping.mouseLeftClick
                case .rightMouseDown:
                    mouseKeyCode = KeyCodeMapping.mouseRightClick
                case .otherMouseDown:
                    mouseKeyCode = KeyCodeMapping.mouseMiddleClick
                default:
                    return event
                }

                self.onKeyCapture?(mouseKeyCode, self.currentModifiers)
                self.stopCapturing()
                return nil  // Consume the event
            }

            let modifierOnlyKeys: Set<Int> = [
                kVK_Command, kVK_Shift, kVK_Option, kVK_Control,
                kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl
            ]

            if event.type == .flagsChanged {
                // Track current modifier state
                var mods = ModifierFlags()
                if event.modifierFlags.contains(.command) { mods.command = true }
                if event.modifierFlags.contains(.option) { mods.option = true }
                if event.modifierFlags.contains(.shift) { mods.shift = true }
                if event.modifierFlags.contains(.control) { mods.control = true }

                self.currentModifiers = mods

                // Track the peak (maximum) modifiers held during this capture session
                // This ensures Command+Shift captures both even if released one at a time
                if mods.command { self.peakModifiers.command = true }
                if mods.option { self.peakModifiers.option = true }
                if mods.shift { self.peakModifiers.shift = true }
                if mods.control { self.peakModifiers.control = true }

                // If all modifiers are now released and no regular key was pressed,
                // capture the peak modifiers as a modifier-only shortcut
                if !mods.hasAny && self.peakModifiers.hasAny && !self.hasNonModifierKey {
                    self.onKeyCapture?(nil, self.peakModifiers)
                    self.stopCapturing()
                }

                return nil // Consume modifier events
            }

            // Regular key press (keyDown)
            if event.type == .keyDown {
                // Skip if it's a modifier key being reported as keyDown (shouldn't happen, but safety check)
                if modifierOnlyKeys.contains(Int(event.keyCode)) {
                    return nil
                }

                self.hasNonModifierKey = true

                // Capture the key with current modifiers
                self.onKeyCapture?(CGKeyCode(event.keyCode), self.currentModifiers)
                self.stopCapturing()
                return nil
            }

            return event
        }
    }

    func stopCapturing() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        currentModifiers = ModifierFlags()
        peakModifiers = ModifierFlags()
        hasNonModifierKey = false
    }

    deinit {
        stopCapturing()
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
