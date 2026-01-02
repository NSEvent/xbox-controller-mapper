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

    // MARK: - Thread-Safe State
    
    private let inputQueue = DispatchQueue(label: "com.xboxmapper.input", qos: .userInteractive)
    private let pollingQueue = DispatchQueue(label: "com.xboxmapper.polling", qos: .userInteractive)
    
    private final class EngineState: @unchecked Sendable {
        let lock = NSLock()
        var isEnabled = true
        
        // Mirrors of MainActor data
        var activeProfile: Profile?
        var frontmostBundleId: String?
        var joystickSettings: JoystickSettings?

        // Button State
        var heldButtons: [ControllerButton: KeyMapping] = [:]
        var activeChordButtons: Set<ControllerButton> = []
        var lastTapTime: [ControllerButton: Date] = [:]
        var pendingSingleTap: [ControllerButton: DispatchWorkItem] = [:]
        var pendingReleaseActions: [ControllerButton: DispatchWorkItem] = [:]
        var longHoldTimers: [ControllerButton: DispatchWorkItem] = [:]
        var longHoldTriggered: Set<ControllerButton> = []
        var repeatTimers: [ControllerButton: DispatchSourceTimer] = [:]

        // Joystick State
        var smoothedLeftStick: CGPoint = .zero
        var smoothedRightStick: CGPoint = .zero
        var lastJoystickSampleTime: TimeInterval = 0
        
        var rightStickWasOutsideDeadzone = false
        var rightStickPeakYAbs: Double = 0
        var rightStickLastDirection: Int = 0
        var lastRightStickTapTime: TimeInterval = 0
        var lastRightStickTapDirection: Int = 0
        var scrollBoostDirection: Int = 0

        // Focus mode state tracking for haptic feedback
        var wasFocusActive = false

        // Smooth multiplier transition to prevent mouse jump when exiting focus mode
        var currentMultiplier: Double = 0

        // Brief pause after exiting focus mode to let user adjust joystick
        var focusExitTime: TimeInterval = 0
        
        func reset() {
            heldButtons.removeAll()
            activeChordButtons.removeAll()
            lastTapTime.removeAll()
            
            pendingSingleTap.values.forEach { $0.cancel() }
            pendingSingleTap.removeAll()
            
            pendingReleaseActions.values.forEach { $0.cancel() }
            pendingReleaseActions.removeAll()
            
            longHoldTimers.values.forEach { $0.cancel() }
            longHoldTimers.removeAll()
            longHoldTriggered.removeAll()
            
            repeatTimers.values.forEach { $0.cancel() }
            repeatTimers.removeAll()
            
            smoothedLeftStick = .zero
            smoothedRightStick = .zero
            lastJoystickSampleTime = 0
            rightStickWasOutsideDeadzone = false
            rightStickPeakYAbs = 0
            rightStickLastDirection = 0
            lastRightStickTapTime = 0
            lastRightStickTapDirection = 0
            scrollBoostDirection = 0
            wasFocusActive = false
            currentMultiplier = 0
            focusExitTime = 0
        }
    }
    
    private let state = EngineState()
    
    // Joystick polling
    private var joystickTimer: DispatchSourceTimer?
    private let joystickPollInterval: TimeInterval = 1.0 / 120.0

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
        
        // Initial state sync
        self.state.activeProfile = profileManager.activeProfile
        self.state.joystickSettings = profileManager.activeProfile?.joystickSettings
        self.state.frontmostBundleId = appMonitor.frontmostBundleId
    }
    
    private func setupBindings() {
        // Sync Profile
        profileManager.$activeProfile
            .sink { [weak self] profile in
                guard let self = self else { return }
                self.state.lock.lock()
                self.state.activeProfile = profile
                self.state.joystickSettings = profile?.joystickSettings
                self.state.lock.unlock()
            }
            .store(in: &cancellables)
            
        // Sync App Bundle ID
        appMonitor.$frontmostBundleId
            .sink { [weak self] bundleId in
                guard let self = self else { return }
                self.state.lock.lock()
                self.state.frontmostBundleId = bundleId
                self.state.lock.unlock()
            }
            .store(in: &cancellables)

        // Button press handler (Off-Main Thread)
        controllerService.onButtonPressed = { [weak self] button in
            guard let self = self else { return }
            self.inputQueue.async {
                self.handleButtonPressed(button)
            }
        }

        // Button release handler (Off-Main Thread)
        controllerService.onButtonReleased = { [weak self] button, duration in
            guard let self = self else { return }
            self.inputQueue.async {
                self.handleButtonReleased(button, holdDuration: duration)
            }
        }

        // Chord handler (Off-Main Thread)
        controllerService.onChordDetected = { [weak self] buttons in
            guard let self = self else { return }
            self.inputQueue.async {
                self.handleChord(buttons)
            }
        }

        // Joystick polling
        controllerService.$isConnected
            .sink { [weak self] connected in
                if connected {
                    self?.startJoystickPolling()
                } else {
                    self?.stopJoystickPolling()
                }
            }
            .store(in: &cancellables)
            
        // Enable/Disable toggle sync
        $isEnabled
            .sink { [weak self] enabled in
                guard let self = self else { return }
                self.state.lock.lock()
                self.state.isEnabled = enabled
                if !enabled {
                    // Cleanup if disabled
                    self.state.reset()
                    self.inputSimulator.releaseAllModifiers()
                }
                self.state.lock.unlock()
            }
            .store(in: &cancellables)
    }

    // MARK: - Button Handling (Background Queue)

    nonisolated private func isButtonUsedInChords(_ button: ControllerButton, profile: Profile) -> Bool {
        return profile.chordMappings.contains { chord in
            chord.buttons.contains(button)
        }
    }

    nonisolated private func handleButtonPressed(_ button: ControllerButton) {
        state.lock.lock()
        guard state.isEnabled, let profile = state.activeProfile else {
            state.lock.unlock()
            return
        }
        let bundleId = state.frontmostBundleId
        // Copy state needed for logic
        let lastTap = state.lastTapTime[button]
        state.lock.unlock()

        // Get the effective mapping
        guard let mapping = profile.effectiveMapping(for: button, appBundleId: bundleId) else {
            return
        }

        #if DEBUG
        print("🔵 handleButtonPressed: \(button.displayName)")
        #endif

        // Auto-optimize Mouse Clicks: Treat as hold modifier (Down on Press, Up on Release)
        let isMouseClick = mapping.keyCode.map { KeyCodeMapping.isMouseButton($0) } ?? false
        let isChordPart = isButtonUsedInChords(button, profile: profile)
        let hasDoubleTap = mapping.doubleTapMapping != nil && !mapping.doubleTapMapping!.isEmpty
        
        let shouldTreatAsHold = mapping.isHoldModifier || (isMouseClick && !isChordPart && !hasDoubleTap)

        if shouldTreatAsHold {
            // Check for double-tap
            if let doubleTapMapping = mapping.doubleTapMapping, !doubleTapMapping.isEmpty {
                let now = Date()
                if let lastTap = lastTap, now.timeIntervalSince(lastTap) <= doubleTapMapping.threshold {
                    // Double-tap executed
                    state.lock.lock()
                    state.lastTapTime.removeValue(forKey: button)
                    state.lock.unlock()
                    
                    executeDoubleTapMapping(doubleTapMapping)
                    inputLogService?.log(buttons: [button], type: .doubleTap, action: doubleTapMapping.displayString)
                    return
                }
                state.lock.lock()
                state.lastTapTime[button] = now
                state.lock.unlock()
            }

            // Start holding
            state.lock.lock()
            state.heldButtons[button] = mapping
            state.lock.unlock()
            
            inputSimulator.startHoldMapping(mapping)
            inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)
            return
        }
        
        // Long Hold
        if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
            let workItem = DispatchWorkItem { [weak self] in
                self?.handleLongHoldTriggered(button, mapping: longHold)
            }
            state.lock.lock()
            state.longHoldTimers[button] = workItem
            state.lock.unlock()
            inputQueue.asyncAfter(deadline: .now() + longHold.threshold, execute: workItem)
        }

        // Repeat
        if let repeatConfig = mapping.repeatMapping, repeatConfig.enabled {
            startRepeatTimer(for: button, mapping: mapping, interval: repeatConfig.interval)
        }
    }

    nonisolated private func startRepeatTimer(for button: ControllerButton, mapping: KeyMapping, interval: TimeInterval) {
        stopRepeatTimer(for: button)

        inputSimulator.executeMapping(mapping)
        inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)

        let timer = DispatchSource.makeTimerSource(queue: inputQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Check if button is still held (by checking active buttons from controller service? 
            // ControllerService is MainActor. Accessing activeButtons is tricky.
            // Better to rely on state.heldButtons or just stop timer on release.)
            self.inputSimulator.executeMapping(mapping)
        }
        timer.resume()
        
        state.lock.lock()
        state.repeatTimers[button] = timer
        state.lock.unlock()
    }

    nonisolated private func stopRepeatTimer(for button: ControllerButton) {
        state.lock.lock()
        defer { state.lock.unlock() }
        if let timer = state.repeatTimers[button] {
            timer.cancel()
            state.repeatTimers.removeValue(forKey: button)
        }
    }
    
    nonisolated private func handleLongHoldTriggered(_ button: ControllerButton, mapping: LongHoldMapping) {
        state.lock.lock()
        state.longHoldTriggered.insert(button)
        state.lock.unlock()
        
        executeLongHoldMapping(mapping)
        inputLogService?.log(buttons: [button], type: .longPress, action: mapping.displayString)
    }

    nonisolated private func handleButtonReleased(_ button: ControllerButton, holdDuration: TimeInterval) {
        stopRepeatTimer(for: button)

        state.lock.lock()
        // Cancel long hold timer
        if let timer = state.longHoldTimers[button] {
            timer.cancel()
            state.longHoldTimers.removeValue(forKey: button)
        }
        
        guard state.isEnabled, let profile = state.activeProfile else {
            state.lock.unlock()
            return
        }
        
        // Check for held mapping - must release even for chord buttons
        // (chord fallback may have started a hold mapping that needs cleanup)
        if let heldMapping = state.heldButtons[button] {
            state.heldButtons.removeValue(forKey: button)
            state.activeChordButtons.remove(button)  // Also clear chord state if present
            state.lock.unlock()
            inputSimulator.stopHoldMapping(heldMapping)
            return
        }

        if state.activeChordButtons.contains(button) {
            state.activeChordButtons.remove(button)
            state.lock.unlock()
            return
        }
        
        let bundleId = state.frontmostBundleId
        let isLongHoldTriggered = state.longHoldTriggered.contains(button)
        if isLongHoldTriggered {
            state.longHoldTriggered.remove(button)
        }
        
        // Copy other needed state
        let pendingSingle = state.pendingSingleTap[button]
        let lastTap = state.lastTapTime[button]
        state.lock.unlock()

        guard let mapping = profile.effectiveMapping(for: button, appBundleId: bundleId) else { return }
        
        // Skip if held or repeat (handled above/already)
        if mapping.isHoldModifier || (mapping.repeatMapping?.enabled ?? false) { return }
        if isLongHoldTriggered { return }

        // Long Hold Fallback
        if let longHoldMapping = mapping.longHoldMapping,
           holdDuration >= longHoldMapping.threshold,
           !longHoldMapping.isEmpty {
            
            state.lock.lock()
            state.pendingSingleTap[button]?.cancel()
            state.pendingSingleTap.removeValue(forKey: button)
            state.lastTapTime.removeValue(forKey: button)
            state.lock.unlock()
            
            executeLongHoldMapping(longHoldMapping)
            return
        }

        // Double Tap
        if let doubleTapMapping = mapping.doubleTapMapping, !doubleTapMapping.isEmpty {
            let now = Date()
            
            if let pending = pendingSingle,
               let lastTap = lastTap,
               now.timeIntervalSince(lastTap) <= doubleTapMapping.threshold {
                
                pending.cancel()
                state.lock.lock()
                state.pendingSingleTap.removeValue(forKey: button)
                state.lastTapTime.removeValue(forKey: button)
                state.lock.unlock()
                
                executeDoubleTapMapping(doubleTapMapping)
                inputLogService?.log(buttons: [button], type: .doubleTap, action: doubleTapMapping.displayString)
                return
            }
            
            // First tap
            state.lock.lock()
            state.lastTapTime[button] = now
            
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.state.lock.lock()
                self.state.pendingSingleTap.removeValue(forKey: button)
                self.state.lastTapTime.removeValue(forKey: button)
                self.state.lock.unlock()
                
                self.inputSimulator.executeMapping(mapping)
                self.inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)
            }
            state.pendingSingleTap[button] = workItem
            state.lock.unlock()
            
            inputQueue.asyncAfter(deadline: .now() + doubleTapMapping.threshold, execute: workItem)
        } else {
            // Single Tap
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.state.lock.lock()
                self.state.pendingReleaseActions.removeValue(forKey: button)
                self.state.lock.unlock()
                
                self.inputSimulator.executeMapping(mapping)
                self.inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)
            }
            
            state.lock.lock()
            state.pendingReleaseActions[button] = workItem
            state.lock.unlock()
            
            let isChordPart = isButtonUsedInChords(button, profile: profile)
            let delay = isChordPart ? 0.18 : 0.0
            
            if delay > 0 {
                inputQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
            } else {
                inputQueue.async(execute: workItem)
            }
        }
    }

    nonisolated private func executeLongHoldMapping(_ mapping: LongHoldMapping) {
        if let keyCode = mapping.keyCode {
            inputSimulator.pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        } else if mapping.modifiers.hasAny {
            let flags = mapping.modifiers.cgEventFlags
            inputSimulator.holdModifier(flags)
            inputQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.inputSimulator.releaseModifier(flags)
            }
        }
    }

    nonisolated private func executeDoubleTapMapping(_ mapping: DoubleTapMapping) {
        if let keyCode = mapping.keyCode {
            inputSimulator.pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        } else if mapping.modifiers.hasAny {
            let flags = mapping.modifiers.cgEventFlags
            inputSimulator.holdModifier(flags)
            inputQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.inputSimulator.releaseModifier(flags)
            }
        }
    }

    nonisolated private func handleChord(_ buttons: Set<ControllerButton>) {
        state.lock.lock()
        guard state.isEnabled, let profile = state.activeProfile else {
            state.lock.unlock()
            return
        }
        
        // Cancel pending actions
        for button in buttons {
            state.pendingReleaseActions[button]?.cancel()
            state.pendingReleaseActions.removeValue(forKey: button)
            
            state.pendingSingleTap[button]?.cancel()
            state.pendingSingleTap.removeValue(forKey: button)
            state.lastTapTime.removeValue(forKey: button)
        }
        
        // Register active chord
        state.activeChordButtons = buttons
        state.lock.unlock()

        let matchingChord = profile.chordMappings.first { chord in
            chord.buttons == buttons
        }

        if let chord = matchingChord {
            inputLogService?.log(buttons: Array(buttons), type: .chord, action: chord.actionDisplayString)
            if let keyCode = chord.keyCode {
                inputSimulator.pressKey(keyCode, modifiers: chord.modifiers.cgEventFlags)
            } else if chord.modifiers.hasAny {
                let flags = chord.modifiers.cgEventFlags
                inputSimulator.holdModifier(flags)
                inputQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.inputSimulator.releaseModifier(flags)
                }
            }
        } else {
            // Fallback: Individual handling
            // Note: This fallback is tricky because we're inside the chord handler.
            // But usually ControllerService only sends chord *or* individual presses.
            // If it sends chord, it means buttons were pressed roughly together.
            // If no chord mapping exists, we should probably just treat them as individual presses.
            // But we might have missed the "press" event if it was swallowed?
            // ControllerService logic usually sends individual press if chord not detected.
            // If chord IS detected by Service but no mapping exists, we should invoke handleButtonPressed for each?
            // But handleButtonPressed might have been called already?
            // Let's assume ControllerService suppresses individual presses until chord timeout.
            // So we need to trigger them now.
            
            let sortedButtons = buttons.sorted { $0.rawValue < $1.rawValue }
            for button in sortedButtons {
                handleButtonPressed(button)
            }
        }
    }

    // MARK: - Joystick Handling (Background Queue)

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
        
        state.lock.lock()
        state.reset()
        state.lock.unlock()
    }

    nonisolated private func processJoysticks() {
        state.lock.lock()
        defer { state.lock.unlock() }
        
        guard state.isEnabled, let settings = state.joystickSettings else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let dt = state.lastJoystickSampleTime > 0 ? now - state.lastJoystickSampleTime : joystickPollInterval
        state.lastJoystickSampleTime = now

        // Process left joystick (mouse)
        // Note: accessing controllerService.threadSafeLeftStick is safe (atomic/lock-free usually)
        let leftStick = controllerService.threadSafeLeftStick
        
        // Remove smoothing - pass raw value
        processMouseMovement(leftStick, settings: settings)

        // Process right joystick (scroll)
        let rightStick = controllerService.threadSafeRightStick
        updateScrollDoubleTapState(rawStick: rightStick, settings: settings, now: now)
        let rightMagnitudeSquared = rightStick.x * rightStick.x + rightStick.y * rightStick.y
        let rightDeadzoneSquared = settings.scrollDeadzone * settings.scrollDeadzone
        
        if rightMagnitudeSquared <= rightDeadzoneSquared {
            state.smoothedRightStick = .zero
        } else {
            state.smoothedRightStick = smoothStick(rightStick, previous: state.smoothedRightStick, dt: dt)
        }
        processScrolling(state.smoothedRightStick, rawStick: rightStick, settings: settings, now: now)
    }

    nonisolated private func smoothStick(_ raw: CGPoint, previous: CGPoint, dt: TimeInterval) -> CGPoint {
        let magnitude = sqrt(Double(raw.x * raw.x + raw.y * raw.y))
        let t = min(1.0, magnitude * 1.2)
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

        if state.scrollBoostDirection != 0, isOutside {
            let currentDirection = rawStick.y >= 0 ? 1 : -1
            if abs(rawStick.y) >= abs(rawStick.x) * self.scrollTapDirectionRatio,
               currentDirection != state.scrollBoostDirection {
                state.scrollBoostDirection = 0
            }
        }

        if isOutside {
            state.rightStickWasOutsideDeadzone = true
            state.rightStickPeakYAbs = max(state.rightStickPeakYAbs, abs(Double(rawStick.y)))
            if abs(rawStick.y) >= abs(rawStick.x) * self.scrollTapDirectionRatio {
                state.rightStickLastDirection = rawStick.y >= 0 ? 1 : -1
            }
            return
        }

        guard state.rightStickWasOutsideDeadzone else { return }
        state.rightStickWasOutsideDeadzone = false

        if state.rightStickPeakYAbs >= self.scrollTapThreshold, state.rightStickLastDirection != 0 {
            if now - state.lastRightStickTapTime <= self.scrollDoubleTapWindow,
               state.rightStickLastDirection == state.lastRightStickTapDirection {
                state.scrollBoostDirection = state.rightStickLastDirection
            }
            state.lastRightStickTapTime = now
            state.lastRightStickTapDirection = state.rightStickLastDirection
        }

        state.rightStickPeakYAbs = 0
        state.rightStickLastDirection = 0
    }

    nonisolated private func processMouseMovement(_ stick: CGPoint, settings: JoystickSettings) {
        // Focus Mode Logic - check BEFORE deadzone to detect transitions even when stick is idle
        let focusFlags = settings.focusModeModifier.cgEventFlags

        // Determine if focus mode is active
        // Only use our internal controller state - this prevents false triggers from
        // shortcuts that briefly hold the same modifier (e.g., Command+C triggering
        // focus mode haptics when focus mode uses Command)
        let isFocusActive = focusFlags.rawValue != 0 && inputSimulator.isHoldingModifiers(focusFlags)

        // Detect focus mode transitions and trigger haptic feedback
        // Note: state.lock is already held by caller (processJoysticks)
        let wasFocusActive = state.wasFocusActive
        let now = CFAbsoluteTimeGetCurrent()

        if isFocusActive != wasFocusActive {
            state.wasFocusActive = isFocusActive
            // Haptic feedback runs async internally, won't block input
            performFocusModeHaptic(entering: isFocusActive)

            // When exiting focus mode, record the time so we can pause movement briefly
            if !isFocusActive {
                state.focusExitTime = now
                // Reset multiplier to focus level so it ramps up from there
                state.currentMultiplier = settings.focusMultiplier
            }
        }

        // Brief pause after exiting focus mode (100ms) to let user adjust joystick
        let focusExitPauseDuration: TimeInterval = 0.1
        if state.focusExitTime > 0 && (now - state.focusExitTime) < focusExitPauseDuration {
            return  // Skip mouse movement during pause
        }

        // Early exit if stick is within deadzone
        let deadzone = settings.mouseDeadzone
        let magnitudeSquared = stick.x * stick.x + stick.y * stick.y
        let deadzoneSquared = deadzone * deadzone
        guard magnitudeSquared > deadzoneSquared else { return }

        let magnitude = sqrt(magnitudeSquared)
        let normalizedMagnitude = (magnitude - deadzone) / (1.0 - deadzone)
        let acceleratedMagnitude = pow(normalizedMagnitude, settings.mouseAccelerationExponent)

        // Smooth multiplier transition to prevent mouse jump when exiting focus mode
        let targetMultiplier = isFocusActive ? settings.focusMultiplier : settings.mouseMultiplier

        // Initialize currentMultiplier if zero (first run)
        if state.currentMultiplier == 0 {
            state.currentMultiplier = targetMultiplier
        }

        // Exponential smoothing: ~100ms transition time at 120Hz polling
        // alpha = 1 - e^(-dt/tau), where tau is time constant
        // For 120Hz and ~100ms transition: alpha ≈ 0.08
        let smoothingAlpha = 0.08
        state.currentMultiplier += smoothingAlpha * (targetMultiplier - state.currentMultiplier)

        let scale = acceleratedMagnitude * state.currentMultiplier / magnitude
        let dx = stick.x * scale
        var dy = stick.y * scale

        dy = settings.invertMouseY ? dy : -dy

        inputSimulator.moveMouse(dx: dx, dy: dy)
    }

    /// Performs haptic feedback for focus mode transitions on the controller
    nonisolated private func performFocusModeHaptic(entering: Bool) {
        // Both enter and exit get strong haptics, but with different feel
        // Enter: sharp click, Exit: softer thud
        let intensity: Float = 0.5
        let sharpness: Float = entering ? 1.0 : 0.3
        let duration: TimeInterval = entering ? 0.12 : 0.15
        controllerService.playHaptic(intensity: intensity, sharpness: sharpness, duration: duration)
    }

    nonisolated private func processScrolling(_ stick: CGPoint, rawStick: CGPoint, settings: JoystickSettings, now: TimeInterval) {
        let deadzone = settings.scrollDeadzone
        let magnitudeSquared = stick.x * stick.x + stick.y * stick.y
        let deadzoneSquared = deadzone * deadzone
        guard magnitudeSquared > deadzoneSquared else { return }

        let magnitude = sqrt(magnitudeSquared)
        let normalizedMagnitude = (magnitude - deadzone) / (1.0 - deadzone)
        let acceleratedMagnitude = pow(normalizedMagnitude, settings.scrollAccelerationExponent)
        let scale = acceleratedMagnitude * settings.scrollMultiplier / magnitude
        let dx = stick.x * scale
        var dy = stick.y * scale

        dy = settings.invertScrollY ? -dy : dy

        if state.scrollBoostDirection != 0,
           (rawStick.y >= 0 ? 1 : -1) == state.scrollBoostDirection {
            dy *= settings.scrollBoostMultiplier
        }

        inputSimulator.scroll(dx: dx, dy: dy)
    }

    // MARK: - Control

    func enable() {
        isEnabled = true
    }

    func disable() {
        isEnabled = false
    }

    func toggle() {
        isEnabled.toggle()
    }
}
