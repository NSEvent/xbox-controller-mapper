import SwiftUI
import AppKit
import Combine

/// Manages the floating on-screen keyboard window
@MainActor
class OnScreenKeyboardManager: ObservableObject {
    static let shared = OnScreenKeyboardManager()

    @Published private(set) var isVisible = false

    private var window: NSWindow?
    private var inputSimulator: InputSimulatorProtocol?

    private init() {}

    /// Sets the input simulator to use for sending key presses
    func setInputSimulator(_ simulator: InputSimulatorProtocol) {
        self.inputSimulator = simulator
    }

    /// Shows the on-screen keyboard window
    func show() {
        guard window == nil else {
            window?.orderFront(nil)
            isVisible = true
            return
        }

        let keyboardView = OnScreenKeyboardView { [weak self] keyCode, modifiers in
            self?.handleKeyPress(keyCode: keyCode, modifiers: modifiers)
        }

        let hostingView = NSHostingView(rootView: keyboardView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Center window on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = window.frame.size
            let x = screenFrame.midX - windowSize.width / 2
            let y = screenFrame.minY + 100  // Position near bottom of screen
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFront(nil)
        self.window = window
        isVisible = true
    }

    /// Hides the on-screen keyboard window
    func hide() {
        window?.orderOut(nil)
        isVisible = false
    }

    /// Toggles the on-screen keyboard visibility
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    private func handleKeyPress(keyCode: CGKeyCode, modifiers: ModifierFlags) {
        guard let simulator = inputSimulator else {
            NSLog("[OnScreenKeyboard] No input simulator configured")
            return
        }

        // Convert ModifierFlags to CGEventFlags
        var eventFlags: CGEventFlags = []
        if modifiers.command { eventFlags.insert(.maskCommand) }
        if modifiers.option { eventFlags.insert(.maskAlternate) }
        if modifiers.shift { eventFlags.insert(.maskShift) }
        if modifiers.control { eventFlags.insert(.maskControl) }

        // Check if this is a mouse click
        if KeyCodeMapping.isMouseButton(keyCode) {
            // Create a temporary mapping for the mouse click
            let mapping = KeyMapping(keyCode: keyCode)
            simulator.executeMapping(mapping)
        } else {
            // Send the key press
            simulator.pressKey(keyCode, modifiers: eventFlags)
        }
    }
}
