import Foundation
import GameController
import Combine

/// Service for managing Xbox controller connection and input
@MainActor
class ControllerService: ObservableObject {
    @Published var isConnected = false
    @Published var connectedController: GCController?
    @Published var controllerName: String = ""

    /// Currently pressed buttons
    @Published var activeButtons: Set<ControllerButton> = []

    /// Left joystick position (-1 to 1)
    @Published var leftStick: CGPoint = .zero

    /// Right joystick position (-1 to 1)
    @Published var rightStick: CGPoint = .zero

    /// Left trigger pressure (0 to 1)
    @Published var leftTriggerValue: Float = 0

    /// Right trigger pressure (0 to 1)
    @Published var rightTriggerValue: Float = 0

    // Button press timestamps for long-hold detection
    var buttonPressTimestamps: [ControllerButton: Date] = [:]

    // Callback for button events
    var onButtonPressed: ((ControllerButton) -> Void)?
    var onButtonReleased: ((ControllerButton, TimeInterval) -> Void)?
    var onChordDetected: ((Set<ControllerButton>) -> Void)?

    // Joystick callbacks
    var onLeftStickMoved: ((CGPoint) -> Void)?
    var onRightStickMoved: ((CGPoint) -> Void)?

    // Chord detection
    private var chordTimer: Timer?
    private let chordWindow: TimeInterval = 0.05  // 50ms window for chord detection
    private var pendingButtons: Set<ControllerButton> = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupNotifications()
        startDiscovery()
        checkConnectedControllers()
    }

    func cleanup() {
        stopDiscovery()
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let controller = notification.object as? GCController {
                    self?.controllerConnected(controller)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let controller = notification.object as? GCController,
                   controller == self?.connectedController {
                    self?.controllerDisconnected()
                }
            }
            .store(in: &cancellables)
    }

    private func startDiscovery() {
        GCController.startWirelessControllerDiscovery {
            print("Wireless controller discovery completed")
        }
    }

    private func stopDiscovery() {
        GCController.stopWirelessControllerDiscovery()
    }

    private func checkConnectedControllers() {
        // Check for already connected controllers
        if let controller = GCController.controllers().first {
            controllerConnected(controller)
        }
    }

    private func controllerConnected(_ controller: GCController) {
        connectedController = controller
        isConnected = true
        controllerName = controller.vendorName ?? "Xbox Controller"

        setupInputHandlers(for: controller)

        print("Controller connected: \(controllerName)")
    }

    private func controllerDisconnected() {
        connectedController = nil
        isConnected = false
        controllerName = ""
        activeButtons.removeAll()
        leftStick = .zero
        rightStick = .zero

        print("Controller disconnected")
    }

    private func setupInputHandlers(for controller: GCController) {
        guard let gamepad = controller.extendedGamepad else {
            print("Controller does not support extended gamepad profile")
            return
        }

        // Face buttons
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.a, pressed: pressed) }
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.b, pressed: pressed) }
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.x, pressed: pressed) }
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.y, pressed: pressed) }
        }

        // Bumpers
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.leftBumper, pressed: pressed) }
        }
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.rightBumper, pressed: pressed) }
        }

        // Triggers (with value for analog sensitivity)
        gamepad.leftTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            Task { @MainActor in
                self?.leftTriggerValue = value
                self?.handleButton(.leftTrigger, pressed: pressed)
            }
        }
        gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            Task { @MainActor in
                self?.rightTriggerValue = value
                self?.handleButton(.rightTrigger, pressed: pressed)
            }
        }

        // D-pad
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.dpadUp, pressed: pressed) }
        }
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.dpadDown, pressed: pressed) }
        }
        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.dpadLeft, pressed: pressed) }
        }
        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.dpadRight, pressed: pressed) }
        }

        // Special buttons
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.menu, pressed: pressed) }
        }
        gamepad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.view, pressed: pressed) }
        }
        gamepad.buttonHome?.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.xbox, pressed: pressed) }
        }

        // Share button (Xbox Series controllers)
        if let xboxGamepad = gamepad as? GCXboxGamepad {
            xboxGamepad.buttonShare?.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in self?.handleButton(.share, pressed: pressed) }
            }
        }

        // Thumbstick clicks
        gamepad.leftThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.leftThumbstick, pressed: pressed) }
        }
        gamepad.rightThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handleButton(.rightThumbstick, pressed: pressed) }
        }

        // Left joystick
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            Task { @MainActor in
                let point = CGPoint(x: CGFloat(xValue), y: CGFloat(yValue))
                self?.leftStick = point
                self?.onLeftStickMoved?(point)
            }
        }

        // Right joystick
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            Task { @MainActor in
                let point = CGPoint(x: CGFloat(xValue), y: CGFloat(yValue))
                self?.rightStick = point
                self?.onRightStickMoved?(point)
            }
        }
    }

    private func handleButton(_ button: ControllerButton, pressed: Bool) {
        if pressed {
            buttonPressed(button)
        } else {
            buttonReleased(button)
        }
    }

    private func buttonPressed(_ button: ControllerButton) {
        guard !activeButtons.contains(button) else { return }

        activeButtons.insert(button)
        buttonPressTimestamps[button] = Date()

        // Add to pending buttons for chord detection
        pendingButtons.insert(button)

        // Reset chord timer
        chordTimer?.invalidate()
        chordTimer = Timer.scheduledTimer(withTimeInterval: chordWindow, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.processChordOrSinglePress()
            }
        }
    }

    private func buttonReleased(_ button: ControllerButton) {
        guard activeButtons.contains(button) else { return }

        activeButtons.remove(button)

        // Calculate hold duration
        let holdDuration: TimeInterval
        if let pressTime = buttonPressTimestamps[button] {
            holdDuration = Date().timeIntervalSince(pressTime)
        } else {
            holdDuration = 0
        }

        buttonPressTimestamps.removeValue(forKey: button)
        pendingButtons.remove(button)

        onButtonReleased?(button, holdDuration)
    }

    private func processChordOrSinglePress() {
        if pendingButtons.count >= 2 {
            // Chord detected
            onChordDetected?(pendingButtons)
        } else if let button = pendingButtons.first {
            // Single button press
            onButtonPressed?(button)
        }

        pendingButtons.removeAll()
    }

    /// Trigger haptic feedback on the controller
    func triggerHaptic(intensity: Float = 0.5, duration: TimeInterval = 0.1) {
        // Haptics API varies by controller - this is a placeholder
        // Real implementation would use CHHapticEngine for supported controllers
        print("Haptic feedback requested: intensity=\(intensity), duration=\(duration)")
    }

    /// Manually trigger the Guide button press (e.g. from EventTap)
    func triggerGuideButton() {
        print("Triggering Guide button from external source")
        handleButton(.xbox, pressed: true)
        
        // Release it shortly after to simulate a tap
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.handleButton(.xbox, pressed: false)
        }
    }
}
