import Foundation
import Combine
import CoreGraphics

// MARK: - Mapping Execution Helper

/// Handles execution of different mapping types (simple, hold, long-hold, double-tap)
private struct MappingExecutor {
    private let inputSimulator: InputSimulatorProtocol
    private let inputQueue: DispatchQueue
    private let inputLogService: InputLogService?

    init(inputSimulator: InputSimulatorProtocol, inputQueue: DispatchQueue, inputLogService: InputLogService?) {
        self.inputSimulator = inputSimulator
        self.inputQueue = inputQueue
        self.inputLogService = inputLogService
    }

    /// Executes a simple key mapping
    func executeMapping(_ mapping: KeyMapping, for button: ControllerButton, logType: InputEventType = .singlePress) {
        if let keyCode = mapping.keyCode {
            inputSimulator.pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        } else if mapping.modifiers.hasAny {
            executeTapModifier(mapping.modifiers.cgEventFlags)
        }
        inputLogService?.log(buttons: [button], type: logType, action: mapping.displayString)
    }

    /// Executes a long-hold mapping
    func executeLongHold(_ mapping: LongHoldMapping, for button: ControllerButton) {
        if let keyCode = mapping.keyCode {
            inputSimulator.pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        } else if mapping.modifiers.hasAny {
            executeTapModifier(mapping.modifiers.cgEventFlags)
        }
        inputLogService?.log(buttons: [button], type: .longPress, action: mapping.displayString)
    }

    /// Executes a double-tap mapping
    func executeDoubleTap(_ mapping: DoubleTapMapping, for button: ControllerButton) {
        if let keyCode = mapping.keyCode {
            inputSimulator.pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        } else if mapping.modifiers.hasAny {
            executeTapModifier(mapping.modifiers.cgEventFlags)
        }
        inputLogService?.log(buttons: [button], type: .doubleTap, action: mapping.displayString)
    }

    /// Helper: Execute a modifier-only mapping (tap modifiers briefly)
    private func executeTapModifier(_ flags: CGEventFlags) {
        inputSimulator.holdModifier(flags)
        inputQueue.asyncAfter(deadline: .now() + Config.modifierReleaseCheckDelay) { [inputSimulator] in
            inputSimulator.releaseModifier(flags)
        }
    }
}

/// Orchestrates game controller input to keyboard/mouse output mapping
///
/// The MappingEngine is the central coordinator that:
/// 1. Listens to controller input events from ControllerService
/// 2. Looks up appropriate mappings from the active Profile
/// 3. Applies complex mapping logic (chords, long-holds, double-taps)
/// 4. Simulates keyboard/mouse output via InputSimulator
/// 5. Tracks joystick input and provides mouse movement
///
/// **Key Features:**
/// - **Chord Detection** - Multiple buttons pressed simultaneously trigger combined action
/// - **Long-Hold Detection** - Different action when button held >500ms threshold
/// - **Double-Tap Detection** - Different action on rapid double-press within time window
/// - **Repeat-While-Held** - Key repeats continuously while button is held
/// - **Hold Modifiers** - Button acts as modifier key (Cmd, Option, Shift, Control) while held
/// - **Joystick Mapping** - Left stick → mouse movement, Right stick → scroll wheel
/// - **Focus Mode** - Sensitivity boost when app window in focus
/// - **App-Specific Overrides** - Different mappings per application (bundle ID)
///
/// **Thread Safety:** @MainActor isolation with internal NSLock for nonisolated callbacks
///
/// **Performance:** Polling @ 120Hz with UI throttled to 15Hz refresh rate
///
/// **Configuration:** Tunable parameters in `Config.swift`
@MainActor
class MappingEngine: ObservableObject {
    @Published var isEnabled = true

    private let controllerService: ControllerService
    private let profileManager: ProfileManager
    private let appMonitor: AppMonitor
    nonisolated private let inputSimulator: InputSimulatorProtocol
    private let inputLogService: InputLogService?
    nonisolated private let mappingExecutor: MappingExecutor

    // MARK: - Thread-Safe State
    
    private let inputQueue = DispatchQueue(label: "com.xboxmapper.input", qos: .userInteractive)
    private let pollingQueue = DispatchQueue(label: "com.xboxmapper.polling", qos: .userInteractive)
    
    /// State container for all mapping engine operations
    ///
    /// Tracks button presses, timing state, and pending actions in a thread-safe manner.
    /// Accessed from nonisolated polling callbacks via lock-protected access.
    ///
    /// **Main State Categories:**
    /// 1. **Button Tracking** - Active buttons and chord detection
    ///    - heldButtons: Map of currently pressed buttons to their mappings
    ///    - activeChordButtons: Set of buttons involved in active chord sequence
    /// 2. **Timing & Detection** - Double-tap, long-hold, and repeat detection
    ///    - lastTapTime: Last press time per button (for double-tap detection)
    ///    - pendingSingleTap: Delayed execution of single-tap (waits for double-tap)
    ///    - longHoldTriggered: Tracks which buttons have triggered long-hold alternate
    /// 3. **Delayed Actions** - Actions queued for later execution
    ///    - pendingSingleTap: Single-tap confirmed after double-tap window closes
    ///    - pendingReleaseActions: Button releases queued during chord window
    ///    - longHoldTimers: Timers waiting to trigger long-hold alternate
    ///    - repeatTimers: Timers for repeat-while-held actions
    /// 4. **Joystick State** - Smoothed stick positions and special handling
    ///    - smoothedLeftStick/smoothedRightStick: Low-pass filtered analog values
    ///    - rightStickWasOutsideDeadzone: Tracks if stick moved far enough for scroll boost
    ///    - scrollBoostDirection: Active scroll boost direction (if in progress)
    /// 5. **Focus Mode** - Special sensitivity mode for focused input
    ///    - currentMultiplier: Joystick sensitivity multiplier (0.0-2.0)
    ///    - focusExitTime: Timestamp when focus mode was exited

    // MARK: - Touchpad Gesture State

    /// Groups all touchpad gesture-related state for better organization
    private struct TouchpadGestureState {
        // Single-finger movement smoothing
        var smoothedDelta: CGPoint = .zero
        var lastSampleTime: TimeInterval = 0

        // Two-finger gesture smoothing
        var smoothedCenterDelta: CGPoint = .zero
        var smoothedDistanceDelta: Double = 0
        var lastGestureSampleTime: TimeInterval = 0
        var isGestureActive = false

        // Scroll residuals for sub-pixel accumulation
        var scrollResidualX: Double = 0
        var scrollResidualY: Double = 0

        // Momentum physics state
        var momentumVelocity: CGPoint = .zero
        var momentumLastUpdate: TimeInterval = 0
        var momentumLastGestureTime: TimeInterval = 0
        var momentumWasActive = false
        var momentumCandidateVelocity: CGPoint = .zero
        var momentumCandidateTime: TimeInterval = 0
        var momentumHighVelocityStartTime: TimeInterval = 0
        var momentumHighVelocitySampleCount: Int = 0
        var momentumPeakVelocity: CGPoint = .zero
        var momentumPeakMagnitude: Double = 0
        var smoothedPanVelocity: CGPoint = .zero

        // Pinch/zoom state
        var pinchAccumulator: Double = 0
        var magnifyGestureActive: Bool = false

        mutating func reset() {
            smoothedDelta = .zero
            lastSampleTime = 0
            smoothedCenterDelta = .zero
            smoothedDistanceDelta = 0
            lastGestureSampleTime = 0
            isGestureActive = false
            scrollResidualX = 0
            scrollResidualY = 0
            momentumVelocity = .zero
            momentumLastUpdate = 0
            momentumLastGestureTime = 0
            momentumWasActive = false
            momentumCandidateVelocity = .zero
            momentumCandidateTime = 0
            momentumHighVelocityStartTime = 0
            momentumHighVelocitySampleCount = 0
            momentumPeakVelocity = .zero
            momentumPeakMagnitude = 0
            smoothedPanVelocity = .zero
            pinchAccumulator = 0
            magnifyGestureActive = false
        }
    }

    // MARK: - Engine State

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
        var onScreenKeyboardButton: ControllerButton? = nil  // Tracks which button is showing the on-screen keyboard
        var onScreenKeyboardHoldMode: Bool = false  // Whether keyboard should hide on button release

        // Joystick State
        var smoothedLeftStick: CGPoint = .zero
        var smoothedRightStick: CGPoint = .zero
        var lastJoystickSampleTime: TimeInterval = 0
        var smoothedTouchpadDelta: CGPoint = .zero
        var lastTouchpadSampleTime: TimeInterval = 0
        var smoothedTouchpadCenterDelta: CGPoint = .zero
        var smoothedTouchpadDistanceDelta: Double = 0
        var lastTouchpadGestureSampleTime: TimeInterval = 0
        var isTouchpadGestureActive = false
        var touchpadScrollResidualX: Double = 0
        var touchpadScrollResidualY: Double = 0
        var touchpadMomentumVelocity: CGPoint = .zero
        var touchpadMomentumLastUpdate: TimeInterval = 0
        var touchpadMomentumLastGestureTime: TimeInterval = 0
        var touchpadMomentumWasActive = false
        var touchpadMomentumCandidateVelocity: CGPoint = .zero
        var touchpadMomentumCandidateTime: TimeInterval = 0
        var touchpadMomentumHighVelocityStartTime: TimeInterval = 0
        var touchpadMomentumHighVelocitySampleCount: Int = 0
        var touchpadMomentumPeakVelocity: CGPoint = .zero
        var touchpadMomentumPeakMagnitude: Double = 0
        var smoothedTouchpadPanVelocity: CGPoint = .zero
        var touchpadPinchAccumulator: Double = 0
        var touchpadMagnifyGestureActive: Bool = false

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
            smoothedTouchpadDelta = .zero
            lastTouchpadSampleTime = 0
            smoothedTouchpadCenterDelta = .zero
            smoothedTouchpadDistanceDelta = 0
            lastTouchpadGestureSampleTime = 0
            isTouchpadGestureActive = false
            touchpadScrollResidualX = 0
            touchpadScrollResidualY = 0
            touchpadMomentumVelocity = .zero
            touchpadMomentumLastUpdate = 0
            touchpadMomentumLastGestureTime = 0
            touchpadMomentumWasActive = false
            touchpadMomentumCandidateVelocity = .zero
            touchpadMomentumCandidateTime = 0
            touchpadMomentumHighVelocityStartTime = 0
            touchpadMomentumHighVelocitySampleCount = 0
            touchpadMomentumPeakVelocity = .zero
            touchpadMomentumPeakMagnitude = 0
            smoothedTouchpadPanVelocity = .zero
            touchpadPinchAccumulator = 0
            touchpadMagnifyGestureActive = false
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
    private var touchpadMomentumTimer: DispatchSourceTimer?

    private var cancellables = Set<AnyCancellable>()

    init(controllerService: ControllerService, profileManager: ProfileManager, appMonitor: AppMonitor, inputSimulator: InputSimulatorProtocol = InputSimulator(), inputLogService: InputLogService? = nil) {
        self.controllerService = controllerService
        self.profileManager = profileManager
        self.appMonitor = appMonitor
        self.inputSimulator = inputSimulator
        self.inputLogService = inputLogService
        self.mappingExecutor = MappingExecutor(inputSimulator: inputSimulator, inputQueue: inputQueue, inputLogService: inputLogService)

        // Set up on-screen keyboard manager with our input simulator
        OnScreenKeyboardManager.shared.setInputSimulator(inputSimulator)

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
                    self?.startTouchpadMomentumTimer()
                } else {
                    self?.stopJoystickPolling()
                    self?.stopTouchpadMomentumTimer()
                }
            }
            .store(in: &cancellables)

        // Apply LED settings only when DualSense first connects (not on profile changes)
        controllerService.$isConnected
            .removeDuplicates()
            .filter { $0 == true }  // Only react to connection events
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.controllerService.threadSafeIsDualSense,
                   let ledSettings = self.profileManager.activeProfile?.dualSenseLEDSettings {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.controllerService.applyLEDSettings(ledSettings)
                    }
                }
            }
            .store(in: &cancellables)

        // Touchpad movement handler (DualSense only)
        controllerService.onTouchpadMoved = { [weak self] delta in
            guard let self = self else { return }
            self.pollingQueue.async {
                self.processTouchpadMovement(delta)
            }
        }

        // Touchpad gesture handler (DualSense two-finger)
        controllerService.onTouchpadGesture = { [weak self] gesture in
            guard let self = self else { return }
            self.pollingQueue.async {
                self.processTouchpadGesture(gesture)
            }
        }

        // Touchpad tap handler (single tap = left click by default)
        controllerService.onTouchpadTap = { [weak self] in
            guard let self = self else { return }
            self.pollingQueue.async {
                self.processTouchpadTap()
            }
        }

        // Touchpad two-finger tap handler (two-finger tap or two-finger + click = right click)
        controllerService.onTouchpadTwoFingerTap = { [weak self] in
            guard let self = self else { return }
            self.pollingQueue.async {
                self.processTouchpadTwoFingerTap()
            }
        }

        // Touchpad long tap handler (touch held without moving)
        controllerService.onTouchpadLongTap = { [weak self] in
            guard let self = self else { return }
            self.pollingQueue.async {
                self.processTouchpadLongTap()
            }
        }

        // Touchpad two-finger long tap handler
        controllerService.onTouchpadTwoFingerLongTap = { [weak self] in
            guard let self = self else { return }
            self.pollingQueue.async {
                self.processTouchpadTwoFingerLongTap()
            }
        }

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
                if enabled {
                    if self.controllerService.isConnected {
                        self.startTouchpadMomentumTimer()
                    }
                } else {
                    self.stopTouchpadMomentumTimer()
                }
            }
            .store(in: &cancellables)
    }

    private func startTouchpadMomentumTimer() {
        guard touchpadMomentumTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: pollingQueue)
        timer.schedule(deadline: .now(), repeating: Config.touchpadMomentumTickInterval)
        timer.setEventHandler { [weak self] in
            self?.processTouchpadMomentumTick()
        }
        timer.resume()
        touchpadMomentumTimer = timer
    }

    private func stopTouchpadMomentumTimer() {
        touchpadMomentumTimer?.cancel()
        touchpadMomentumTimer = nil
        stopTouchpadMomentum(emitEnd: true)
    }

    nonisolated private func stopTouchpadMomentum(emitEnd: Bool) {
        var wasActive = false
        state.lock.lock()
        wasActive = state.touchpadMomentumWasActive
        state.touchpadMomentumVelocity = .zero
        state.touchpadMomentumWasActive = false
        state.touchpadMomentumLastUpdate = 0
        state.touchpadMomentumLastGestureTime = 0
        state.touchpadMomentumCandidateVelocity = .zero
        state.touchpadMomentumCandidateTime = 0
        state.touchpadMomentumHighVelocityStartTime = 0
            state.touchpadMomentumHighVelocitySampleCount = 0
            state.touchpadMomentumPeakVelocity = .zero
            state.touchpadMomentumPeakMagnitude = 0
        state.smoothedTouchpadPanVelocity = .zero
        state.touchpadScrollResidualX = 0
        state.touchpadScrollResidualY = 0
        state.lock.unlock()

        if emitEnd, wasActive {
            inputSimulator.scroll(
                dx: 0,
                dy: 0,
                phase: nil,
                momentumPhase: .end,
                isContinuous: true,
                flags: []
            )
        }
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
        let lastTap = state.lastTapTime[button]
        state.lock.unlock()

        guard let mapping = effectiveMapping(for: button, in: profile) else {
            // Log unmapped button presses so they still appear in history
            inputLogService?.log(buttons: [button], type: .singlePress, action: "(unmapped)")
            return
        }

        #if DEBUG
        print("🔵 handleButtonPressed: \(button.displayName)")
        #endif

        // Check for special actions
        let isOnScreenKeyboard = mapping.keyCode == KeyCodeMapping.showOnScreenKeyboard
        if isOnScreenKeyboard {
            handleOnScreenKeyboardPressed(button, holdMode: mapping.isHoldModifier)
            return
        }

        // Determine if this should be treated as a held mapping
        let isMouseClick = mapping.keyCode.map { KeyCodeMapping.isMouseButton($0) } ?? false
        let isChordPart = isButtonUsedInChords(button, profile: profile)
        let hasDoubleTap = mapping.doubleTapMapping != nil && !mapping.doubleTapMapping!.isEmpty
        let shouldTreatAsHold = mapping.isHoldModifier || (isMouseClick && !isChordPart && !hasDoubleTap)

        if shouldTreatAsHold {
            handleHoldMapping(button, mapping: mapping, lastTap: lastTap)
            return
        }

        // Set up long-hold timer if applicable
        if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
            setupLongHoldTimer(for: button, mapping: longHold)
        }

        // Set up repeat if applicable
        if let repeatConfig = mapping.repeatMapping, repeatConfig.enabled {
            startRepeatTimer(for: button, mapping: mapping, interval: repeatConfig.interval)
        }
    }

    /// Handles mapping that should be treated as continuously held
    nonisolated private func handleHoldMapping(_ button: ControllerButton, mapping: KeyMapping, lastTap: Date?) {
        // Check for double-tap
        if let doubleTapMapping = mapping.doubleTapMapping, !doubleTapMapping.isEmpty {
            let now = Date()
            if let lastTap = lastTap, now.timeIntervalSince(lastTap) <= doubleTapMapping.threshold {
                state.lock.lock()
                defer { state.lock.unlock() }
                state.lastTapTime.removeValue(forKey: button)
                mappingExecutor.executeDoubleTap(doubleTapMapping, for: button)
                return
            }
            state.lock.lock()
            defer { state.lock.unlock() }
            state.lastTapTime[button] = now
        }

        // Start holding the mapping
        do {
            state.lock.lock()
            defer { state.lock.unlock() }
            state.heldButtons[button] = mapping
        }

        inputSimulator.startHoldMapping(mapping)
        inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)
    }

    /// Handles on-screen keyboard button press
    /// - holdMode: If true, shows keyboard while held. If false, toggles keyboard on/off.
    nonisolated private func handleOnScreenKeyboardPressed(_ button: ControllerButton, holdMode: Bool) {
        state.lock.lock()
        state.onScreenKeyboardButton = button
        state.onScreenKeyboardHoldMode = holdMode
        state.lock.unlock()

        DispatchQueue.main.async {
            if holdMode {
                // Hold mode: always show on press
                OnScreenKeyboardManager.shared.show()
            } else {
                // Toggle mode: toggle visibility on press
                OnScreenKeyboardManager.shared.toggle()
            }
        }
        inputLogService?.log(buttons: [button], type: .singlePress, action: "On-Screen Keyboard")
    }

    /// Handles on-screen keyboard button release (hides keyboard only in hold mode)
    nonisolated private func handleOnScreenKeyboardReleased(_ button: ControllerButton) {
        state.lock.lock()
        let wasKeyboardButton = state.onScreenKeyboardButton == button
        let wasHoldMode = state.onScreenKeyboardHoldMode
        if wasKeyboardButton {
            state.onScreenKeyboardButton = nil
        }
        state.lock.unlock()

        // Only hide on release if in hold mode
        if wasKeyboardButton && wasHoldMode {
            DispatchQueue.main.async {
                OnScreenKeyboardManager.shared.hide()
            }
        }
    }

    /// Sets up a timer for long-hold detection
    nonisolated private func setupLongHoldTimer(for button: ControllerButton, mapping: LongHoldMapping) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.handleLongHoldTriggered(button, mapping: mapping)
        }
        do {
            state.lock.lock()
            defer { state.lock.unlock() }
            state.longHoldTimers[button] = workItem
        }
        inputQueue.asyncAfter(deadline: .now() + mapping.threshold, execute: workItem)
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
        defer { state.lock.unlock() }
        state.repeatTimers[button] = timer
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
        
        mappingExecutor.executeLongHold(mapping, for: button)
    }

    nonisolated private func handleButtonReleased(_ button: ControllerButton, holdDuration: TimeInterval) {
        stopRepeatTimer(for: button)

        // Check if this button was showing the on-screen keyboard
        handleOnScreenKeyboardReleased(button)

        // Cleanup: cancel long hold timer and check for held/chord buttons
        if let releaseResult = cleanupReleaseTimers(for: button) {
            if case .heldMapping(let heldMapping) = releaseResult {
                inputSimulator.stopHoldMapping(heldMapping)
            }
            return
        }

        // Get button mapping and verify constraints
        guard let (mapping, profile, bundleId, isLongHoldTriggered) = getReleaseContext(for: button) else { return }

        // Check if this is a repeat mapping - we still want to detect double-taps for these
        let isRepeatMapping = mapping.repeatMapping?.enabled ?? false
        let hasDoubleTap = mapping.doubleTapMapping != nil && !mapping.doubleTapMapping!.isEmpty

        // Skip special cases (hold modifiers, already triggered long holds)
        // But allow repeat mappings through if they have double-tap configured
        if shouldSkipRelease(mapping: mapping, isLongHoldTriggered: isLongHoldTriggered) {
            // Exception: still check for double-tap on repeat mappings
            if isRepeatMapping && hasDoubleTap {
                let (pendingSingle, lastTap) = getPendingTapInfo(for: button)
                _ = handleDoubleTapIfReady(button, mapping: mapping, pendingSingle: pendingSingle, lastTap: lastTap, doubleTapMapping: mapping.doubleTapMapping!, skipSingleTap: true)
            }
            return
        }

        // Try to handle as long hold fallback
        if let longHoldMapping = mapping.longHoldMapping,
           holdDuration >= longHoldMapping.threshold,
           !longHoldMapping.isEmpty {
            clearTapState(for: button)
            mappingExecutor.executeLongHold(longHoldMapping, for: button)
            return
        }

        // Get pending tap info for double-tap detection
        let (pendingSingle, lastTap) = getPendingTapInfo(for: button)

        // Try to handle as double tap
        if let doubleTapMapping = mapping.doubleTapMapping, !doubleTapMapping.isEmpty {
            // handleDoubleTapIfReady returns true if double-tap executed, false if scheduling first tap
            // Either way, we're done - don't call handleSingleTap
            _ = handleDoubleTapIfReady(button, mapping: mapping, pendingSingle: pendingSingle, lastTap: lastTap, doubleTapMapping: doubleTapMapping)
        } else {
            // Default to single tap (no double-tap mapping)
            handleSingleTap(button, mapping: mapping, profile: profile)
        }
    }

    // MARK: - Release Handler Helpers

    /// Result of cleanup checks during button release
    enum ReleaseCleanupResult {
        case heldMapping(KeyMapping)
        case chordButton
    }

    /// Cleanup timers and check for held/chord buttons that bypass normal release handling
    nonisolated private func cleanupReleaseTimers(for button: ControllerButton) -> ReleaseCleanupResult? {
        state.lock.lock()
        defer { state.lock.unlock() }

        // Cancel long hold timer
        if let timer = state.longHoldTimers[button] {
            timer.cancel()
            state.longHoldTimers.removeValue(forKey: button)
        }

        guard state.isEnabled, let profile = state.activeProfile else { return nil }

        // Check for held mapping - must release even for chord buttons
        // (chord fallback may have started a hold mapping that needs cleanup)
        if let heldMapping = state.heldButtons[button] {
            state.heldButtons.removeValue(forKey: button)
            state.activeChordButtons.remove(button)
            return .heldMapping(heldMapping)
        }

        // Check if button is part of active chord - skip normal release handling
        if state.activeChordButtons.contains(button) {
            state.activeChordButtons.remove(button)
            return .chordButton
        }

        return nil
    }

    /// Get the context needed for release handling (mapping, profile, bundleId, etc.)
    nonisolated private func getReleaseContext(for button: ControllerButton) -> (KeyMapping, Profile, String?, Bool)? {
        state.lock.lock()
        defer { state.lock.unlock() }

        guard state.isEnabled, let profile = state.activeProfile else { return nil }

        let bundleId = state.frontmostBundleId
        var isLongHoldTriggered = state.longHoldTriggered.contains(button)
        if isLongHoldTriggered {
            state.longHoldTriggered.remove(button)
        }

        guard let mapping = effectiveMapping(for: button, in: profile) else { return nil }

        return (mapping, profile, bundleId, isLongHoldTriggered)
    }

    /// Returns the effective mapping for a button, using default if profile mapping is empty or missing
    nonisolated private func effectiveMapping(for button: ControllerButton, in profile: Profile) -> KeyMapping? {
        if let mapping = profile.buttonMappings[button], !mapping.isEmpty {
            return mapping
        }
        return defaultMapping(for: button)
    }

    /// Returns a default mapping for buttons that should have fallback behavior
    nonisolated private func defaultMapping(for button: ControllerButton) -> KeyMapping? {
        switch button {
        case .touchpadButton:
            // DualSense touchpad click defaults to left mouse click
            return KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true)
        case .touchpadTwoFingerButton:
            // DualSense touchpad two-finger click defaults to right mouse click
            return KeyMapping(keyCode: KeyCodeMapping.mouseRightClick, isHoldModifier: true)
        case .touchpadTap:
            // DualSense touchpad single tap defaults to left mouse click
            return KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true)
        case .touchpadTwoFingerTap:
            // DualSense touchpad two-finger tap defaults to right mouse click
            return KeyMapping(keyCode: KeyCodeMapping.mouseRightClick, isHoldModifier: true)
        default:
            return nil
        }
    }

    /// Check if button release should be skipped (hold modifier, repeat, already triggered long hold)
    nonisolated private func shouldSkipRelease(mapping: KeyMapping, isLongHoldTriggered: Bool) -> Bool {
        mapping.isHoldModifier || (mapping.repeatMapping?.enabled ?? false) || isLongHoldTriggered
    }

    /// Get pending tap state for double-tap detection
    nonisolated private func getPendingTapInfo(for button: ControllerButton) -> (DispatchWorkItem?, Date?) {
        state.lock.lock()
        defer { state.lock.unlock() }

        return (state.pendingSingleTap[button], state.lastTapTime[button])
    }

    /// Clear pending tap state (used when double-tap window expires or long-hold triggers)
    nonisolated private func clearTapState(for button: ControllerButton) {
        state.lock.lock()
        state.pendingSingleTap[button]?.cancel()
        state.pendingSingleTap.removeValue(forKey: button)
        state.lastTapTime.removeValue(forKey: button)
        state.lock.unlock()
    }

    /// Handle double-tap detection - returns true if double-tap was executed
    /// - Parameter skipSingleTap: If true, don't schedule single-tap fallback (used for repeat mappings where primary action already fired)
    nonisolated private func handleDoubleTapIfReady(
        _ button: ControllerButton,
        mapping: KeyMapping,
        pendingSingle: DispatchWorkItem?,
        lastTap: Date?,
        doubleTapMapping: DoubleTapMapping,
        skipSingleTap: Bool = false
    ) -> Bool {
        let now = Date()

        // Check if we have a pending tap within the double-tap window
        if let lastTap = lastTap,
           now.timeIntervalSince(lastTap) <= doubleTapMapping.threshold {

            if let pending = pendingSingle {
                pending.cancel()
            }
            clearTapState(for: button)
            mappingExecutor.executeDoubleTap(doubleTapMapping, for: button)
            return true
        }

        // First tap in potential double-tap sequence
        state.lock.lock()
        state.lastTapTime[button] = now

        if skipSingleTap {
            // For repeat mappings: just record tap time, don't schedule single-tap
            // (the repeat action already fired on press)
            state.lock.unlock()
            return false
        }

        // Schedule single tap fallback
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.clearTapState(for: button)
            self.inputSimulator.executeMapping(mapping)
            self.inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)
        }
        state.pendingSingleTap[button] = workItem
        state.lock.unlock()

        inputQueue.asyncAfter(deadline: .now() + doubleTapMapping.threshold, execute: workItem)
        return false
    }

    /// Handle single tap - either immediate or delayed if button is part of chord mapping
    nonisolated private func handleSingleTap(_ button: ControllerButton, mapping: KeyMapping, profile: Profile) {
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
        let delay = isChordPart ? Config.chordReleaseProcessingDelay : 0.0

        if delay > 0 {
            inputQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            inputQueue.async(execute: workItem)
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
                inputQueue.asyncAfter(deadline: .now() + Config.modifierReleaseCheckDelay) { [weak self] in
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
        timer.schedule(deadline: .now(), repeating: Config.joystickPollInterval, leeway: .microseconds(100))
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
        let dt = state.lastJoystickSampleTime > 0 ? now - state.lastJoystickSampleTime : Config.joystickPollInterval
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
        let cutoff = Config.joystickMinCutoffFrequency + (Config.joystickMaxCutoffFrequency - Config.joystickMinCutoffFrequency) * t
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
            if abs(rawStick.y) >= abs(rawStick.x) * Config.scrollTapDirectionRatio,
               currentDirection != state.scrollBoostDirection {
                state.scrollBoostDirection = 0
            }
        }

        if isOutside {
            state.rightStickWasOutsideDeadzone = true
            state.rightStickPeakYAbs = max(state.rightStickPeakYAbs, abs(Double(rawStick.y)))
            if abs(rawStick.y) >= abs(rawStick.x) * Config.scrollTapDirectionRatio {
                state.rightStickLastDirection = rawStick.y >= 0 ? 1 : -1
            }
            return
        }

        guard state.rightStickWasOutsideDeadzone else { return }
        state.rightStickWasOutsideDeadzone = false

        if state.rightStickPeakYAbs >= Config.scrollTapThreshold, state.rightStickLastDirection != 0 {
            if now - state.lastRightStickTapTime <= Config.scrollDoubleTapWindow,
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

        // Brief pause after exiting focus mode to let user adjust joystick
        if state.focusExitTime > 0 && (now - state.focusExitTime) < Config.focusExitPauseDuration {
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

        // Exponential smoothing: transition time at configured polling rate
        // alpha = 1 - e^(-dt/tau), where tau is time constant
        state.currentMultiplier += Config.focusMultiplierSmoothingAlpha * (targetMultiplier - state.currentMultiplier)

        let scale = acceleratedMagnitude * state.currentMultiplier / magnitude
        let dx = stick.x * scale
        var dy = stick.y * scale

        dy = settings.invertMouseY ? dy : -dy

        inputSimulator.moveMouse(dx: dx, dy: dy)
    }

    /// Process touchpad tap gesture (uses user mapping, supports double-tap)
    nonisolated private func processTouchpadTap() {
        let button = ControllerButton.touchpadTap
        processTapGesture(button)
    }

    /// Process touchpad two-finger tap gesture (uses user mapping, supports double-tap)
    nonisolated private func processTouchpadTwoFingerTap() {
        let button = ControllerButton.touchpadTwoFingerTap
        processTapGesture(button)
    }

    /// Common handler for tap gestures with double-tap support
    nonisolated private func processTapGesture(_ button: ControllerButton) {
        state.lock.lock()
        guard state.isEnabled, let profile = state.activeProfile else {
            state.lock.unlock()
            return
        }
        let lastTap = state.lastTapTime[button]
        state.lock.unlock()

        guard let mapping = effectiveMapping(for: button, in: profile) else {
            inputLogService?.log(buttons: [button], type: .singlePress, action: "(unmapped)")
            return
        }

        // Check for double-tap
        if let doubleTapMapping = mapping.doubleTapMapping, !doubleTapMapping.isEmpty {
            let now = Date()
            if let lastTap = lastTap, now.timeIntervalSince(lastTap) <= doubleTapMapping.threshold {
                // Double-tap detected
                state.lock.lock()
                state.lastTapTime.removeValue(forKey: button)
                state.pendingSingleTap[button]?.cancel()
                state.pendingSingleTap.removeValue(forKey: button)
                state.lock.unlock()

                mappingExecutor.executeDoubleTap(doubleTapMapping, for: button)
                return
            }

            // Record tap time and schedule delayed single-tap execution
            state.lock.lock()
            state.lastTapTime[button] = now
            state.pendingSingleTap[button]?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.state.lock.lock()
                self.state.pendingSingleTap.removeValue(forKey: button)
                self.state.lock.unlock()

                self.inputSimulator.executeMapping(mapping)
                self.inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)
            }
            state.pendingSingleTap[button] = workItem
            state.lock.unlock()

            inputQueue.asyncAfter(deadline: .now() + doubleTapMapping.threshold, execute: workItem)
            return
        }

        // No double-tap configured, execute immediately
        inputSimulator.executeMapping(mapping)
        inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.displayString)
    }

    /// Process touchpad long tap gesture (executes long hold mapping)
    nonisolated private func processTouchpadLongTap() {
        let button = ControllerButton.touchpadTap
        processLongTapGesture(button)
    }

    /// Process touchpad two-finger long tap gesture (executes long hold mapping)
    nonisolated private func processTouchpadTwoFingerLongTap() {
        let button = ControllerButton.touchpadTwoFingerTap
        processLongTapGesture(button)
    }

    /// Common handler for long tap gestures
    nonisolated private func processLongTapGesture(_ button: ControllerButton) {
        state.lock.lock()
        guard state.isEnabled, let profile = state.activeProfile else {
            state.lock.unlock()
            return
        }
        // Cancel any pending single tap for this button
        state.pendingSingleTap[button]?.cancel()
        state.pendingSingleTap.removeValue(forKey: button)
        state.lastTapTime.removeValue(forKey: button)
        state.lock.unlock()

        // Long tap only executes if there's an explicit long hold mapping configured
        // (no default fallback like regular taps have)
        guard let mapping = profile.buttonMappings[button],
              let longHoldMapping = mapping.longHoldMapping,
              !longHoldMapping.isEmpty else {
            return
        }

        mappingExecutor.executeLongHold(longHoldMapping, for: button)
    }

    /// Process touchpad movement for mouse control (DualSense only)
    /// Unlike joystick which is position-based (continuous velocity), touchpad is delta-based (like a laptop trackpad)
    nonisolated private func processTouchpadMovement(_ delta: CGPoint) {
        state.lock.lock()
        guard state.isEnabled, let settings = state.joystickSettings else {
            state.lock.unlock()
            return
        }
        let isGestureActive = state.isTouchpadGestureActive
        state.lock.unlock()

        let movementBlocked = controllerService.threadSafeIsTouchpadMovementBlocked
        if isGestureActive || movementBlocked {
            state.lock.lock()
            state.smoothedTouchpadDelta = .zero
            state.lastTouchpadSampleTime = 0
            state.lock.unlock()
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        var smoothedDelta: CGPoint = .zero
        var lastSampleTime: TimeInterval = 0

        state.lock.lock()
        smoothedDelta = state.smoothedTouchpadDelta
        lastSampleTime = state.lastTouchpadSampleTime
        state.lock.unlock()

        let resetSmoothing = lastSampleTime == 0 || (now - lastSampleTime) > Config.touchpadSmoothingResetInterval
        if resetSmoothing || settings.touchpadSmoothing <= 0 {
            smoothedDelta = delta
        } else {
            let alpha = max(Config.touchpadMinSmoothingAlpha, 1.0 - settings.touchpadSmoothing)
            smoothedDelta = CGPoint(
                x: smoothedDelta.x + (delta.x - smoothedDelta.x) * alpha,
                y: smoothedDelta.y + (delta.y - smoothedDelta.y) * alpha
            )
        }

        state.lock.lock()
        state.smoothedTouchpadDelta = smoothedDelta
        state.lastTouchpadSampleTime = now
        state.lock.unlock()

        let magnitude = Double(hypot(smoothedDelta.x, smoothedDelta.y))
        guard magnitude > settings.touchpadDeadzone else { return }

        let normalized = min(magnitude / Config.touchpadAccelerationMaxDelta, 1.0)
        let curve = pow(normalized, settings.touchpadAccelerationExponent)
        let accelScale = 1.0 + settings.effectiveTouchpadAcceleration * Config.touchpadAccelerationMaxBoost * curve

        // The touchpad coordinates are normalized (-1 to 1), so delta is small
        // Scale up to get reasonable mouse movement
        // Use mouse sensitivity settings for consistency with left stick
        let sensitivity = settings.mouseMultiplier
            * Config.touchpadSensitivityMultiplier
            * settings.touchpadSensitivityMultiplier

        let dx = Double(smoothedDelta.x) * accelScale * sensitivity
        // Invert Y by default (touchpad up = mouse up, but Y axis is inverted in coordinate system)
        var dy = -Double(smoothedDelta.y) * accelScale * sensitivity

        // Respect mouse Y inversion setting
        if settings.invertMouseY {
            dy = -dy
        }

        inputSimulator.moveMouse(dx: CGFloat(dx), dy: CGFloat(dy))
    }

    // MARK: - Two-Finger Touchpad Gestures

    /// Process two-finger touchpad gestures (pan + pinch zoom)
    /// This method handles:
    /// 1. Gesture lifecycle (begin/change/end phases)
    /// 2. Delta smoothing for consistent feel
    /// 3. Pinch vs Pan discrimination
    /// 4. Native magnify gestures or Cmd+Plus/Minus zoom
    /// 5. Scroll with momentum physics
    nonisolated private func processTouchpadGesture(_ gesture: TouchpadGesture) {
        // MARK: State Snapshot
        state.lock.lock()
        guard state.isEnabled, let settings = state.joystickSettings else {
            state.lock.unlock()
            return
        }
        let wasActive = state.isTouchpadGestureActive
        let isActive = gesture.isPrimaryTouching && gesture.isSecondaryTouching
        state.isTouchpadGestureActive = isActive
        var smoothedCenter = state.smoothedTouchpadCenterDelta
        var smoothedDistance = state.smoothedTouchpadDistanceDelta
        var smoothedVelocity = state.smoothedTouchpadPanVelocity
        let wasMomentumActive = state.touchpadMomentumWasActive
        let lastSampleTime = state.lastTouchpadGestureSampleTime
        var residualX = state.touchpadScrollResidualX
        var residualY = state.touchpadScrollResidualY
        state.lock.unlock()

        if isActive, wasMomentumActive {
            stopTouchpadMomentum(emitEnd: true)
        }

        guard isActive else {
            // End magnify gesture if it was active
            state.lock.lock()
            let wasMagnifyActive = state.touchpadMagnifyGestureActive
            if wasMagnifyActive {
                state.touchpadMagnifyGestureActive = false
                state.touchpadPinchAccumulator = 0
            }
            state.lock.unlock()
            if wasMagnifyActive {
                postMagnifyGestureEvent(0, 2)  // end gesture (phase 2)
            }

            if wasActive {
                inputSimulator.scroll(
                    dx: 0,
                    dy: 0,
                    phase: .ended,
                    momentumPhase: nil,
                    isContinuous: true,
                    flags: []
                )
            }
            let now = CFAbsoluteTimeGetCurrent()
            state.lock.lock()
            let candidateVelocity = state.touchpadMomentumCandidateVelocity
            let candidateTime = state.touchpadMomentumCandidateTime
            let candidateSpeed = Double(hypot(candidateVelocity.x, candidateVelocity.y))
            let shouldStartMomentum = candidateTime > 0 &&
                (now - candidateTime) <= Config.touchpadMomentumReleaseWindow &&
                candidateSpeed >= Config.touchpadMomentumStartVelocity
            if shouldStartMomentum {
                state.touchpadMomentumVelocity = candidateVelocity
                state.touchpadMomentumLastGestureTime = now
                state.touchpadMomentumLastUpdate = now
                state.touchpadMomentumWasActive = false
            } else {
                state.touchpadMomentumVelocity = .zero
                state.touchpadMomentumLastGestureTime = 0
                state.touchpadMomentumLastUpdate = 0
                state.touchpadMomentumWasActive = false
            }
            state.touchpadMomentumCandidateVelocity = .zero
            state.touchpadMomentumCandidateTime = 0
            state.touchpadMomentumHighVelocityStartTime = 0
            state.touchpadMomentumHighVelocitySampleCount = 0
            state.touchpadMomentumPeakVelocity = .zero
            state.touchpadMomentumPeakMagnitude = 0
            state.smoothedTouchpadCenterDelta = .zero
            state.smoothedTouchpadDistanceDelta = 0
            state.lastTouchpadGestureSampleTime = 0
            state.smoothedTouchpadPanVelocity = .zero
            state.touchpadScrollResidualX = 0
            state.touchpadScrollResidualY = 0
            state.lock.unlock()
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        if lastSampleTime == 0 ||
            (now - lastSampleTime) > Config.touchpadSmoothingResetInterval ||
            settings.touchpadSmoothing <= 0 {
            smoothedCenter = gesture.centerDelta
            smoothedDistance = gesture.distanceDelta
        } else {
            let alpha = max(Config.touchpadMinSmoothingAlpha, 1.0 - settings.touchpadSmoothing)
            smoothedCenter = CGPoint(
                x: smoothedCenter.x + (gesture.centerDelta.x - smoothedCenter.x) * alpha,
                y: smoothedCenter.y + (gesture.centerDelta.y - smoothedCenter.y) * alpha
            )
            smoothedDistance += (gesture.distanceDelta - smoothedDistance) * alpha
        }

        state.lock.lock()
        state.smoothedTouchpadCenterDelta = smoothedCenter
        state.smoothedTouchpadDistanceDelta = smoothedDistance
        state.lastTouchpadGestureSampleTime = now
        state.lock.unlock()

        let phase: CGScrollPhase = wasActive ? .changed : .began

        // Always send .began event when gesture starts, even with zero delta
        // Chrome requires seeing .began to initialize its gesture recognizer
        if phase == .began {
            inputSimulator.scroll(
                dx: 0,
                dy: 0,
                phase: .began,
                momentumPhase: nil,
                isContinuous: true,
                flags: []
            )
        }

        // Check if this is a pinch (zoom) gesture vs pan (scroll) gesture
        let pinchMagnitude = abs(smoothedDistance)
        let panMagnitude = Double(hypot(smoothedCenter.x, smoothedCenter.y))
        let ratio = pinchMagnitude / max(panMagnitude, 0.001)

        #if DEBUG
        // Debug logging (disabled in release for performance - this runs at 120Hz)
        // NSLog("[PINCH] pinch=%.4f pan=%.4f ratio=%.2f (need pinch>%.2f, ratio>%.2f)", pinchMagnitude, panMagnitude, ratio, Config.touchpadPinchDeadzone, settings.touchpadZoomToPanRatio)
        #endif

        // Determine if pinch is dominant over pan
        let isPinchGesture = pinchMagnitude > Config.touchpadPinchDeadzone &&
            (panMagnitude < Config.touchpadPanDeadzone ||
             ratio > settings.touchpadZoomToPanRatio)

        if isPinchGesture {
            // Reset pan-related state since we're doing pinch
            state.lock.lock()
            state.smoothedTouchpadPanVelocity = .zero
            state.touchpadMomentumVelocity = .zero
            state.touchpadMomentumCandidateVelocity = .zero
            state.touchpadMomentumCandidateTime = 0
            state.touchpadScrollResidualX = 0
            state.touchpadScrollResidualY = 0

            if settings.touchpadUseNativeZoom {
                // Use native macOS magnify gesture
                // Scale the pinch distance to a reasonable magnification value
                let magnification = smoothedDistance * Config.touchpadPinchSensitivityMultiplier / 1000.0

                // Track accumulated pinch for scroll suppression
                state.touchpadPinchAccumulator += abs(smoothedDistance)

                if !state.touchpadMagnifyGestureActive {
                    // Start new magnify gesture
                    state.touchpadMagnifyGestureActive = true
                    state.lock.unlock()
                    postMagnifyGestureEvent(0, 0)  // begin gesture (phase 0)
                    postMagnifyGestureEvent(magnification, 1)  // first magnify event (phase 1)
                } else {
                    state.lock.unlock()
                    postMagnifyGestureEvent(magnification, 1)  // continue magnify (phase 1)
                }
            } else {
                // Use Cmd+Plus/Minus for zoom (accumulator-based approach)
                // Pinch out (distance increases, positive) = zoom in = Cmd+Plus
                // Pinch in (distance decreases, negative) = zoom out = Cmd+Minus

                // Accumulate pinch delta to trigger discrete zoom steps
                state.touchpadPinchAccumulator += smoothedDistance
                let threshold = 0.08  // Accumulate enough pinch before triggering zoom
                let shouldZoomIn = state.touchpadPinchAccumulator > threshold
                let shouldZoomOut = state.touchpadPinchAccumulator < -threshold

                if shouldZoomIn {
                    // Calculate zoom steps based on accumulated magnitude (1-3 keypresses)
                    let steps = min(3, max(1, Int(state.touchpadPinchAccumulator / threshold)))
                    state.touchpadPinchAccumulator = 0
                    state.lock.unlock()
                    // Cmd+Plus (or Cmd+Equals which is same key)
                    for _ in 0..<steps {
                        inputSimulator.pressKey(KeyCodeMapping.equal, modifiers: [.maskCommand])
                    }
                } else if shouldZoomOut {
                    // Calculate zoom steps based on accumulated magnitude (1-3 keypresses)
                    let steps = min(3, max(1, Int(abs(state.touchpadPinchAccumulator) / threshold)))
                    state.touchpadPinchAccumulator = 0
                    state.lock.unlock()
                    // Cmd+Minus
                    for _ in 0..<steps {
                        inputSimulator.pressKey(KeyCodeMapping.minus, modifiers: [.maskCommand])
                    }
                } else {
                    state.lock.unlock()
                }
            }
            return
        }

        // If we've accumulated significant pinch, suppress scrolling
        // Only suppress when accumulator is large enough to indicate intentional pinch
        state.lock.lock()
        let pinchAccumMagnitude = abs(state.touchpadPinchAccumulator)
        state.lock.unlock()
        if pinchAccumMagnitude > 0.05 {
            return
        }

        guard panMagnitude > Config.touchpadPanDeadzone else {
            let now = CFAbsoluteTimeGetCurrent()
            state.lock.lock()
            state.smoothedTouchpadPanVelocity = .zero
            state.touchpadMomentumVelocity = .zero
            state.touchpadMomentumHighVelocityStartTime = 0
            state.touchpadMomentumHighVelocitySampleCount = 0
            state.touchpadMomentumPeakVelocity = .zero
            state.touchpadMomentumPeakMagnitude = 0
            if state.touchpadMomentumCandidateTime > 0,
               (now - state.touchpadMomentumCandidateTime) > Config.touchpadMomentumReleaseWindow {
                state.touchpadMomentumCandidateVelocity = .zero
                state.touchpadMomentumCandidateTime = 0
            }
            state.touchpadScrollResidualX = 0
            state.touchpadScrollResidualY = 0
            state.lock.unlock()
            return
        }

        let panScale = settings.touchpadPanSensitivity * Config.touchpadPanSensitivityMultiplier
        var dx = Double(smoothedCenter.x) * panScale
        var dy = -Double(smoothedCenter.y) * panScale
        dy = settings.invertScrollY ? -dy : dy

        let sampleInterval = lastSampleTime == 0 ? Config.touchpadMomentumMinDeltaTime : (now - lastSampleTime)
        let dt = max(sampleInterval, Config.touchpadMomentumMinDeltaTime)
        let velocityX = dx / dt
        let velocityY = dy / dt
        let velocityAlpha = Config.touchpadMomentumVelocitySmoothingAlpha
        smoothedVelocity = CGPoint(
            x: smoothedVelocity.x + (velocityX - smoothedVelocity.x) * velocityAlpha,
            y: smoothedVelocity.y + (velocityY - smoothedVelocity.y) * velocityAlpha
        )
        let velocityMagnitude = Double(hypot(smoothedVelocity.x, smoothedVelocity.y))
        state.lock.lock()
        state.smoothedTouchpadPanVelocity = smoothedVelocity
        if velocityMagnitude <= Config.touchpadMomentumStopVelocity {
            state.touchpadMomentumCandidateVelocity = .zero
            state.touchpadMomentumCandidateTime = 0
            state.touchpadMomentumHighVelocityStartTime = 0
            state.touchpadMomentumHighVelocitySampleCount = 0
            state.touchpadMomentumPeakVelocity = .zero
            state.touchpadMomentumPeakMagnitude = 0
        } else if velocityMagnitude >= Config.touchpadMomentumStartVelocity {
            // Track high velocity samples and peak
            state.touchpadMomentumHighVelocitySampleCount += 1
            if velocityMagnitude > state.touchpadMomentumPeakMagnitude {
                state.touchpadMomentumPeakMagnitude = velocityMagnitude
                state.touchpadMomentumPeakVelocity = smoothedVelocity
            }

            // Require 2+ samples to filter out edge-exit spikes (single sample spikes)
            if state.touchpadMomentumHighVelocitySampleCount >= 2 {
                // Use peak velocity for momentum calculation
                let peakMagnitude = state.touchpadMomentumPeakMagnitude
                let peakVelocity = state.touchpadMomentumPeakVelocity
                let clampedMagnitude = min(peakMagnitude, Config.touchpadMomentumMaxVelocity)
                let velocityScale = peakMagnitude > 0 ? clampedMagnitude / peakMagnitude : 0
                // Scale boost based on velocity - lower boost near threshold, higher at fast speeds
                let boostRange = Config.touchpadMomentumBoostMax - Config.touchpadMomentumBoostMin
                let velocityRange = Config.touchpadMomentumBoostMaxVelocity - Config.touchpadMomentumStartVelocity
                let velocityAboveThreshold = min(peakMagnitude - Config.touchpadMomentumStartVelocity, velocityRange)
                let boostFactor = velocityAboveThreshold / velocityRange
                let boost = Config.touchpadMomentumBoostMin + boostRange * boostFactor
                let clampedVelocity = CGPoint(
                    x: peakVelocity.x * velocityScale * boost,
                    y: peakVelocity.y * velocityScale * boost
                )
                state.touchpadMomentumCandidateVelocity = clampedVelocity
                state.touchpadMomentumCandidateTime = now
            }
        } else {
            // Velocity is between stop and start thresholds - reset high velocity tracking
            state.touchpadMomentumHighVelocityStartTime = 0
            state.touchpadMomentumHighVelocitySampleCount = 0
            state.touchpadMomentumPeakVelocity = .zero
            state.touchpadMomentumPeakMagnitude = 0
        }
        state.lock.unlock()

        let combinedDx = dx + residualX
        let combinedDy = dy + residualY
        let sendDx = combinedDx.rounded(.towardZero)
        let sendDy = combinedDy.rounded(.towardZero)
        residualX = combinedDx - sendDx
        residualY = combinedDy - sendDy
        state.lock.lock()
        state.touchpadScrollResidualX = residualX
        state.touchpadScrollResidualY = residualY
        state.lock.unlock()
        guard abs(sendDx) >= 1 || abs(sendDy) >= 1 else { return }
        // Always use .changed here since .began was already sent at gesture start
        inputSimulator.scroll(
            dx: CGFloat(sendDx),
            dy: CGFloat(sendDy),
            phase: .changed,
            momentumPhase: nil,
            isContinuous: true,
            flags: []
        )
    }

    nonisolated private func processTouchpadMomentumTick() {
        state.lock.lock()
        guard state.isEnabled else {
            state.lock.unlock()
            return
        }
        let isGestureActive = state.isTouchpadGestureActive
        let lastGestureTime = state.touchpadMomentumLastGestureTime
        var velocity = state.touchpadMomentumVelocity
        var wasActive = state.touchpadMomentumWasActive
        var residualX = state.touchpadScrollResidualX
        var residualY = state.touchpadScrollResidualY
        let lastUpdate = state.touchpadMomentumLastUpdate
        state.lock.unlock()

        if isGestureActive {
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        if lastUpdate == 0 {
            state.lock.lock()
            state.touchpadMomentumLastUpdate = now
            state.lock.unlock()
            return
        }

        let idleInterval = now - lastGestureTime
        if idleInterval > Config.touchpadMomentumMaxIdleInterval {
            if wasActive {
                inputSimulator.scroll(
                    dx: 0,
                    dy: 0,
                    phase: nil,
                    momentumPhase: .end,
                    isContinuous: true,
                    flags: []
                )
            }
            state.lock.lock()
            state.touchpadMomentumVelocity = .zero
            state.touchpadMomentumWasActive = false
            state.touchpadMomentumLastUpdate = now
            state.touchpadScrollResidualX = 0
            state.touchpadScrollResidualY = 0
            state.lock.unlock()
            return
        }

        let dt = max(now - lastUpdate, Config.touchpadMomentumMinDeltaTime)
        let decay = exp(-Config.touchpadMomentumDecay * dt)
        velocity = CGPoint(x: velocity.x * decay, y: velocity.y * decay)
        let speed = Double(hypot(velocity.x, velocity.y))
        if speed < Config.touchpadMomentumStopVelocity {
            if wasActive {
                inputSimulator.scroll(
                    dx: 0,
                    dy: 0,
                    phase: nil,
                    momentumPhase: .end,
                    isContinuous: true,
                    flags: []
                )
            }
            state.lock.lock()
            state.touchpadMomentumVelocity = .zero
            state.touchpadMomentumWasActive = false
            state.touchpadMomentumLastUpdate = now
            state.touchpadScrollResidualX = 0
            state.touchpadScrollResidualY = 0
            state.lock.unlock()
            return
        }

        let dx = Double(velocity.x) * dt
        let dy = Double(velocity.y) * dt
        let combinedDx = dx + residualX
        let combinedDy = dy + residualY
        let sendDx = combinedDx.rounded(.towardZero)
        let sendDy = combinedDy.rounded(.towardZero)
        residualX = combinedDx - sendDx
        residualY = combinedDy - sendDy

        if abs(sendDx) >= 1 || abs(sendDy) >= 1 {
            let momentumPhase: CGMomentumScrollPhase = wasActive ? .continuous : .begin
            inputSimulator.scroll(
                dx: CGFloat(sendDx),
                dy: CGFloat(sendDy),
                phase: nil,
                momentumPhase: momentumPhase,
                isContinuous: true,
                flags: []
            )
            wasActive = true
        }

        state.lock.lock()
        state.touchpadMomentumVelocity = velocity
        state.touchpadMomentumWasActive = wasActive
        state.touchpadMomentumLastUpdate = now
        state.touchpadScrollResidualX = residualX
        state.touchpadScrollResidualY = residualY
        state.lock.unlock()
    }

    /// Performs haptic feedback for focus mode transitions on the controller
    nonisolated private func performFocusModeHaptic(entering: Bool) {
        // Both enter and exit get strong haptics, but with different feel
        let intensity: Float = entering ? Config.focusEntryHapticIntensity : Config.focusExitHapticIntensity
        let sharpness: Float = entering ? Config.focusEntryHapticSharpness : Config.focusExitHapticSharpness
        let duration: TimeInterval = entering ? Config.focusEntryHapticDuration : Config.focusExitHapticDuration
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
