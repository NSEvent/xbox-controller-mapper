import Foundation
import Combine

/// Coordinates controller input with profile mappings and input simulation
@MainActor
class MappingEngine: ObservableObject {
    @Published var isEnabled = true

    private let controllerService: ControllerService
    private let profileManager: ProfileManager
    private let appMonitor: AppMonitor
    private let inputSimulator: InputSimulatorProtocol

    /// Tracks which buttons are currently being held (for hold-type mappings)
    private var heldButtons: [ControllerButton: KeyMapping] = [:]

    /// Tracks buttons that are part of an active chord
    private var activeChordButtons: Set<ControllerButton> = []

    /// Tracks last tap time for each button (for double-tap detection)
    private var lastTapTime: [ControllerButton: Date] = [:]

    /// Tracks pending single-tap work items (cancelled if double-tap detected)
    private var pendingSingleTap: [ControllerButton: DispatchWorkItem] = [:]

    /// Timers for detecting long holds while button is pressed
    private var longHoldTimers: [ControllerButton: DispatchWorkItem] = [:]

    /// Tracks buttons that have already triggered their long-hold action during the current press
    private var longHoldTriggered: Set<ControllerButton> = []

    /// Timer for joystick polling
    private var joystickTimer: Timer?
    private let joystickPollInterval: TimeInterval = 1.0 / 60.0  // 60 Hz

    private var cancellables = Set<AnyCancellable>()

    init(controllerService: ControllerService, profileManager: ProfileManager, appMonitor: AppMonitor, inputSimulator: InputSimulatorProtocol = InputSimulator()) {
        self.controllerService = controllerService
        self.profileManager = profileManager
        self.appMonitor = appMonitor
        self.inputSimulator = inputSimulator

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

        #if DEBUG
        print("🔵 handleButtonPressed: \(button.displayName) isHoldModifier=\(mapping.isHoldModifier)")
        #endif

        // For hold-type mappings, start holding immediately
        if mapping.isHoldModifier {
            heldButtons[button] = mapping
            inputSimulator.startHoldMapping(mapping)
            return
        }
        
        // Schedule long hold timer if configured
        if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.handleLongHoldTriggered(button, mapping: longHold)
                }
            }
            longHoldTimers[button] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + longHold.threshold, execute: workItem)
        }
    }
    
    private func handleLongHoldTriggered(_ button: ControllerButton, mapping: LongHoldMapping) {
        longHoldTriggered.insert(button)
        executeLongHoldMapping(mapping)
        
        #if DEBUG
        print("⏱️ Long hold triggered for \(button.displayName)")
        #endif
    }

    private func handleButtonReleased(_ button: ControllerButton, holdDuration: TimeInterval) {
        #if DEBUG
        print("🔘 handleButtonReleased: \(button.displayName) duration=\(holdDuration)")
        #endif

        // Cancel pending long hold timer since button was released
        if let timer = longHoldTimers[button] {
            timer.cancel()
            longHoldTimers.removeValue(forKey: button)
        }

        guard isEnabled else {
            #if DEBUG
            print("   ❌ Engine is disabled")
            #endif
            return
        }
        guard let profile = profileManager.activeProfile else {
            #if DEBUG
            print("   ❌ No active profile")
            #endif
            return
        }

        // If this button was part of a chord, skip individual handling
        if activeChordButtons.contains(button) {
            activeChordButtons.remove(button)
            #if DEBUG
            print("   ⏭️ Was part of chord, skipping")
            #endif
            return
        }

        // If this was a held modifier, release it
        if let heldMapping = heldButtons[button] {
            inputSimulator.stopHoldMapping(heldMapping)
            heldButtons.removeValue(forKey: button)
            #if DEBUG
            print("   🔓 Released held modifier")
            #endif
            return
        }

        // Get the effective mapping
        guard let mapping = profile.effectiveMapping(for: button, appBundleId: appMonitor.frontmostBundleId) else {
            #if DEBUG
            print("   ❌ No mapping found for \(button.displayName)")
            print("   Available mappings: \(profile.buttonMappings.keys.map { $0.displayName })")
            #endif
            return
        }

        #if DEBUG
        print("   ✅ Found mapping: \(mapping.displayString)")
        #endif

        // Skip if this is a hold modifier (already handled)
        guard !mapping.isHoldModifier else { return }

        // If long hold was already triggered while holding, we're done
        if longHoldTriggered.contains(button) {
            longHoldTriggered.remove(button)
            #if DEBUG
            print("   ⏭️ Long hold already executed, skipping release actions")
            #endif
            return
        }

        // Check for long hold fallback (in case timer didn't fire but duration met)
        if let longHoldMapping = mapping.longHoldMapping,
           holdDuration >= longHoldMapping.threshold,
           !longHoldMapping.isEmpty {
            // Cancel any pending single-tap since this was a long hold
            pendingSingleTap[button]?.cancel()
            pendingSingleTap.removeValue(forKey: button)
            lastTapTime.removeValue(forKey: button)
            executeLongHoldMapping(longHoldMapping)
            return
        }

        // Check for double-tap
        if let doubleTapMapping = mapping.doubleTapMapping, !doubleTapMapping.isEmpty {
            let now = Date()

            // Check if there's a pending single-tap (meaning first tap already happened)
            if let pending = pendingSingleTap[button],
               let lastTap = lastTapTime[button],
               now.timeIntervalSince(lastTap) <= doubleTapMapping.threshold {
                // This is a double-tap - cancel the pending single-tap
                pending.cancel()
                pendingSingleTap.removeValue(forKey: button)
                lastTapTime.removeValue(forKey: button)
                executeDoubleTapMapping(doubleTapMapping)
                return
            }

            // This might be the first tap of a double-tap sequence
            // Schedule a delayed single-tap that can be cancelled if second tap comes
            lastTapTime[button] = now
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.pendingSingleTap.removeValue(forKey: button)
                    self?.lastTapTime.removeValue(forKey: button)
                    self?.inputSimulator.executeMapping(mapping)
                }
            }
            pendingSingleTap[button] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapMapping.threshold, execute: workItem)
        } else {
            // No double-tap mapping - execute immediately
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

    private func executeDoubleTapMapping(_ mapping: DoubleTapMapping) {
        if let keyCode = mapping.keyCode {
            inputSimulator.pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        } else if mapping.modifiers.hasAny {
            // Modifier-only double tap
            let flags = mapping.modifiers.cgEventFlags
            inputSimulator.holdModifier(flags)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.inputSimulator.releaseModifier(flags)
            }
        }
    }

    private func handleChord(_ buttons: Set<ControllerButton>) {
        #if DEBUG
        print("🔍 handleChord: buttons=\(buttons.map { $0.displayName })")
        #endif
        guard isEnabled else { return }
        guard let profile = profileManager.activeProfile else { return }

        // Find matching chord mapping
        let matchingChord = profile.chordMappings.first { chord in
            chord.buttons == buttons
        }

        guard let chord = matchingChord else {
            // No chord match - process buttons individually
            let sortedButtons = buttons.sorted { button1, button2 in
                let map1 = profile.effectiveMapping(for: button1, appBundleId: appMonitor.frontmostBundleId)
                let map2 = profile.effectiveMapping(for: button2, appBundleId: appMonitor.frontmostBundleId)
                
                let isMod1 = map1?.isHoldModifier ?? false
                let isMod2 = map2?.isHoldModifier ?? false
                
                return isMod1 && !isMod2
            }
            
            #if DEBUG
            print("   ⏭️ Fallback to individual: \(sortedButtons.map { $0.displayName })")
            #endif
            
            for button in sortedButtons {
                handleButtonPressed(button)
            }
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
        // Cancel any pending single-taps
        for (_, workItem) in pendingSingleTap {
            workItem.cancel()
        }
        pendingSingleTap.removeAll()
        
        // Cancel long hold timers
        for (_, workItem) in longHoldTimers {
            workItem.cancel()
        }
        longHoldTimers.removeAll()
        longHoldTriggered.removeAll()
        
        lastTapTime.removeAll()
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
