import Foundation
import Combine
import CoreGraphics

/// Coordinates controller input with profile mappings and input simulation
@MainActor
class MappingEngine: ObservableObject {
    @Published var isEnabled = true

    private let controllerService: ControllerService
    private let profileManager: ProfileManager
    private let appMonitor: AppMonitor
    nonisolated private let inputSimulator: InputSimulatorProtocol
    private let inputLogService: InputLogService?

    /// Tracks which buttons are currently being held (for hold-type mappings)
    private var heldButtons: [ControllerButton: KeyMapping] = [:]

    /// Tracks buttons that are part of an active chord
    private var activeChordButtons: Set<ControllerButton> = []

    /// Tracks last tap time for each button (for double-tap detection)
    private var lastTapTime: [ControllerButton: Date] = [:]

    /// Tracks pending single-tap work items (cancelled if double-tap detected)
    private var pendingSingleTap: [ControllerButton: DispatchWorkItem] = [:]

    /// Tracks pending individual release actions (cancelled if chord detected)
    private var pendingReleaseActions: [ControllerButton: DispatchWorkItem] = [:]

    /// Timers for detecting long holds while button is pressed
    private var longHoldTimers: [ControllerButton: DispatchWorkItem] = [:]

    /// Tracks buttons that have already triggered their long-hold action during the current press
    private var longHoldTriggered: Set<ControllerButton> = []

    /// Timers for repeat-while-held functionality
    private var repeatTimers: [ControllerButton: DispatchSourceTimer] = [:]

    /// Timer for joystick polling (using DispatchSourceTimer for lower overhead)
    private var joystickTimer: DispatchSourceTimer?
    private let joystickPollInterval: TimeInterval = 1.0 / 1000.0  // 1000 Hz

    // MARK: - Loop State
    private let pollingQueue = DispatchQueue(label: "com.xboxmapper.polling", qos: .userInteractive)
    
    private final class LoopState: @unchecked Sendable {
        let lock = NSLock()
        var settings: JoystickSettings?
        var isEnabled = true
        
        var smoothedLeftStick: CGPoint = .zero
        var smoothedRightStick: CGPoint = .zero
        var lastJoystickSampleTime: TimeInterval = 0
        
        var rightStickWasOutsideDeadzone = false
        var rightStickPeakYAbs: Double = 0
        var rightStickLastDirection: Int = 0
        var lastRightStickTapTime: TimeInterval = 0
        var lastRightStickTapDirection: Int = 0
        var scrollBoostDirection: Int = 0
        
        func reset() {
            smoothedLeftStick = .zero
            smoothedRightStick = .zero
            lastJoystickSampleTime = 0
            rightStickWasOutsideDeadzone = false
            rightStickPeakYAbs = 0
            rightStickLastDirection = 0
            lastRightStickTapTime = 0
            lastRightStickTapDirection = 0
            scrollBoostDirection = 0
        }
    }
    
    private let loopState = LoopState()

    private let minJoystickCutoffHz: Double = 4.0
    private let maxJoystickCutoffHz: Double = 14.0
    private let scrollTapThreshold: Double = 0.45
    private let scrollDoubleTapWindow: TimeInterval = 0.4
    private let scrollTapDirectionRatio: Double = 0.8

    private var cancellables = Set<AnyCancellable>()

    init(controllerService: ControllerService, profileManager: ProfileManager, appMonitor: AppMonitor, inputSimulator: InputSimulatorProtocol = InputSimulator(), inputLogService: InputLogService? = nil) {
        self.controllerService = controllerService
        self.profileManager = profileManager
        self.appMonitor = appMonitor
        self.inputSimulator = inputSimulator
        self.inputLogService = inputLogService

        setupBindings()
        
        // Sync initial settings
        self.loopState.settings = profileManager.activeProfile?.joystickSettings
        
        // Observe profile changes to update thread-safe settings
        profileManager.$activeProfile
            .sink { [weak self] profile in
                self?._updateSettingsOnMain(profile?.joystickSettings)
            }
            .store(in: &cancellables)
    }
    
    private func _updateSettingsOnMain(_ settings: JoystickSettings?) {
        loopState.lock.lock()
        loopState.settings = settings
        loopState.lock.unlock()
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
        print("🔵 handleButtonPressed: \(button.displayName) (\(button.rawValue))")
        print("   isHoldModifier=\(mapping.isHoldModifier)")
        print("   modifiers: cmd=\(mapping.modifiers.command) opt=\(mapping.modifiers.option) shift=\(mapping.modifiers.shift) ctrl=\(mapping.modifiers.control)")
        print("   keyCode: \(mapping.keyCode?.description ?? "nil")")
        #endif

        // For hold-type mappings, start holding immediately - but only if button is still pressed
        if mapping.isHoldModifier {
            // Check for double-tap before starting hold modifier
            if let doubleTapMapping = mapping.doubleTapMapping, !doubleTapMapping.isEmpty {
                let now = Date()
                if let lastTap = lastTapTime[button],
                   now.timeIntervalSince(lastTap) <= doubleTapMapping.threshold {
                    // This is a double-tap - execute double-tap action instead of hold
                    lastTapTime.removeValue(forKey: button)
                    executeDoubleTapMapping(doubleTapMapping)
                    inputLogService?.log(buttons: [button], type: .doubleTap, action: doubleTapMapping.displayString)
                    #if DEBUG
                    print("   ⏩ Double-tap detected on hold modifier, executing double-tap action")
                    #endif
                    return
                }
                // Record this tap time for potential double-tap detection
                lastTapTime[button] = now
            }

            // Check if button is still actually pressed (it might have been released
            // during the chord detection window for quick taps)
            if controllerService.activeButtons.contains(button) {
                heldButtons[button] = mapping
                inputSimulator.startHoldMapping(mapping)
                inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)
            } else {
                // Button was already released (quick tap) - schedule as simple press
                // with delay to allow chord cancellation
                let workItem = DispatchWorkItem { [weak self] in
                    Task { @MainActor in
                        self?.pendingReleaseActions.removeValue(forKey: button)
                        if let keyCode = mapping.keyCode {
                            self?.inputSimulator.pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
                            self?.inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)
                        }
                    }
                }
                pendingReleaseActions[button] = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
            }
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

        // Start repeat timer if configured
        if let repeatConfig = mapping.repeatMapping, repeatConfig.enabled {
            startRepeatTimer(for: button, mapping: mapping, interval: repeatConfig.interval)
        }
    }

    private func startRepeatTimer(for button: ControllerButton, mapping: KeyMapping, interval: TimeInterval) {
        // Stop any existing repeat timer for this button
        stopRepeatTimer(for: button)

        // Execute action immediately on first press
        inputSimulator.executeMapping(mapping)
        inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)

        // Create a repeating timer
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Check if button is still pressed
            guard self.controllerService.activeButtons.contains(button) else {
                self.stopRepeatTimer(for: button)
                return
            }
            self.inputSimulator.executeMapping(mapping)
        }
        timer.resume()
        repeatTimers[button] = timer

        #if DEBUG
        print("↻ Started repeat timer for \(button.displayName) at \(1.0/interval)/s")
        #endif
    }

    private func stopRepeatTimer(for button: ControllerButton) {
        if let timer = repeatTimers[button] {
            timer.cancel()
            repeatTimers.removeValue(forKey: button)
            #if DEBUG
            print("↻ Stopped repeat timer for \(button.displayName)")
            #endif
        }
    }
    
    private func handleLongHoldTriggered(_ button: ControllerButton, mapping: LongHoldMapping) {
        longHoldTriggered.insert(button)
        executeLongHoldMapping(mapping)
        inputLogService?.log(buttons: [button], type: .longPress, action: mapping.displayString)
        
        #if DEBUG
        print("⏱️ Long hold triggered for \(button.displayName)")
        #endif
    }

    private func handleButtonReleased(_ button: ControllerButton, holdDuration: TimeInterval) {
        #if DEBUG
        print("🔘 handleButtonReleased: \(button.displayName) duration=\(holdDuration)")
        #endif

        // Stop repeat timer if active
        stopRepeatTimer(for: button)

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

        // Skip if repeat was enabled (action already executed on press)
        if let repeatConfig = mapping.repeatMapping, repeatConfig.enabled {
            #if DEBUG
            print("   ⏭️ Repeat was active, skipping release action")
            #endif
            return
        }

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
                inputLogService?.log(buttons: [button], type: .doubleTap, action: doubleTapMapping.displayString)
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
                    self?.inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)
                }
            }
            pendingSingleTap[button] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapMapping.threshold, execute: workItem)
        } else {
            // No double-tap mapping - execute after a short delay to allow for chord cancellation
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.pendingReleaseActions.removeValue(forKey: button)
                    self?.inputSimulator.executeMapping(mapping)
                    self?.inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)
                }
            }
            pendingReleaseActions[button] = workItem
            // Use chord window + a small margin (aligned with 150ms window)
            let delay = 0.18
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
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

        // Cancel any pending individual release actions for these buttons
        for button in buttons {
            if let pending = pendingReleaseActions[button] {
                pending.cancel()
                pendingReleaseActions.removeValue(forKey: button)
                #if DEBUG
                print("   🚫 Cancelled pending individual action for \(button.displayName)")
                #endif
            }
            
            // Also cancel pending single-taps (for buttons with double-tap mappings)
            if let pendingTap = pendingSingleTap[button] {
                pendingTap.cancel()
                pendingSingleTap.removeValue(forKey: button)
                lastTapTime.removeValue(forKey: button)
                #if DEBUG
                print("   🚫 Cancelled pending single-tap for \(button.displayName)")
                #endif
            }
        }

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

        inputLogService?.log(buttons: Array(buttons), type: .chord, action: chord.actionDisplayString)

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

        let timer = DispatchSource.makeTimerSource(queue: pollingQueue)
        timer.schedule(deadline: .now(), repeating: joystickPollInterval, leeway: .microseconds(100))
        timer.setEventHandler { [weak self] in
            self?.processJoysticks()
        }
        timer.resume()
        joystickTimer = timer
    }

    private func stopJoystickPolling() {
        joystickTimer?.cancel()
        joystickTimer = nil
        
        loopState.lock.lock()
        loopState.reset()
        loopState.lock.unlock()
    }

    nonisolated private func processJoysticks() {
        loopState.lock.lock()
        defer { loopState.lock.unlock() }
        
        guard loopState.isEnabled else { return }
        guard let settings = loopState.settings else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let dt = loopState.lastJoystickSampleTime > 0 ? now - loopState.lastJoystickSampleTime : joystickPollInterval
        loopState.lastJoystickSampleTime = now

        // Process left joystick (mouse)
        // Access thread-safe properties from ControllerService
        let leftStick = controllerService.threadSafeLeftStick
        let leftMagnitudeSquared = leftStick.x * leftStick.x + leftStick.y * leftStick.y
        let leftDeadzoneSquared = settings.mouseDeadzone * settings.mouseDeadzone
        
        if leftMagnitudeSquared <= leftDeadzoneSquared {
            loopState.smoothedLeftStick = .zero
        } else {
            loopState.smoothedLeftStick = smoothStick(leftStick, previous: loopState.smoothedLeftStick, dt: dt)
        }
        processMouseMovement(loopState.smoothedLeftStick, settings: settings)

        // Process right joystick (scroll)
        let rightStick = controllerService.threadSafeRightStick
        updateScrollDoubleTapState(rawStick: rightStick, settings: settings, now: now)
        let rightMagnitudeSquared = rightStick.x * rightStick.x + rightStick.y * rightStick.y
        let rightDeadzoneSquared = settings.scrollDeadzone * settings.scrollDeadzone
        
        if rightMagnitudeSquared <= rightDeadzoneSquared {
            loopState.smoothedRightStick = .zero
        } else {
            loopState.smoothedRightStick = smoothStick(rightStick, previous: loopState.smoothedRightStick, dt: dt)
        }
        processScrolling(loopState.smoothedRightStick, rawStick: rightStick, settings: settings, now: now)
    }

    nonisolated private func smoothStick(_ raw: CGPoint, previous: CGPoint, dt: TimeInterval) -> CGPoint {
        let magnitude = sqrt(Double(raw.x * raw.x + raw.y * raw.y))
        let t = min(1.0, magnitude * 1.2)
        // We need access to constants. They are private let in MappingEngine.
        // Accessing self.minJoystickCutoffHz should be fine as they are let and Sendable (Double).
        let cutoff = self.minJoystickCutoffHz + (self.maxJoystickCutoffHz - self.minJoystickCutoffHz) * t
        let alpha = 1.0 - exp(-2.0 * Double.pi * cutoff * max(0.0, dt))
        let newX = Double(previous.x) + alpha * (Double(raw.x) - Double(previous.x))
        let newY = Double(previous.y) + alpha * (Double(raw.y) - Double(previous.y))
        return CGPoint(x: newX, y: newY)
    }

    nonisolated private func updateScrollDoubleTapState(rawStick: CGPoint, settings: JoystickSettings, now: TimeInterval) {
        let deadzone = settings.scrollDeadzone
        let magnitudeSquared = rawStick.x * rawStick.x + rawStick.y * rawStick.y
        let deadzoneSquared = deadzone * deadzone
        let isOutside = magnitudeSquared > deadzoneSquared

        if loopState.scrollBoostDirection != 0, isOutside {
            let currentDirection = rawStick.y >= 0 ? 1 : -1
            if abs(rawStick.y) >= abs(rawStick.x) * self.scrollTapDirectionRatio,
               currentDirection != loopState.scrollBoostDirection {
                loopState.scrollBoostDirection = 0
            }
        }

        if isOutside {
            loopState.rightStickWasOutsideDeadzone = true
            loopState.rightStickPeakYAbs = max(loopState.rightStickPeakYAbs, abs(Double(rawStick.y)))
            if abs(rawStick.y) >= abs(rawStick.x) * self.scrollTapDirectionRatio {
                loopState.rightStickLastDirection = rawStick.y >= 0 ? 1 : -1
            }
            return
        }

        guard loopState.rightStickWasOutsideDeadzone else { return }
        loopState.rightStickWasOutsideDeadzone = false

        if loopState.rightStickPeakYAbs >= self.scrollTapThreshold, loopState.rightStickLastDirection != 0 {
            if now - loopState.lastRightStickTapTime <= self.scrollDoubleTapWindow,
               loopState.rightStickLastDirection == loopState.lastRightStickTapDirection {
                loopState.scrollBoostDirection = loopState.rightStickLastDirection
            }
            loopState.lastRightStickTapTime = now
            loopState.lastRightStickTapDirection = loopState.rightStickLastDirection
        }

        loopState.rightStickPeakYAbs = 0
        loopState.rightStickLastDirection = 0
    }

    nonisolated private func processMouseMovement(_ stick: CGPoint, settings: JoystickSettings) {
        // Fast path: skip if clearly in deadzone (avoid sqrt for common case)
        let deadzone = settings.mouseDeadzone
        let magnitudeSquared = stick.x * stick.x + stick.y * stick.y
        let deadzoneSquared = deadzone * deadzone
        guard magnitudeSquared > deadzoneSquared else { return }

        // Only compute sqrt when we know we're outside deadzone
        let magnitude = sqrt(magnitudeSquared)

        // Normalize and apply deadzone
        let normalizedMagnitude = (magnitude - deadzone) / (1.0 - deadzone)

        // Apply acceleration curve using the 0-1 acceleration setting
        let acceleratedMagnitude = pow(normalizedMagnitude, settings.mouseAccelerationExponent)

        // Calculate direction using the converted multiplier
        let scale = acceleratedMagnitude * settings.mouseMultiplier / magnitude
        let dx = stick.x * scale
        var dy = stick.y * scale

        // Invert Y if needed (joystick Y is inverted compared to screen coordinates)
        dy = settings.invertMouseY ? dy : -dy

        inputSimulator.moveMouse(dx: dx, dy: dy)
    }

    nonisolated private func processScrolling(_ stick: CGPoint, rawStick: CGPoint, settings: JoystickSettings, now: TimeInterval) {
        // Fast path: skip if clearly in deadzone (avoid sqrt for common case)
        let deadzone = settings.scrollDeadzone
        let magnitudeSquared = stick.x * stick.x + stick.y * stick.y
        let deadzoneSquared = deadzone * deadzone
        guard magnitudeSquared > deadzoneSquared else { return }

        // Only compute sqrt when we know we're outside deadzone
        let magnitude = sqrt(magnitudeSquared)

        // Normalize and apply deadzone
        let normalizedMagnitude = (magnitude - deadzone) / (1.0 - deadzone)

        // Apply acceleration curve using the 0-1 acceleration setting
        let acceleratedMagnitude = pow(normalizedMagnitude, settings.scrollAccelerationExponent)

        // Calculate direction using the converted multiplier
        let scale = acceleratedMagnitude * settings.scrollMultiplier / magnitude
        let dx = stick.x * scale
        var dy = stick.y * scale

        // Invert Y if needed
        dy = settings.invertScrollY ? -dy : dy

        if loopState.scrollBoostDirection != 0,
           (rawStick.y >= 0 ? 1 : -1) == loopState.scrollBoostDirection {
            dy *= settings.scrollBoostMultiplier
        }

        inputSimulator.scroll(dx: dx, dy: dy)
    }

    // MARK: - Control

    func enable() {
        isEnabled = true
        loopState.lock.lock()
        loopState.isEnabled = true
        loopState.lock.unlock()
    }

    func disable() {
        isEnabled = false
        
        loopState.lock.lock()
        loopState.isEnabled = false
        loopState.lock.unlock()
        
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

        // Cancel repeat timers
        for (_, timer) in repeatTimers {
            timer.cancel()
        }
        repeatTimers.removeAll()

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
