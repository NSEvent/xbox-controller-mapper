import Foundation
import Combine
import CoreGraphics

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
///
/// Sub-services (implemented as extensions on MappingEngine):
/// - `JoystickHandler` — joystick polling, mouse/scroll movement, direction keys, focus mode, gyro
/// - `TouchpadInputHandler` — touchpad movement, two-finger gestures, momentum scrolling
/// - `MotionInputHandler` — gyro gesture detection and execution
/// - `UIIntegrationService` — on-screen keyboard, command wheel, laser pointer, directory navigator

@MainActor
class MappingEngine: ObservableObject {
    @Published var isEnabled = true
    @Published var isLocked = false

    let controllerService: ControllerService
    let profileManager: ProfileManager
    private let appMonitor: AppMonitor
    nonisolated let inputSimulator: InputSimulatorProtocol
    let inputLogService: InputLogService?
    nonisolated let usageStatsService: UsageStatsService?
    nonisolated let mappingExecutor: MappingExecutor
    nonisolated let scriptEngine: ScriptEngine

    // MARK: - Thread-Safe State

    let inputQueue = DispatchQueue(label: "com.xboxmapper.input", qos: .userInteractive)
    let pollingQueue = DispatchQueue(label: "com.xboxmapper.polling", qos: .userInteractive)

    let state = EngineState()

    // Joystick polling
    var joystickTimer: DispatchSourceTimer?

    private var cancellables = Set<AnyCancellable>()

    init(controllerService: ControllerService, profileManager: ProfileManager, appMonitor: AppMonitor, inputSimulator: InputSimulatorProtocol = InputSimulator(), inputLogService: InputLogService? = nil, usageStatsService: UsageStatsService? = nil) {
        self.controllerService = controllerService
        self.profileManager = profileManager
        self.appMonitor = appMonitor
        self.inputSimulator = inputSimulator
        self.inputLogService = inputLogService
        self.usageStatsService = usageStatsService

        // Create script engine for JavaScript scripting support
        let engine = ScriptEngine(
            inputSimulator: inputSimulator,
            inputQueue: inputQueue,
            controllerService: controllerService,
            inputLogService: inputLogService
        )
        self.scriptEngine = engine

        self.mappingExecutor = MappingExecutor(inputSimulator: inputSimulator, inputQueue: inputQueue, inputLogService: inputLogService, profileManager: profileManager, usageStatsService: usageStatsService, scriptEngine: engine)

        // Set up on-screen keyboard manager with our input simulator
        OnScreenKeyboardManager.shared.setInputSimulator(inputSimulator)
        Task { @MainActor in
            if let service = usageStatsService {
                OnScreenKeyboardManager.shared.setUsageStatsService(service)
                CommandWheelManager.shared.setUsageStatsService(service)
            }
        }
        Task { @MainActor [weak self] in
            OnScreenKeyboardManager.shared.setHapticHandler { [weak self] in
                self?.controllerService.playHaptic(
                    intensity: Config.keyboardActionHapticIntensity,
                    sharpness: Config.keyboardActionHapticSharpness,
                    duration: Config.keyboardActionHapticDuration,
                    transient: true
                )
            }
        }

        // Set up webhook feedback handler for haptics and visual feedback
        mappingExecutor.systemCommandExecutor.webhookFeedbackHandler = { [weak self] success, message in
            guard let self = self else { return }

            if success {
                self.controllerService.playHaptic(
                    intensity: Config.webhookSuccessHapticIntensity,
                    sharpness: Config.webhookSuccessHapticSharpness,
                    duration: Config.webhookSuccessHapticDuration,
                    transient: true
                )
            } else {
                self.controllerService.playHaptic(
                    intensity: Config.webhookFailureHapticIntensity,
                    sharpness: Config.webhookFailureHapticSharpness,
                    duration: Config.webhookFailureHapticDuration,
                    transient: false
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + Config.webhookFailureHapticGap + Config.webhookFailureHapticDuration) {
                    self.controllerService.playHaptic(
                        intensity: Config.webhookFailureHapticIntensity,
                        sharpness: Config.webhookFailureHapticSharpness,
                        duration: Config.webhookFailureHapticDuration,
                        transient: false
                    )
                }
            }

            Task { @MainActor in
                ActionFeedbackIndicator.shared.show(
                    action: message,
                    type: success ? .webhookSuccess : .webhookFailure
                )
            }
        }

        setupBindings()

        // Initial state sync
        self.state.activeProfile = profileManager.activeProfile
        self.state.joystickSettings = profileManager.activeProfile?.joystickSettings
        let oskSettings = profileManager.activeProfile?.onScreenKeyboardSettings
        self.state.swipeTypingEnabled = oskSettings?.swipeTypingEnabled ?? false
        self.state.swipeTypingSensitivity = oskSettings?.swipeTypingSensitivity ?? 0.5
        self.state.frontmostBundleId = appMonitor.frontmostBundleId
        rebuildLayerActivatorMap(profile: profileManager.activeProfile)
        syncGestureSettings(from: profileManager.activeProfile?.joystickSettings)
    }

    /// Rebuilds the layer activator button -> layer ID lookup map
    private func rebuildLayerActivatorMap(profile: Profile?) {
        state.layerActivatorMap.removeAll()
        guard let profile = profile else { return }
        for layer in profile.layers {
            if let activatorButton = layer.activatorButton {
                state.layerActivatorMap[activatorButton] = layer.id
            }
        }
    }

    /// Pushes effective gesture detection settings from the profile into ControllerStorage
    /// so the motion callback thread can read them without accessing JoystickSettings.
    private func syncGestureSettings(from settings: JoystickSettings?) {
        let settings = settings ?? .default
        controllerService.storage.lock.lock()
        controllerService.storage.gestureActivationThreshold = settings.effectiveGestureActivationThreshold
        controllerService.storage.gestureMinPeakVelocity = settings.effectiveGestureMinPeakVelocity
        controllerService.storage.gestureRollActivationThreshold = settings.effectiveGestureRollActivationThreshold
        controllerService.storage.gestureRollMinPeakVelocity = settings.effectiveGestureRollMinPeakVelocity
        controllerService.storage.gestureCooldown = settings.effectiveGestureCooldown
        controllerService.storage.gestureOppositeDirectionCooldown = settings.effectiveGestureOppositeDirectionCooldown
        controllerService.storage.lock.unlock()
    }

    private func setupBindings() {
        // Sync Profile
        profileManager.$activeProfile
            .sink { [weak self] profile in
                guard let self = self else { return }
                self.state.lock.withLock {
                    self.state.activeProfile = profile
                    self.state.joystickSettings = profile?.joystickSettings
                    let osk = profile?.onScreenKeyboardSettings
                    self.state.swipeTypingEnabled = osk?.swipeTypingEnabled ?? false
                    self.state.swipeTypingSensitivity = osk?.swipeTypingSensitivity ?? 0.5
                    self.state.activeLayerIds.removeAll()
                    self.rebuildLayerActivatorMap(profile: profile)
                }
                self.syncGestureSettings(from: profile?.joystickSettings)
                self.scriptEngine.clearState()
            }
            .store(in: &cancellables)

        // Sync App Bundle ID
        appMonitor.$frontmostBundleId
            .sink { [weak self] bundleId in
                guard let self = self else { return }
                self.state.lock.withLock {
                    self.state.frontmostBundleId = bundleId
                }
            }
            .store(in: &cancellables)

        // Controller input callbacks — route each event to the appropriate queue.
        // The unified handleControllerInput(_:) method is also available as a
        // single entry point that can be used by external consumers or tests.
        controllerService.onButtonPressed = { [weak self] button in
            guard let self = self else { return }
            self.inputQueue.async {
                self.handleButtonPressed(button)
            }
        }
        controllerService.onButtonReleased = { [weak self] button, duration in
            guard let self = self else { return }
            self.inputQueue.async {
                self.handleButtonReleased(button, holdDuration: duration)
            }
        }
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
                    self?.startJoystickPollingIfNeeded()
                } else {
                    self?.stopJoystickPollingInternal()
                }
            }
            .store(in: &cancellables)

        // Apply LED settings only when DualSense first connects
        controllerService.$isConnected
            .removeDuplicates()
            .filter { $0 == true }
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

        controllerService.onTouchpadMoved = { [weak self] delta in
            guard let self = self else { return }
            self.pollingQueue.async {
                self.processTouchpadMovement(delta)
            }
        }
        controllerService.onTouchpadGesture = { [weak self] gesture in
            guard let self = self else { return }
            self.pollingQueue.async {
                self.processTouchpadGesture(gesture)
            }
        }
        controllerService.onTouchpadTap = { [weak self] in
            guard let self = self else { return }
            self.pollingQueue.async {
                self.processTouchpadTap()
            }
        }
        controllerService.onTouchpadTwoFingerTap = { [weak self] in
            guard let self = self else { return }
            self.pollingQueue.async {
                self.processTouchpadTwoFingerTap()
            }
        }
        controllerService.onTouchpadLongTap = { [weak self] in
            guard let self = self else { return }
            self.pollingQueue.async {
                self.processTouchpadLongTap()
            }
        }
        controllerService.onTouchpadTwoFingerLongTap = { [weak self] in
            guard let self = self else { return }
            self.pollingQueue.async {
                self.processTouchpadTwoFingerLongTap()
            }
        }
        controllerService.onMotionGesture = { [weak self] gestureType in
            guard let self = self else { return }
            self.inputQueue.async {
                self.processMotionGesture(gestureType)
            }
        }

        // Enable/Disable toggle sync
        $isEnabled
            .sink { [weak self] enabled in
                guard let self = self else { return }
                let keysToRelease: (left: Set<CGKeyCode>, right: Set<CGKeyCode>)? = self.state.lock.withLock {
                    self.state.isEnabled = enabled
                    guard !enabled else { return nil }
                    let leftKeys = self.state.leftStickHeldKeys
                    let rightKeys = self.state.rightStickHeldKeys
                    self.state.reset()
                    return (leftKeys, rightKeys)
                }
                if let keysToRelease {
                    self.inputSimulator.releaseAllModifiers()
                    for key in keysToRelease.left {
                        self.inputSimulator.keyUp(key)
                    }
                    for key in keysToRelease.right {
                        self.inputSimulator.keyUp(key)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Unified Controller Input Handler

    /// Single entry point for all controller input events.
    /// Routes each event to the appropriate dispatch queue and handler method.
    nonisolated func handleControllerInput(_ event: ControllerInputEvent) {
        switch event {
        case .buttonPressed(let button):
            inputQueue.async { self.handleButtonPressed(button) }
        case .buttonReleased(let button, let duration):
            inputQueue.async { self.handleButtonReleased(button, holdDuration: duration) }
        case .chord(let buttons):
            inputQueue.async { self.handleChord(buttons) }
        case .touchpadMoved(let delta):
            pollingQueue.async { self.processTouchpadMovement(delta) }
        case .touchpadGesture(let gesture):
            pollingQueue.async { self.processTouchpadGesture(gesture) }
        case .touchpadTap:
            pollingQueue.async { self.processTouchpadTap() }
        case .touchpadTwoFingerTap:
            pollingQueue.async { self.processTouchpadTwoFingerTap() }
        case .touchpadLongTap:
            pollingQueue.async { self.processTouchpadLongTap() }
        case .touchpadTwoFingerLongTap:
            pollingQueue.async { self.processTouchpadTwoFingerLongTap() }
        case .motionGesture(let gestureType):
            inputQueue.async { self.processMotionGesture(gestureType) }
        }
    }

    // MARK: - Button Handling (Background Queue)

    nonisolated private func isButtonUsedInChords(_ button: ControllerButton, profile: Profile) -> Bool {
        return profile.chordMappings.contains { chord in
            chord.buttons.contains(button)
        }
    }

    nonisolated private func isButtonUsedInSequences(_ button: ControllerButton, profile: Profile) -> Bool {
        return profile.sequenceMappings.contains { seq in
            seq.steps.contains(button)
        }
    }

    // MARK: - Sequence Detection (Zero-Latency)

    nonisolated private func advanceSequenceTracking(_ button: ControllerButton, profile: Profile, chordWindow: TimeInterval = 0) {
        let now = Date()

        let completedSequence: SequenceMapping? = state.lock.withLock {
            var survivingSequences: [EngineState.SequenceProgress] = []
            for var seq in state.activeSequences {
                let sinceLastStep = now.timeIntervalSince(seq.lastStepTime)
                let effectiveTimeout = seq.stepTimeout + chordWindow
                if sinceLastStep <= effectiveTimeout && seq.matchedCount < seq.steps.count && button == seq.steps[seq.matchedCount] {
                    seq.matchedCount += 1
                    seq.lastStepTime = now
                    survivingSequences.append(seq)
                }
            }

            let trackedIds = Set(survivingSequences.map { $0.sequenceId })
            for seq in profile.sequenceMappings where seq.isValid {
                if !trackedIds.contains(seq.id) && seq.steps[0] == button {
                    survivingSequences.append(EngineState.SequenceProgress(
                        sequenceId: seq.id,
                        steps: seq.steps,
                        stepTimeout: seq.stepTimeout,
                        matchedCount: 1,
                        lastStepTime: now
                    ))
                }
            }

            if let completedIdx = survivingSequences.firstIndex(where: { $0.matchedCount == $0.steps.count }) {
                let completed = survivingSequences[completedIdx]
                let sequence = profile.sequenceMappings.first { $0.id == completed.sequenceId }

                survivingSequences.remove(at: completedIdx)
                state.activeSequences = survivingSequences
                return sequence
            }

            state.activeSequences = survivingSequences
            return nil
        }

        if let sequence = completedSequence {
            if let keyCode = sequence.keyCode {
                if keyCode == KeyCodeMapping.controllerLock {
                    _ = performLockToggle()
                    inputLogService?.log(buttons: sequence.steps, type: .sequence, action: "Controller Lock")
                    return
                }

                if state.lock.withLock({ state.isLocked }) { return }

                if keyCode == KeyCodeMapping.showLaserPointer {
                    DispatchQueue.main.async {
                        LaserPointerOverlay.shared.toggle()
                    }
                    inputLogService?.log(buttons: sequence.steps, type: .sequence, action: "Laser Pointer")
                    return
                }
                if keyCode == KeyCodeMapping.showOnScreenKeyboard {
                    DispatchQueue.main.async {
                        OnScreenKeyboardManager.shared.toggle()
                    }
                    inputLogService?.log(buttons: sequence.steps, type: .sequence, action: "On-Screen Keyboard")
                    return
                }
                if keyCode == KeyCodeMapping.showDirectoryNavigator {
                    DispatchQueue.main.async {
                        DirectoryNavigatorManager.shared.toggle()
                    }
                    inputLogService?.log(buttons: sequence.steps, type: .sequence, action: "Directory Navigator")
                    return
                }
            } else {
                if state.lock.withLock({ state.isLocked }) { return }
            }
            mappingExecutor.executeAction(sequence, for: sequence.steps, profile: profile, logType: .sequence)
        }
    }

    private enum ButtonPressStartState {
        case blocked
        case layerActivated(profile: Profile, layerId: UUID)
        case ready(profile: Profile, lastTap: Date?)
    }

    nonisolated private func beginButtonPress(_ button: ControllerButton) -> ButtonPressStartState {
        state.lock.withLock {
            guard state.isEnabled, let profile = state.activeProfile else {
                return .blocked
            }

            let lastTap = state.lastTapTime[button]
            if let layerId = state.layerActivatorMap[button] {
                state.activeLayerIds.removeAll { $0 == layerId }
                state.activeLayerIds.append(layerId)
                return .layerActivated(profile: profile, layerId: layerId)
            }

            return .ready(profile: profile, lastTap: lastTap)
        }
    }

    nonisolated private func resolveButtonPressOutcome(
        _ button: ControllerButton,
        profile: Profile,
        lastTap: Date?
    ) -> ButtonPressOrchestrationPolicy.Outcome {
        let keyboardVisible = OnScreenKeyboardManager.shared.threadSafeIsVisible
        let directoryNavigatorVisible = DirectoryNavigatorManager.shared.threadSafeIsVisible
        let mapping = effectiveMapping(for: button, in: profile)
        let navigationModeActive = keyboardVisible ? OnScreenKeyboardManager.shared.threadSafeNavigationModeActive : false
        let isChordPart = mapping != nil ? isButtonUsedInChords(button, profile: profile) : false

        return ButtonPressOrchestrationPolicy.resolve(
            button: button,
            mapping: mapping,
            keyboardVisible: keyboardVisible,
            navigationModeActive: navigationModeActive,
            directoryNavigatorVisible: directoryNavigatorVisible,
            isChordPart: isChordPart,
            lastTap: lastTap
        )
    }

    /// - Precondition: Must be called on inputQueue
    nonisolated private func handleButtonPressed(_ button: ControllerButton) {
        dispatchPrecondition(condition: .onQueue(inputQueue))
        switch beginButtonPress(button) {
        case .blocked:
            return

        case .layerActivated(let profile, let layerId):
            if let layer = profile.layers.first(where: { $0.id == layerId }) {
                #if DEBUG
                print("🔷 Layer activated: \(layer.name)")
                #endif
                inputLogService?.log(buttons: [button], type: .singlePress, action: "Layer: \(layer.name)")
            }
            return

        case .ready(let profile, let lastTap):
            if !profile.sequenceMappings.isEmpty {
                let chordWindow = controllerService.threadSafeChordWindow
                advanceSequenceTracking(button, profile: profile, chordWindow: chordWindow)
            }

            let outcome = resolveButtonPressOutcome(button, profile: profile, lastTap: lastTap)

            if state.lock.withLock({ state.isLocked }) {
                if case .interceptControllerLock = outcome {
                    _ = performLockToggle()
                }
                return
            }

            switch outcome {
            case .interceptDpadNavigation:
                Task { @MainActor in
                    OnScreenKeyboardManager.shared.handleDPadNavigation(button)
                }
                startDpadNavigationRepeat(button)
                return

            case .interceptKeyboardActivation:
                DispatchQueue.main.async {
                    OnScreenKeyboardManager.shared.activateHighlightedKey()
                }
                return

            case .interceptOnScreenKeyboard(let holdMode):
                handleOnScreenKeyboardPressed(button, holdMode: holdMode)
                return

            case .interceptLaserPointer(let holdMode):
                handleLaserPointerPressed(button, holdMode: holdMode)
                return

            case .interceptControllerLock:
                _ = performLockToggle()
                return

            case .interceptDirectoryNavigator(let holdMode):
                handleDirectoryNavigatorPressed(button, holdMode: holdMode)
                return

            case .interceptDirectoryNavigation:
                Task { @MainActor in
                    DirectoryNavigatorManager.shared.handleDPadNavigation(button)
                }
                startDpadNavigationRepeat(button)
                return

            case .interceptDirectoryConfirm:
                DispatchQueue.main.async {
                    DirectoryNavigatorManager.shared.dismissAndCd()
                }
                return

            case .interceptDirectoryDismiss:
                DispatchQueue.main.async {
                    DirectoryNavigatorManager.shared.hide()
                }
                return

            case .interceptSwipePredictionNavigation:
                controllerService.playHaptic(
                    intensity: Config.keyboardActionHapticIntensity,
                    sharpness: Config.keyboardActionHapticSharpness,
                    duration: Config.keyboardActionHapticDuration,
                    transient: true
                )
                DispatchQueue.main.async {
                    if button == .dpadRight {
                        SwipeTypingEngine.shared.selectNextPrediction()
                    } else {
                        SwipeTypingEngine.shared.selectPreviousPrediction()
                    }
                }
                return

            case .interceptSwipePredictionConfirm:
                controllerService.playHaptic(
                    intensity: Config.keyboardActionHapticIntensity,
                    sharpness: Config.keyboardActionHapticSharpness,
                    duration: Config.keyboardActionHapticDuration,
                    transient: true
                )
                DispatchQueue.main.async {
                    if let word = SwipeTypingEngine.shared.confirmSelection() {
                        OnScreenKeyboardManager.shared.typeSwipedWord(word)
                    }
                }
                return

            case .interceptSwipePredictionCancel:
                state.lock.withLock {
                    state.swipeTypingActive = false
                    state.wasTouchpadTouching = false
                }
                SwipeTypingEngine.shared.deactivateMode()
                return

            case .unmapped:
                inputLogService?.log(buttons: [button], type: .singlePress, action: "(unmapped)")
                return

            case .mapping(let context):
                if context.shouldTreatAsHold {
                    handleHoldMapping(button, mapping: context.mapping, lastTap: context.lastTap, profile: profile)
                    return
                }

                if let longHold = context.mapping.longHoldMapping, !longHold.isEmpty {
                    setupLongHoldTimer(for: button, mapping: longHold)
                }

                if let repeatConfig = context.mapping.repeatMapping, repeatConfig.enabled {
                    startRepeatTimer(for: button, mapping: context.mapping, interval: repeatConfig.interval)
                }
            }
        }
    }

    /// Handles mapping that should be treated as continuously held
    nonisolated private func handleHoldMapping(_ button: ControllerButton, mapping: KeyMapping, lastTap: Date?, profile: Profile?) {
        if let doubleTapMapping = mapping.doubleTapMapping, !doubleTapMapping.isEmpty {
            let now = Date()
            if let lastTap = lastTap, now.timeIntervalSince(lastTap) <= doubleTapMapping.threshold {
                state.lock.withLock {
                    state.lastTapTime.removeValue(forKey: button)
                }
                mappingExecutor.executeAction(doubleTapMapping, for: button, profile: profile, logType: .doubleTap)
                return
            }
            state.lock.withLock {
                state.lastTapTime[button] = now
            }
        }

        state.lock.withLock {
            state.heldButtons[button] = mapping
        }

        inputSimulator.startHoldMapping(mapping)
        inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.feedbackString, isHeld: true)
    }

    /// Toggles the controller lock state
    nonisolated func performLockToggle() -> Bool {
        let keysToRelease: (left: Set<CGKeyCode>, right: Set<CGKeyCode>)?
        let nowLocked: Bool

        state.lock.lock()
        let wasLocked = state.isLocked
        state.isLocked = !wasLocked
        nowLocked = !wasLocked

        if nowLocked {
            let leftKeys = state.leftStickHeldKeys
            let rightKeys = state.rightStickHeldKeys

            state.heldButtons.removeAll()
            state.activeChordButtons.removeAll()

            state.pendingSingleTap.values.forEach { $0.cancel() }
            state.pendingSingleTap.removeAll()
            state.pendingReleaseActions.values.forEach { $0.cancel() }
            state.pendingReleaseActions.removeAll()
            state.longHoldTimers.values.forEach { $0.cancel() }
            state.longHoldTimers.removeAll()
            state.longHoldTriggered.removeAll()
            state.repeatTimers.values.forEach { $0.cancel() }
            state.repeatTimers.removeAll()
            state.dpadNavigationTimer?.cancel()
            state.dpadNavigationTimer = nil
            state.dpadNavigationButton = nil

            state.activeSequences.removeAll()

            state.smoothedLeftStick = .zero
            state.smoothedRightStick = .zero
            state.leftStickHeldKeys.removeAll()
            state.rightStickHeldKeys.removeAll()

            state.smoothedTouchpadDelta = .zero
            state.lastTouchpadSampleTime = 0
            state.touchpadResidualX = 0
            state.touchpadResidualY = 0
            state.touchpadMomentumVelocity = .zero
            state.touchpadMomentumWasActive = false

            state.onScreenKeyboardButton = nil
            state.onScreenKeyboardHoldMode = false
            state.laserPointerButton = nil
            state.laserPointerHoldMode = false
            state.directoryNavigatorButton = nil
            state.directoryNavigatorHoldMode = false
            state.commandWheelActive = false

            keysToRelease = (leftKeys, rightKeys)
        } else {
            keysToRelease = nil
        }
        state.lock.unlock()

        if nowLocked {
            inputSimulator.releaseAllModifiers()
            if let keysToRelease {
                for key in keysToRelease.left {
                    inputSimulator.keyUp(key)
                }
                for key in keysToRelease.right {
                    inputSimulator.keyUp(key)
                }
            }

            DispatchQueue.main.async {
                LaserPointerOverlay.shared.hide()
                OnScreenKeyboardManager.shared.hide()
                DirectoryNavigatorManager.shared.hide()
            }
        }

        if nowLocked {
            controllerService.playHaptic(
                intensity: Config.lockHapticIntensity1,
                sharpness: Config.lockHapticSharpness1,
                duration: Config.lockHapticDuration1
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.lockHapticDuration1 + Config.lockHapticGap) { [weak self] in
                self?.controllerService.playHaptic(
                    intensity: Config.lockHapticIntensity2,
                    sharpness: Config.lockHapticSharpness2,
                    duration: Config.lockHapticDuration2
                )
            }
        } else {
            controllerService.playHaptic(
                intensity: Config.unlockHapticIntensity,
                sharpness: Config.unlockHapticSharpness,
                duration: Config.unlockHapticDuration
            )
        }

        DispatchQueue.main.async { [weak self] in
            self?.isLocked = nowLocked
            ActionFeedbackIndicator.shared.show(
                action: nowLocked ? "Controller Locked" : "Controller Unlocked",
                type: .singlePress
            )
        }

        return nowLocked
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
        if let keyCode = mapping.keyCode {
            OnScreenKeyboardManager.shared.notifyControllerKeyPress(
                keyCode: keyCode, modifiers: mapping.modifiers.cgEventFlags
            )
        }
        inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.feedbackString)

        let timer = DispatchSource.makeTimerSource(queue: inputQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.inputSimulator.executeMapping(mapping)
            if let keyCode = mapping.keyCode {
                OnScreenKeyboardManager.shared.notifyControllerKeyPress(
                    keyCode: keyCode, modifiers: mapping.modifiers.cgEventFlags
                )
            }
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
        let profile = state.lock.withLock {
            state.longHoldTriggered.insert(button)
            return state.activeProfile
        }

        mappingExecutor.executeAction(mapping, for: button, profile: profile, logType: .longPress)
    }

    /// - Precondition: Must be called on inputQueue
    nonisolated private func handleButtonReleased(_ button: ControllerButton, holdDuration: TimeInterval) {
        dispatchPrecondition(condition: .onQueue(inputQueue))
        stopRepeatTimer(for: button)

        // Layer Activator Release
        let layerDeactivation = state.lock.withLock { () -> (didDeactivate: Bool, layerName: String?) in
            guard let layerId = state.layerActivatorMap[button] else {
                return (false, nil)
            }
            state.activeLayerIds.removeAll { $0 == layerId }
            #if DEBUG
            let layerName = state.activeProfile?
                .layers
                .first(where: { $0.id == layerId })?
                .name
            return (true, layerName)
            #else
            return (true, nil)
            #endif
        }
        if layerDeactivation.didDeactivate {
            #if DEBUG
            if let layerName = layerDeactivation.layerName {
                print("🔷 Layer deactivated: \(layerName)")
            }
            #endif
            return
        }

        handleOnScreenKeyboardReleased(button)
        handleLaserPointerReleased(button)
        handleDirectoryNavigatorReleased(button)

        let keyboardVisible = OnScreenKeyboardManager.shared.threadSafeIsVisible
        let directoryNavigatorVisible = DirectoryNavigatorManager.shared.threadSafeIsVisible
        if keyboardVisible || directoryNavigatorVisible {
            switch button {
            case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
                stopDpadNavigationRepeat(button)
                return
            default:
                break
            }
        }

        if let releaseResult = cleanupReleaseTimers(for: button) {
            if case .heldMapping(let heldMapping) = releaseResult {
                inputSimulator.stopHoldMapping(heldMapping)
                inputLogService?.dismissHeldFeedback(action: heldMapping.feedbackString)
            }
            return
        }

        guard let (mapping, profile, isLongHoldTriggered) = getReleaseContext(for: button) else { return }

        switch ButtonInteractionFlowPolicy.releaseDecision(
            mapping: mapping,
            holdDuration: holdDuration,
            isLongHoldTriggered: isLongHoldTriggered
        ) {
        case .skip:
            return

        case .executeLongHold(let longHoldMapping):
            clearTapState(for: button)
            mappingExecutor.executeAction(longHoldMapping, for: button, profile: profile, logType: .longPress)
            return

        case .evaluateDoubleTap(let doubleTapMapping, let skipSingleTapFallback):
            let (pendingSingle, lastTap) = getPendingTapInfo(for: button)
            _ = handleDoubleTapIfReady(
                button,
                mapping: mapping,
                pendingSingle: pendingSingle,
                lastTap: lastTap,
                doubleTapMapping: doubleTapMapping,
                skipSingleTap: skipSingleTapFallback,
                profile: profile
            )

        case .executeSingleTap:
            handleSingleTap(button, mapping: mapping, profile: profile)
        }
    }

    // MARK: - Release Handler Helpers

    enum ReleaseCleanupResult {
        case heldMapping(KeyMapping)
        case chordButton
    }

    nonisolated private func cleanupReleaseTimers(for button: ControllerButton) -> ReleaseCleanupResult? {
        state.lock.lock()
        defer { state.lock.unlock() }

        if let timer = state.longHoldTimers[button] {
            timer.cancel()
            state.longHoldTimers.removeValue(forKey: button)
        }

        guard state.isEnabled, state.activeProfile != nil else { return nil }

        if let heldMapping = state.heldButtons[button] {
            state.heldButtons.removeValue(forKey: button)
            state.activeChordButtons.remove(button)
            return .heldMapping(heldMapping)
        }

        if state.activeChordButtons.contains(button) {
            state.activeChordButtons.remove(button)
            return .chordButton
        }

        return nil
    }

    nonisolated private func getReleaseContext(for button: ControllerButton) -> (KeyMapping, Profile, Bool)? {
        guard let (profile, isLongHoldTriggered) = state.lock.withLock({ () -> (Profile, Bool)? in
            guard state.isEnabled, !state.isLocked, let profile = state.activeProfile else {
                return nil
            }

            let isLongHoldTriggered = state.longHoldTriggered.contains(button)
            if isLongHoldTriggered {
                state.longHoldTriggered.remove(button)
            }

            return (profile, isLongHoldTriggered)
        }) else {
            return nil
        }

        guard let mapping = effectiveMapping(for: button, in: profile) else { return nil }

        return (mapping, profile, isLongHoldTriggered)
    }

    /// Returns the effective mapping for a button, considering active layers.
    nonisolated func effectiveMapping(for button: ControllerButton, in profile: Profile) -> KeyMapping? {
        let (layerActivatorMap, activeLayerIds) = state.lock.withLock {
            (state.layerActivatorMap, state.activeLayerIds)
        }

        return ButtonMappingResolutionPolicy.resolve(
            button: button,
            profile: profile,
            activeLayerIds: activeLayerIds,
            layerActivatorMap: layerActivatorMap
        )
    }

    /// Get pending tap state for double-tap detection
    nonisolated func getPendingTapInfo(for button: ControllerButton) -> (DispatchWorkItem?, Date?) {
        state.lock.lock()
        defer { state.lock.unlock() }

        return (state.pendingSingleTap[button], state.lastTapTime[button])
    }

    /// Clear pending tap state
    nonisolated func clearTapState(for button: ControllerButton) {
        state.lock.withLock {
            state.pendingSingleTap[button]?.cancel()
            state.pendingSingleTap.removeValue(forKey: button)
            state.lastTapTime.removeValue(forKey: button)
        }
    }

    /// Handle double-tap detection - returns true if double-tap was executed
    nonisolated func handleDoubleTapIfReady(
        _ button: ControllerButton,
        mapping: KeyMapping,
        pendingSingle: DispatchWorkItem?,
        lastTap: Date?,
        doubleTapMapping: DoubleTapMapping,
        skipSingleTap: Bool = false,
        profile: Profile? = nil
    ) -> Bool {
        let now = Date()

        if let lastTap = lastTap,
           now.timeIntervalSince(lastTap) <= doubleTapMapping.threshold {

            if let pending = pendingSingle {
                pending.cancel()
            }
            clearTapState(for: button)
            mappingExecutor.executeAction(doubleTapMapping, for: button, profile: profile, logType: .doubleTap)
            return true
        }

        let workItem = state.lock.withLock { () -> DispatchWorkItem? in
            state.lastTapTime[button] = now

            if skipSingleTap {
                return nil
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.clearTapState(for: button)

                let profile = self.state.lock.withLock { self.state.activeProfile }
                self.mappingExecutor.executeAction(mapping, for: button, profile: profile)
            }
            state.pendingSingleTap[button] = workItem
            return workItem
        }

        if let workItem {
            inputQueue.asyncAfter(deadline: .now() + doubleTapMapping.threshold, execute: workItem)
        }
        return false
    }

    /// Handle single tap - either immediate or delayed if button is part of chord mapping
    nonisolated private func handleSingleTap(_ button: ControllerButton, mapping: KeyMapping, profile: Profile) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.state.lock.withLock {
                self.state.pendingReleaseActions.removeValue(forKey: button)
            }

            self.mappingExecutor.executeAction(mapping, for: button, profile: profile)
        }

        state.lock.withLock {
            state.pendingReleaseActions[button] = workItem
        }

        let isChordPart = isButtonUsedInChords(button, profile: profile)
        let delay = isChordPart ? Config.chordReleaseProcessingDelay : 0.0

        if delay > 0 {
            inputQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            inputQueue.async(execute: workItem)
        }
    }

    /// - Precondition: Must be called on inputQueue
    nonisolated private func handleChord(_ buttons: Set<ControllerButton>) {
        dispatchPrecondition(condition: .onQueue(inputQueue))
        guard let (profile, chordButtons) = state.lock.withLock({ () -> (Profile, Set<ControllerButton>)? in
            guard state.isEnabled, let profile = state.activeProfile else {
                return nil
            }

            var layerActivators: Set<ControllerButton> = []
            for button in buttons {
                if let layerId = state.layerActivatorMap[button] {
                    layerActivators.insert(button)
                    state.activeLayerIds.removeAll { $0 == layerId }
                    state.activeLayerIds.append(layerId)
                    #if DEBUG
                    if let layer = profile.layers.first(where: { $0.id == layerId }) {
                        print("🔷 Layer activated (via chord): \(layer.name)")
                    }
                    #endif
                }
            }

            let chordButtons = buttons.subtracting(layerActivators)

            for button in buttons {
                state.pendingReleaseActions[button]?.cancel()
                state.pendingReleaseActions.removeValue(forKey: button)

                state.pendingSingleTap[button]?.cancel()
                state.pendingSingleTap.removeValue(forKey: button)
                state.lastTapTime.removeValue(forKey: button)
            }

            return (profile, chordButtons)
        }) else {
            return
        }

        if chordButtons.isEmpty {
            return
        }

        if chordButtons.count == 1 {
            for button in chordButtons {
                handleButtonPressed(button)
            }
            return
        }

        let matchingChord = profile.chordMappings.first { chord in
            chord.buttons == chordButtons
        }

        if let chord = matchingChord {
            state.lock.withLock {
                state.activeChordButtons = chordButtons
            }

            if let keyCode = chord.keyCode {
                if keyCode == KeyCodeMapping.controllerLock {
                    _ = performLockToggle()
                    inputLogService?.log(buttons: Array(chordButtons), type: .chord, action: "Controller Lock")
                    return
                }

                if state.lock.withLock({ state.isLocked }) { return }

                if keyCode == KeyCodeMapping.showLaserPointer {
                    DispatchQueue.main.async { LaserPointerOverlay.shared.toggle() }
                    inputLogService?.log(buttons: Array(chordButtons), type: .chord, action: "Laser Pointer")
                    return
                }
                if keyCode == KeyCodeMapping.showOnScreenKeyboard {
                    DispatchQueue.main.async { OnScreenKeyboardManager.shared.toggle() }
                    inputLogService?.log(buttons: Array(chordButtons), type: .chord, action: "On-Screen Keyboard")
                    return
                }
                if keyCode == KeyCodeMapping.showDirectoryNavigator {
                    DispatchQueue.main.async { DirectoryNavigatorManager.shared.toggle() }
                    inputLogService?.log(buttons: Array(chordButtons), type: .chord, action: "Directory Navigator")
                    return
                }
            } else {
                if state.lock.withLock({ state.isLocked }) { return }
            }

            mappingExecutor.executeAction(chord, for: Array(chordButtons), profile: profile, logType: .chord)
        } else {
            if state.lock.withLock({ state.isLocked }) { return }

            let sortedButtons = chordButtons.sorted { $0.rawValue < $1.rawValue }
            for button in sortedButtons {
                handleButtonPressed(button)
            }
        }
    }

    // MARK: - Control

    func enable() {
        isEnabled = true
    }

    func disable() {
        isEnabled = false
        releaseAllDirectionKeys()
    }

    func toggle() {
        isEnabled.toggle()
    }
}
