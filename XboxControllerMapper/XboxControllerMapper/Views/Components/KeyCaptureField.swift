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
                .help("Clear shortcut")
                .accessibilityLabel("Clear shortcut")
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
                .accessibilityHidden(true)
        )
        .onTapGesture {
            isCapturing = true
        }
        .accessibilityLabel(displayText.isEmpty ? "Key capture field, no shortcut set" : "Key capture field: \(displayText)")
        .accessibilityHint("Click to record a keyboard shortcut. Press any key combination to capture it.")
        .accessibilityValue(displayText.isEmpty ? "Empty" : displayText)
        .accessibilityAddTraits(.isButton)
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

        if modifiers.command { parts.append(ModifierFlags.label(for: modifiers.commandSide) + "⌘") }
        if modifiers.option { parts.append(ModifierFlags.label(for: modifiers.optionSide) + "⌥") }
        if modifiers.shift { parts.append(ModifierFlags.label(for: modifiers.shiftSide) + "⇧") }
        if modifiers.control { parts.append(ModifierFlags.label(for: modifiers.controlSide) + "⌃") }

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
    /// Specific modifier key codes (kVK_Command vs kVK_RightCommand, etc.) seen during this capture.
    /// Lets us preserve left/right identity when the user records just one modifier key on its own.
    private var capturedModifierKeyCodes: [UInt16] = []

    override var acceptsFirstResponder: Bool { true }

    func startCapturing() {
        guard localMonitor == nil else { return }

        // Reset state
        currentModifiers = ModifierFlags()
        peakModifiers = ModifierFlags()
        hasNonModifierKey = false
        capturedModifierKeyCodes = []

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
				if self.window != nil {
                    let locationInView = self.convert(event.locationInWindow, from: nil)
                    if !self.bounds.contains(locationInView) {
                        self.stopCapturing()
                        self.onEscape?()
                        return event
                    }
                }

                // Use buttonNumber for reliable mouse button detection
                // buttonNumber: 0 = left, 1 = right, 2 = middle
                // This correctly handles trackpad two-finger click as right-click
                let mouseKeyCode: CGKeyCode
                switch event.buttonNumber {
                case 0:
                    mouseKeyCode = KeyCodeMapping.mouseLeftClick
                case 1:
                    mouseKeyCode = KeyCodeMapping.mouseRightClick
                default:
                    mouseKeyCode = KeyCodeMapping.mouseMiddleClick
                }

                self.onKeyCapture?(mouseKeyCode, self.currentModifiers)
                self.stopCapturing()
                return nil  // Consume the event
            }

            let modifierOnlyKeys: Set<Int> = [
                kVK_Command, kVK_Shift, kVK_Option, kVK_Control,
                kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl,
                kVK_Function
            ]

            if event.type == .flagsChanged {
                let specificKeyCode = event.keyCode

                // Remember which specific modifier key codes were touched (left vs right).
                if modifierOnlyKeys.contains(Int(specificKeyCode)) &&
                   !self.capturedModifierKeyCodes.contains(specificKeyCode) {
                    self.capturedModifierKeyCodes.append(specificKeyCode)
                }

				// Track current modifier state, preserving side when exactly one side of
				// a modifier has been involved in this capture.
				let mods = Self.modifierFlags(
					from: event.modifierFlags,
					capturedKeyCodes: self.capturedModifierKeyCodes
				)
                self.currentModifiers = mods

                // Track the peak (maximum) modifiers held during this capture session
                // This ensures Command+Shift captures both even if released one at a time
				if mods.command {
					self.peakModifiers.command = true
					self.peakModifiers.commandSide = mods.commandSide
				}
				if mods.option {
					self.peakModifiers.option = true
					self.peakModifiers.optionSide = mods.optionSide
				}
				if mods.shift {
					self.peakModifiers.shift = true
					self.peakModifiers.shiftSide = mods.shiftSide
				}
				if mods.control {
					self.peakModifiers.control = true
					self.peakModifiers.controlSide = mods.controlSide
				}

                // If all modifiers are now released and no regular key was pressed,
                // capture the peak modifiers as a modifier-only shortcut
                if !mods.hasAny && self.peakModifiers.hasAny && !self.hasNonModifierKey {
                    // If the user pressed exactly one modifier key on its own, preserve
                    // the specific left/right key code (e.g. kVK_RightCommand). Otherwise
                    // fall back to the mask-based modifier-only shortcut.
                    let sideAwareCodes = self.capturedModifierKeyCodes.filter { Int($0) != kVK_Function }
                    if sideAwareCodes.count == 1, let code = sideAwareCodes.first {
                        self.onKeyCapture?(CGKeyCode(code), ModifierFlags())
                    } else {
                        self.onKeyCapture?(nil, self.peakModifiers)
                    }
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

	static func modifierFlags(
		from eventFlags: NSEvent.ModifierFlags,
		capturedKeyCodes: [UInt16]
    ) -> ModifierFlags {
		var modifiers = ModifierFlags(
			command: eventFlags.contains(.command),
			option: eventFlags.contains(.option),
			shift: eventFlags.contains(.shift),
			control: eventFlags.contains(.control)
		)

		if modifiers.command {
			modifiers.commandSide = capturedSide(
				leftKey: kVK_Command,
				rightKey: kVK_RightCommand,
				capturedKeyCodes: capturedKeyCodes
			)
		}
		if modifiers.option {
			modifiers.optionSide = capturedSide(
				leftKey: kVK_Option,
				rightKey: kVK_RightOption,
				capturedKeyCodes: capturedKeyCodes
			)
		}
		if modifiers.shift {
			modifiers.shiftSide = capturedSide(
				leftKey: kVK_Shift,
				rightKey: kVK_RightShift,
				capturedKeyCodes: capturedKeyCodes
			)
		}
		if modifiers.control {
			modifiers.controlSide = capturedSide(
				leftKey: kVK_Control,
				rightKey: kVK_RightControl,
				capturedKeyCodes: capturedKeyCodes
			)
		}

		return modifiers
    }

	private static func capturedSide(
		leftKey: Int,
		rightKey: Int,
		capturedKeyCodes: [UInt16]
    ) -> ModifierSide? {
		let hasLeft = capturedKeyCodes.contains(UInt16(leftKey))
		let hasRight = capturedKeyCodes.contains(UInt16(rightKey))

		switch (hasLeft, hasRight) {
		case (true, false): return .left
		case (false, true): return .right
		default: return nil
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
        capturedModifierKeyCodes = []
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
                .accessibilityLabel("Command modifier")

            Toggle("⌥", isOn: $modifiers.option)
                .toggleStyle(.checkbox)
                .accessibilityLabel("Option modifier")

            Toggle("⇧", isOn: $modifiers.shift)
                .toggleStyle(.checkbox)
                .accessibilityLabel("Shift modifier")

            Toggle("⌃", isOn: $modifiers.control)
                .toggleStyle(.checkbox)
                .accessibilityLabel("Control modifier")
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
