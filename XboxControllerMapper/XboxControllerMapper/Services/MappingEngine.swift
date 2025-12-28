import Foundation
import Combine

/// Coordinates controller input with profile mappings and input simulation
@MainActor
class MappingEngine: ObservableObject {
    @Published var isEnabled = true

    private let controllerService: ControllerService
    private let profileManager: ProfileManager
    private let appMonitor: AppMonitor
    private let inputSimulator = InputSimulator()

    /// Tracks which buttons are currently being held (for hold-type mappings)
    private var heldButtons: [ControllerButton: KeyMapping] = [:]

    /// Tracks buttons that are part of an active chord
    private var activeChordButtons: Set<ControllerButton> = []

    /// Timer for joystick polling
    private var joystickTimer: Timer?
    private let joystickPollInterval: TimeInterval = 1.0 / 60.0  // 60 Hz

    private var cancellables = Set<AnyCancellable>()

    init(controllerService: ControllerService, profileManager: ProfileManager, appMonitor: AppMonitor) {
        self.controllerService = controllerService
        self.profileManager = profileManager
        self.appMonitor = appMonitor

        setupBindings()
    }

    private func setupBindings() {
        // Button press handler
        controllerService.onButtonPressed = { [weak self] button in
            Task { @MainActor in
                self?.handleButtonPressed(button)
            }
        }

        // Button release handler
        controllerService.onButtonReleased = { [weak self] button, duration in
            Task { @MainActor in
                self?.handleButtonReleased(button, holdDuration: duration)
            }
        }

        // Chord handler
        controllerService.onChordDetected = { [weak self] buttons in
            Task { @MainActor in
                self?.handleChord(buttons)
            }
        }

        // Start joystick polling when controller connects
        controllerService.$isConnected
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

        // Get the effective mapping (considering app overrides)
        guard let mapping = profile.effectiveMapping(for: button, appBundleId: appMonitor.frontmostBundleId) else {
            return
        }

        // For hold-type mappings, start holding immediately
        if mapping.isHoldModifier {
            heldButtons[button] = mapping
            inputSimulator.startHoldMapping(mapping)
        }
        // For non-hold mappings, we wait for release to determine tap vs long-hold
    }

    private func handleButtonReleased(_ button: ControllerButton, holdDuration: TimeInterval) {
        guard isEnabled else { return }
        guard let profile = profileManager.activeProfile else { return }

        // If this button was part of a chord, skip individual handling
        if activeChordButtons.contains(button) {
            activeChordButtons.remove(button)
            return
        }

        // If this was a held modifier, release it
        if let heldMapping = heldButtons[button] {
            inputSimulator.stopHoldMapping(heldMapping)
            heldButtons.removeValue(forKey: button)
            return
        }

        // Get the effective mapping
        guard let mapping = profile.effectiveMapping(for: button, appBundleId: appMonitor.frontmostBundleId) else {
            return
        }

        // Skip if this is a hold modifier (already handled)
        guard !mapping.isHoldModifier else { return }

        // Check for long hold
        if let longHoldMapping = mapping.longHoldMapping,
           holdDuration >= longHoldMapping.threshold,
           !longHoldMapping.isEmpty {
            // Execute long hold mapping
            executeLongHoldMapping(longHoldMapping)
        } else {
            // Execute normal mapping
            inputSimulator.executeMapping(mapping)
        }
    }

    private func executeLongHoldMapping(_ mapping: LongHoldMapping) {
        if let keyCode = mapping.keyCode {
            inputSimulator.pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        } else if mapping.modifiers.hasAny {
            // Modifier-only long hold
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

        // Find matching chord mapping
        let matchingChord = profile.chordMappings.first { chord in
            chord.buttons == buttons
        }

        guard let chord = matchingChord else {
            // No chord match - process buttons individually
            return
        }

        // Mark these buttons as part of a chord
        activeChordButtons = buttons

        // Execute chord mapping
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

        joystickTimer = Timer.scheduledTimer(withTimeInterval: joystickPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.processJoysticks()
            }
        }
    }

    private func stopJoystickPolling() {
        joystickTimer?.invalidate()
        joystickTimer = nil
    }

    private func processJoysticks() {
        guard isEnabled else { return }
        guard let settings = profileManager.activeProfile?.joystickSettings else { return }

        // Process left joystick (mouse)
        let leftStick = controllerService.leftStick
        processMouseMovement(leftStick, settings: settings)

        // Process right joystick (scroll)
        let rightStick = controllerService.rightStick
        processScrolling(rightStick, settings: settings)
    }

    private func processMouseMovement(_ stick: CGPoint, settings: JoystickSettings) {
        // Apply deadzone
        let magnitude = sqrt(stick.x * stick.x + stick.y * stick.y)
        guard magnitude > settings.mouseDeadzone else { return }

        // Normalize and apply deadzone
        let normalizedMagnitude = (magnitude - settings.mouseDeadzone) / (1.0 - settings.mouseDeadzone)

        // Apply acceleration curve using the 0-1 acceleration setting
        let acceleratedMagnitude = pow(normalizedMagnitude, settings.mouseAccelerationExponent)

        // Calculate direction using the converted multiplier
        let dx = (stick.x / magnitude) * acceleratedMagnitude * settings.mouseMultiplier
        var dy = (stick.y / magnitude) * acceleratedMagnitude * settings.mouseMultiplier

        // Invert Y if needed (joystick Y is inverted compared to screen coordinates)
        dy = settings.invertMouseY ? dy : -dy

        inputSimulator.moveMouse(dx: dx, dy: dy)
    }

    private func processScrolling(_ stick: CGPoint, settings: JoystickSettings) {
        // Apply deadzone
        let magnitude = sqrt(stick.x * stick.x + stick.y * stick.y)
        guard magnitude > settings.scrollDeadzone else { return }

        // Normalize and apply deadzone
        let normalizedMagnitude = (magnitude - settings.scrollDeadzone) / (1.0 - settings.scrollDeadzone)

        // Apply acceleration curve using the 0-1 acceleration setting
        let acceleratedMagnitude = pow(normalizedMagnitude, settings.scrollAccelerationExponent)

        // Calculate direction using the converted multiplier
        let dx = (stick.x / magnitude) * acceleratedMagnitude * settings.scrollMultiplier
        var dy = (stick.y / magnitude) * acceleratedMagnitude * settings.scrollMultiplier

        // Invert Y if needed
        dy = settings.invertScrollY ? -dy : dy

        inputSimulator.scroll(dx: dx, dy: dy)
    }

    // MARK: - Control

    func enable() {
        isEnabled = true
    }

    func disable() {
        isEnabled = false
        // Release any held buttons
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
