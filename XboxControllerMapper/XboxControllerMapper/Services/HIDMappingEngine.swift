import Foundation
import Combine
import Dispatch

/// Coordinates HID controller input with profile mappings and input simulation
@MainActor
class HIDMappingEngine: ObservableObject {
    @Published var isEnabled = true

    private let controllerService: HIDControllerService
    private let profileManager: ProfileManager
    private let appMonitor: AppMonitor
    private let inputSimulator = InputSimulator()

    /// Tracks which buttons are currently being held (for hold-type mappings)
    private var heldButtons: [ControllerButton: KeyMapping] = [:]

    /// Tracks buttons that are part of an active chord
    private var activeChordButtons: Set<ControllerButton> = []

    /// DispatchSourceTimer for joystick polling
    private var joystickTimer: DispatchSourceTimer?
    private let joystickPollInterval: TimeInterval = 1.0 / 60.0  // 60 Hz

    private var cancellables = Set<AnyCancellable>()

    init(controllerService: HIDControllerService, profileManager: ProfileManager, appMonitor: AppMonitor) {
        self.controllerService = controllerService
        self.profileManager = profileManager
        self.appMonitor = appMonitor

        setupBindings()
    }

    private func setupBindings() {
        // Button press handler
        controllerService.onButtonPressed = { [weak self] button in
            DispatchQueue.main.async {
                self?.handleButtonPressed(button)
            }
        }

        // Button release handler
        controllerService.onButtonReleased = { [weak self] button, duration in
            DispatchQueue.main.async {
                self?.handleButtonReleased(button, holdDuration: duration)
            }
        }

        // Chord handler
        controllerService.onChordDetected = { [weak self] buttons in
            DispatchQueue.main.async {
                self?.handleChord(buttons)
            }
        }

        // Start joystick polling when controller connects
        controllerService.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                if connected {
                    self?.startJoystickPolling()
                } else {
                    self?.stopJoystickPolling()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Button Handling

    private func handleButtonPressed(_ button: ControllerButton) {
        guard isEnabled else { return }
        guard let profile = profileManager.activeProfile else { return }

        #if DEBUG
        print("🎮 HIDMappingEngine: Processing button press: \(button.displayName)")
        #endif

        guard let mapping = profile.effectiveMapping(for: button, appBundleId: appMonitor.frontmostBundleId) else {
            return
        }

        if mapping.isHoldModifier {
            heldButtons[button] = mapping
            inputSimulator.startHoldMapping(mapping)
        }
    }

    private func handleButtonReleased(_ button: ControllerButton, holdDuration: TimeInterval) {
        guard isEnabled else { return }
        guard let profile = profileManager.activeProfile else { return }

        if activeChordButtons.contains(button) {
            activeChordButtons.remove(button)
            return
        }

        if let heldMapping = heldButtons[button] {
            inputSimulator.stopHoldMapping(heldMapping)
            heldButtons.removeValue(forKey: button)
            return
        }

        guard let mapping = profile.effectiveMapping(for: button, appBundleId: appMonitor.frontmostBundleId) else {
            return
        }

        guard !mapping.isHoldModifier else { return }

        if let longHoldMapping = mapping.longHoldMapping,
           holdDuration >= longHoldMapping.threshold,
           !longHoldMapping.isEmpty {
            executeLongHoldMapping(longHoldMapping)
        } else {
            inputSimulator.executeMapping(mapping)
        }
    }

    private func executeLongHoldMapping(_ mapping: LongHoldMapping) {
        if let keyCode = mapping.keyCode {
            inputSimulator.pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        } else if mapping.modifiers.hasAny {
            let flags = mapping.modifiers.cgEventFlags
            inputSimulator.holdModifier(flags)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.inputSimulator.releaseModifier(flags)
            }
        }
    }

    private func handleChord(_ buttons: Set<ControllerButton>) {
        guard isEnabled else { return }
        guard let profile = profileManager.activeProfile else { return }

        let matchingChord = profile.chordMappings.first { chord in
            chord.buttons == buttons
        }

        guard let chord = matchingChord else { return }

        activeChordButtons = buttons

        if let keyCode = chord.keyCode {
            inputSimulator.pressKey(keyCode, modifiers: chord.modifiers.cgEventFlags)
        } else if chord.modifiers.hasAny {
            let flags = chord.modifiers.cgEventFlags
            inputSimulator.holdModifier(flags)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.inputSimulator.releaseModifier(flags)
            }
        }
    }

    // MARK: - Joystick Handling

    private func startJoystickPolling() {
        stopJoystickPolling()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: joystickPollInterval)
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.processJoysticks()
            }
        }
        timer.resume()
        joystickTimer = timer

        #if DEBUG
        print("🎮 HID Joystick polling started")
        #endif
    }

    private func stopJoystickPolling() {
        joystickTimer?.cancel()
        joystickTimer = nil
    }

    private func processJoysticks() {
        guard isEnabled else { return }
        guard let settings = profileManager.activeProfile?.joystickSettings else { return }

        let leftStick = controllerService.leftStick
        processMouseMovement(leftStick, settings: settings)

        let rightStick = controllerService.rightStick
        processScrolling(rightStick, settings: settings)
    }

    private func processMouseMovement(_ stick: CGPoint, settings: JoystickSettings) {
        let magnitude = sqrt(stick.x * stick.x + stick.y * stick.y)
        guard magnitude > settings.mouseDeadzone else { return }

        let normalizedMagnitude = (magnitude - settings.mouseDeadzone) / (1.0 - settings.mouseDeadzone)
        let acceleratedMagnitude = pow(normalizedMagnitude, settings.mouseAccelerationExponent)

        let dx = (stick.x / magnitude) * acceleratedMagnitude * settings.mouseMultiplier
        var dy = (stick.y / magnitude) * acceleratedMagnitude * settings.mouseMultiplier

        dy = settings.invertMouseY ? dy : -dy

        inputSimulator.moveMouse(dx: dx, dy: dy)
    }

    private func processScrolling(_ stick: CGPoint, settings: JoystickSettings) {
        let magnitude = sqrt(stick.x * stick.x + stick.y * stick.y)
        guard magnitude > settings.scrollDeadzone else { return }

        let normalizedMagnitude = (magnitude - settings.scrollDeadzone) / (1.0 - settings.scrollDeadzone)
        let acceleratedMagnitude = pow(normalizedMagnitude, settings.scrollAccelerationExponent)

        let dx = (stick.x / magnitude) * acceleratedMagnitude * settings.scrollMultiplier
        var dy = (stick.y / magnitude) * acceleratedMagnitude * settings.scrollMultiplier

        dy = settings.invertScrollY ? -dy : dy

        inputSimulator.scroll(dx: dx, dy: dy)
    }

    // MARK: - Control

    func enable() {
        isEnabled = true
    }

    func disable() {
        isEnabled = false
        for (_, mapping) in heldButtons {
            inputSimulator.stopHoldMapping(mapping)
        }
        heldButtons.removeAll()
        inputSimulator.releaseAllModifiers()
    }

    func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }
}
