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
                DispatchQueue.main.asyncAfter(deadline: .now() + Config.webhookFailureHapticGap + Config.webhookFailureHapticDuration) { [weak self] in
                    self?.controllerService.playHaptic(
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
	let oskSettings = profileManager.onScreenKeyboardSettings
	self.state.swipeTypingEnabled = oskSettings.swipeTypingEnabled
	self.state.swipeTypingSensitivity = oskSettings.swipeTypingSensitivity
        self.state.frontmostBundleId = appMonitor.frontmostBundleId
        self.state.sequenceDetector.configure(sequences: profileManager.activeProfile?.sequenceMappings ?? [])
        self.state.applyProfileIndex(MappingProfileIndex(profile: profileManager.activeProfile))
        syncLatencySettings(for: profileManager.activeProfile)
        syncGestureSettings(from: profileManager.activeProfile?.joystickSettings)
        syncTouchpadSettings(from: profileManager.activeProfile)
        syncMotionActivation(for: profileManager.activeProfile)
    }

    /// Tears down all subscriptions and timers. Must be called before dropping
    /// the last reference to avoid leaking Combine subscriptions.
    func tearDown() {
        cancellables.removeAll()
        joystickTimer?.cancel()
        joystickTimer = nil
    }

    private func syncLatencySettings(for profile: Profile?) {
		let chordButtons = MappingProfileIndex(profile: profile).chordParticipantButtons
        controllerService.chordParticipantButtons = chordButtons
        controllerService.lowLatencyInputEnabled = profile?.inputLatencyMode == .realtime
    }

    /// Pushes effective gesture detection settings from the profile into ControllerStorage
    /// so the motion callback thread can read them without accessing JoystickSettings.
    /// Also resets gesture detector tracking state to prevent stale gestures from a
    /// previous profile carrying over (e.g., a mid-tracking gesture completing after switch).
    /// Pushes touchpad-related ControllerStorage flags that affect callback policy.
    /// ControllerService doesn't otherwise know about JoystickSettings or Profile,
    /// so MappingEngine is responsible for keeping these in sync whenever the
    /// active profile changes.
    private func syncTouchpadSettings(from profile: Profile?) {
        let settings = profile?.joystickSettings ?? .default
        controllerService.requireActiveTouchForRegionClick = settings.requireActiveTouchForRegionClick
		controllerService.appleTVRemoteCircularScrollEnabled = settings.appleTVRemoteCircularScrollEnabled
        controllerService.touchpadInputMode = profile?.touchpadInputMode ?? .wholePad
    }

    private func syncTouchpadSettings(from settings: JoystickSettings?) {
        // Backwards-compat shim for callers that didn't switch to the
        // profile-based overload yet. Falls back to whole-pad mode since we
        // don't know the active profile here.
        let settings = settings ?? .default
        controllerService.requireActiveTouchForRegionClick = settings.requireActiveTouchForRegionClick
		controllerService.appleTVRemoteCircularScrollEnabled = settings.appleTVRemoteCircularScrollEnabled
    }

    private func syncGestureSettings(from settings: JoystickSettings?) {
        let settings = settings ?? .default
        controllerService.storage.lock.lock()
        controllerService.storage.motionGestureDetector.reset()
        controllerService.storage.motionGestureDetector.pitchActivationThreshold = settings.effectiveGestureActivationThreshold
        controllerService.storage.motionGestureDetector.pitchMinPeakVelocity = settings.effectiveGestureMinPeakVelocity
        controllerService.storage.motionGestureDetector.rollActivationThreshold = settings.effectiveGestureRollActivationThreshold
        controllerService.storage.motionGestureDetector.rollMinPeakVelocity = settings.effectiveGestureRollMinPeakVelocity
        controllerService.storage.motionGestureDetector.cooldown = settings.effectiveGestureCooldown
        controllerService.storage.motionGestureDetector.oppositeDirectionCooldown = settings.effectiveGestureOppositeDirectionCooldown
        controllerService.storage.lock.unlock()
    }

    private func syncMotionActivation(for profile: Profile?) {
        let shouldEnableMotion = ControllerMotionActivationPolicy.shouldEnableMotion(
            profile: profile,
            hasMotion: controllerService.threadSafeHasMotion
        )
        controllerService.setMotionSensorsActive(shouldEnableMotion)
    }

    /// Plays haptic feedback for a discrete controller action if the mapping has a haptic style configured.
    nonisolated func playActionHaptic(style: HapticStyle?) {
        guard let style else { return }
        controllerService.playHaptic(
            intensity: style.intensity,
            sharpness: style.sharpness,
            duration: style.duration,
            transient: true
        )
    }

    private func setupBindings() {
        // Sync Profile
        profileManager.$activeProfile
            .sink { [weak self] profile in
                guard let self = self else { return }
                let directionButtonsToRelease = self.state.lock.withLock { () -> Set<ControllerButton> in
                    let heldDirections = self.state.leftStickHeldDirectionButtons
                        .union(self.state.rightStickHeldDirectionButtons)
                    self.state.leftStickHeldDirectionButtons.removeAll()
                    self.state.rightStickHeldDirectionButtons.removeAll()
                    self.state.activeProfile = profile
                    self.state.joystickSettings = profile?.joystickSettings
		    let osk = self.profileManager.onScreenKeyboardSettings
		    self.state.swipeTypingEnabled = osk.swipeTypingEnabled
		    self.state.swipeTypingSensitivity = osk.swipeTypingSensitivity
                    self.state.activeLayerIds.removeAll()
                    self.state.buttonsActingAsLayerActivators.removeAll()
                    self.state.sequenceDetector.configure(sequences: profile?.sequenceMappings ?? [])
                    self.state.applyProfileIndex(MappingProfileIndex(profile: profile))
                    return heldDirections
                }
                for button in directionButtonsToRelease {
                    self.controllerService.handleButton(button, pressed: false)
                }
                self.syncGestureSettings(from: profile?.joystickSettings)
                self.syncTouchpadSettings(from: profile)
                self.syncMotionActivation(for: profile)
                self.syncLatencySettings(for: profile)
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

        // Controller input events — ControllerService owns event emission;
        // MappingEngine owns queue routing and mapping behavior.
        controllerService.onInputEvent = { [weak self] event in
            self?.enqueueControllerInputEvent(event)
        }

        // Joystick polling
        controllerService.$isConnected
            .sink { [weak self] connected in
                if connected {
                    self?.startJoystickPollingIfNeeded()
                    self?.syncMotionActivation(for: self?.profileManager.activeProfile)
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
                if self.controllerService.threadSafeIsPlayStation,
                   let ledSettings = self.profileManager.activeProfile?.dualSenseLEDSettings {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.controllerService.applyLEDSettings(ledSettings)
                        self?.controllerService.updateBatteryLightBar()
                    }
                }
            }
            .store(in: &cancellables)

        // Region clicks no longer use a callback. ControllerService dispatches
        // them directly as `handleButton(.touchpadRegion*Click, pressed:)`,
        // which goes through the standard press/release machinery (long hold,
        // double tap, repeat, layer overrides all work for free).

        // Enable/Disable toggle sync
        $isEnabled
            .sink { [weak self] enabled in
                guard let self = self else { return }
                let cleanup: (leftKeys: Set<CGKeyCode>, rightKeys: Set<CGKeyCode>, directionButtons: Set<ControllerButton>)? = self.state.lock.withLock {
                    self.state.isEnabled = enabled
                    if enabled {
                        let profile = self.state.activeProfile
                        self.state.sequenceDetector.configure(sequences: profile?.sequenceMappings ?? [])
                        self.state.applyProfileIndex(MappingProfileIndex(profile: profile))
                        self.syncLatencySettings(for: profile)
                        return nil
                    }
                    let leftKeys = self.state.leftStickHeldKeys
                    let rightKeys = self.state.rightStickHeldKeys
                    let directionButtons = self.state.leftStickHeldDirectionButtons
                        .union(self.state.rightStickHeldDirectionButtons)
                    self.state.reset()
                    return (leftKeys, rightKeys, directionButtons)
                }
                if let cleanup {
                    self.inputSimulator.releaseAllModifiers()
                    for key in cleanup.leftKeys {
                        self.inputSimulator.keyUp(key)
                    }
                    for key in cleanup.rightKeys {
                        self.inputSimulator.keyUp(key)
                    }
                    for button in cleanup.directionButtons {
                        self.controllerService.handleButton(button, pressed: false)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Button Handling (Background Queue)

    nonisolated private func isButtonUsedInChords(_ button: ControllerButton, profile: Profile) -> Bool {
        return state.lock.withLock { state.chordParticipantButtons.contains(button) }
    }

	nonisolated private func resolvedInputButton(for button: ControllerButton) -> ControllerButton {
		state.lock.withLock {
			guard let profile = state.activeProfile else { return button }
			return ButtonMappingResolutionPolicy.resolvedButton(
				button: button,
				profile: profile,
				activeLayerIds: state.activeLayerIds,
				layerActivatorMap: state.layerActivatorMap
			)
		}
	}

	nonisolated private func beginPhysicalButtonResolution(for button: ControllerButton) -> ControllerButton {
		let resolvedButton = resolvedInputButton(for: button)
		state.lock.withLock {
			state.physicalButtonResolutions[button] = resolvedButton
		}
		return resolvedButton
	}

	nonisolated private func peekResolvedReleaseButton(for button: ControllerButton) -> ControllerButton {
		state.lock.withLock {
			state.physicalButtonResolutions[button]
		} ?? resolvedInputButton(for: button)
	}

	nonisolated private func endPhysicalButtonResolution(for button: ControllerButton) -> ControllerButton {
		state.lock.withLock {
			state.physicalButtonResolutions.removeValue(forKey: button)
		} ?? resolvedInputButton(for: button)
	}

	nonisolated private func beginPhysicalButtonResolutions(for buttons: Set<ControllerButton>) -> Set<ControllerButton> {
		Set(buttons.map { beginPhysicalButtonResolution(for: $0) })
	}

    // MARK: - Special Action Intercepts

    /// Checks if a keyCode maps to a special action (controller lock, laser pointer, etc.)
    /// and executes it. Returns true if the action was intercepted (caller should return early).
    nonisolated private func handleSpecialActionIntercept(
        keyCode: CGKeyCode?,
        buttons: [ControllerButton],
        logType: InputEventType
    ) -> Bool {
        guard let keyCode = keyCode else { return false }

        if keyCode == KeyCodeMapping.controllerLock {
            _ = performLockToggle()
            inputLogService?.log(buttons: buttons, type: logType, action: "Controller Lock")
            return true
        }

        if state.lock.withLock({ state.isLocked }) { return true }

        if keyCode == KeyCodeMapping.showLaserPointer {
            if UniversalControlMouseRelay.shared.sendUIEvent("laserPress", button: buttons.first ?? .a) {
                return true
            }
            DispatchQueue.main.async { LaserPointerOverlay.shared.toggle() }
            inputLogService?.log(buttons: buttons, type: logType, action: "Laser Pointer")
            return true
        }
        if keyCode == KeyCodeMapping.showOnScreenKeyboard {
            if UniversalControlMouseRelay.shared.sendUIEvent("oskPress", button: buttons.first ?? .a) {
                return true
            }
            DispatchQueue.main.async { OnScreenKeyboardManager.shared.toggle() }
            inputLogService?.log(buttons: buttons, type: logType, action: "On-Screen Keyboard")
            return true
        }
        if keyCode == KeyCodeMapping.showDirectoryNavigator {
            if UniversalControlMouseRelay.shared.sendUIEvent("navPress", button: buttons.first ?? .a) {
                return true
            }
            DispatchQueue.main.async { DirectoryNavigatorManager.shared.toggle() }
            inputLogService?.log(buttons: buttons, type: logType, action: "Directory Navigator")
            return true
        }
        return false
    }

    // MARK: - Sequence Detection (Zero-Latency)

    nonisolated private func advanceSequenceTracking(_ button: ControllerButton) {
        let now = CFAbsoluteTimeGetCurrent()
        let chordWindow = controllerService.threadSafeChordWindow

        let (completedSequence, profile): (SequenceMapping?, Profile?) = state.lock.withLock {
            state.sequenceDetector.chordWindowTolerance = chordWindow
            let result = state.sequenceDetector.process(button, at: now)
            // Read profile atomically with the detector result to ensure
            // the completed sequence executes against the current profile.
            return (result, state.activeProfile)
        }

        if let sequence = completedSequence {
            if handleSpecialActionIntercept(keyCode: sequence.keyCode, buttons: sequence.steps, logType: .sequence) {
                return
            }
            if sequence.keyCode == nil, state.lock.withLock({ state.isLocked }) { return }
            mappingExecutor.executeAction(sequence, for: sequence.steps, profile: profile, logType: .sequence)
            playActionHaptic(style: sequence.hapticStyle)
        }
    }

    private enum ButtonPressStartState {
        case blocked
        case layerActivated(profile: Profile, layerId: UUID)
        case ready(profile: Profile, lastTap: CFAbsoluteTime?)
    }

    nonisolated private func beginButtonPress(_ button: ControllerButton) -> ButtonPressStartState {
        state.lock.withLock {
            guard state.isEnabled, let profile = state.activeProfile else {
                #if DEBUG
                if state.isEnabled && state.activeProfile == nil {
                    print("⚠️ MappingEngine: Button \(button) pressed but no active profile — input ignored")
                }
                #endif
                return .blocked
            }

            let lastTap = state.lastTapTime[button]
            if let layerId = state.layerActivatorMap[button] {
                // If a different layer is already active, don't activate this button's
                // layer. Instead, treat it as a regular button so it can use the active
                // layer's mapping or its base mapping. This frees up other layer activators
                // for remapping within the current layer.
                if let activeLayerId = state.activeLayerIds.last, activeLayerId != layerId {
                    return .ready(profile: profile, lastTap: lastTap)
                }

                state.activeLayerIds.removeAll { $0 == layerId }
                state.activeLayerIds.append(layerId)
                state.buttonsActingAsLayerActivators.insert(button)
                return .layerActivated(profile: profile, layerId: layerId)
            }

            return .ready(profile: profile, lastTap: lastTap)
        }
    }

    nonisolated private func resolveButtonPressOutcome(
        _ button: ControllerButton,
        profile: Profile,
        lastTap: CFAbsoluteTime?
    ) -> ButtonPressOrchestrationPolicy.Outcome {
        let remoteOverlayState = UniversalControlMouseRelay.shared.remoteOverlayState()
        let localKeyboardVisible = OnScreenKeyboardManager.shared.threadSafeIsVisible
        let localDirectoryNavigatorVisible = DirectoryNavigatorManager.shared.threadSafeIsVisible
        let keyboardVisible = localKeyboardVisible || remoteOverlayState.keyboardVisible
        let directoryNavigatorVisible = localDirectoryNavigatorVisible || remoteOverlayState.directoryNavigatorVisible
        let mapping = effectiveMapping(for: button, in: profile)
		let isDPadPresetDirection = profile.dpadPreset.primaryKeyCode(for: button) == mapping?.keyCode
		let isOtherLayerActivatorPress = state.lock.withLock { () -> Bool in
			guard let activatorLayerId = state.layerActivatorMap[button],
				  let activeLayerId = state.activeLayerIds.last else {
				return false
			}
			return activeLayerId != activatorLayerId
		}
        let navigationModeActive = keyboardVisible
            ? (localKeyboardVisible
                ? OnScreenKeyboardManager.shared.threadSafeNavigationModeActive
                : remoteOverlayState.keyboardNavigationModeActive)
            : false
        let isChordPart = mapping != nil ? isButtonUsedInChords(button, profile: profile) : false

        return ButtonPressOrchestrationPolicy.resolve(
            button: button,
            mapping: mapping,
            keyboardVisible: keyboardVisible,
            navigationModeActive: navigationModeActive,
            directoryNavigatorVisible: directoryNavigatorVisible,
            remoteSwipePredictionsVisible: remoteOverlayState.swipePredictionsVisible,
            isChordPart: isChordPart,
			isDPadPresetDirection: isDPadPresetDirection,
			isOtherLayerActivatorPress: isOtherLayerActivatorPress,
            lastTap: lastTap,
            inputLatencyMode: profile.inputLatencyMode
        )
    }

    /// - Precondition: Must be called on inputQueue
    nonisolated private func handleButtonPressed(_ button: ControllerButton) {
        dispatchPrecondition(condition: .onQueue(inputQueue))
        LatencyDiagnostics.mark("engine.press \(button.rawValue)")
		if UniversalControlMouseRelay.shared.shouldRouteControllerInputToRemote {
            _ = UniversalControlMouseRelay.shared.sendControllerButtonPressed(button)
            return
        }
		let button = beginPhysicalButtonResolution(for: button)

        // If a region mapping (or other special action) consumed this press,
        // skip normal handling. Don't remove yet — the release handler removes.
        let isConsumed = state.lock.withLock { state.pressConsumedByAction.contains(button) }
        if isConsumed { return }

        switch beginButtonPress(button) {
        case .blocked:
            return

        case .layerActivated(let profile, let layerId):
            // Check if this activator button is also mapped to controller lock in the base layer.
            // Controller lock must always take precedence over layer activation.
            if let baseMapping = profile.buttonMappings[button],
               baseMapping.keyCode == KeyCodeMapping.controllerLock {
                _ = performLockToggle()
                inputLogService?.log(buttons: [button], type: .singlePress, action: "Controller Lock")
                // Undo the layer activation that beginButtonPress() already performed
                state.lock.withLock {
                    state.activeLayerIds.removeAll { $0 == layerId }
                    state.buttonsActingAsLayerActivators.remove(button)
                }
                return
            }
            if let layer = profile.layers.first(where: { $0.id == layerId }) {
                #if DEBUG
                print("🔷 Layer activated: \(layer.name)")
                #endif
                inputLogService?.log(buttons: [button], type: .singlePress, action: "Layer: \(layer.name)")

                // Apply layer-specific LED settings if configured
                if let ledSettings = layer.dualSenseLEDSettings {
                    DispatchQueue.main.async { [weak self] in
                        self?.controllerService.applyLEDSettings(ledSettings)
                        // Layer LEDs default to batteryLightBar=false, so this just stops
                        // any battery blink/charging animation that might be running.
                        self?.controllerService.updateBatteryLightBar()
                    }
                }
            }
            return

        case .ready(let profile, let lastTap):
            if let heldDirectionChord = consumeHeldJoystickDirectionChord(for: button) {
                let chordButtons = heldDirectionChord.buttons.sorted { $0.rawValue < $1.rawValue }
                let chord = heldDirectionChord.mapping
                if handleSpecialActionIntercept(keyCode: chord.keyCode, buttons: chordButtons, logType: .chord) {
                    return
                }
                if chord.keyCode == nil, state.lock.withLock({ state.isLocked }) { return }

                mappingExecutor.executeAction(chord, for: chordButtons, profile: profile, logType: .chord)
                playActionHaptic(style: chord.hapticStyle)
                return
            }

            if !profile.sequenceMappings.isEmpty {
                advanceSequenceTracking(button)
            }

            let outcome = resolveButtonPressOutcome(button, profile: profile, lastTap: lastTap)

            if state.lock.withLock({ state.isLocked }) {
                if case .interceptControllerLock = outcome {
                    _ = performLockToggle()
                    return
                }
                // Allow unlock via double-tap or long-hold when those alternates resolve
                // to controller lock. Track the timestamp and on second tap within
                // threshold, toggle. Long-hold fires from the longHoldTimer scheduled below.
                if case .mapping(let context) = outcome {
                    let mapping = context.mapping
                    if let dt = mapping.doubleTapMapping, dt.keyCode == KeyCodeMapping.controllerLock {
                        let now = CFAbsoluteTimeGetCurrent()
                        let prevTap = state.lock.withLock { state.lastTapTime[button] }
                        if let prev = prevTap, now - prev <= dt.threshold {
                            state.lock.withLock {
                                state.lastTapTime.removeValue(forKey: button)
                                state.pressConsumedByAction.insert(button)
                            }
                            _ = performLockToggle()
                        } else {
                            state.lock.withLock {
                                state.lastTapTime[button] = now
                                state.pressConsumedByAction.insert(button)
                            }
                        }
                        return
                    }
                    if let lh = mapping.longHoldMapping, lh.keyCode == KeyCodeMapping.controllerLock {
                        state.lock.withLock { state.pressConsumedByAction.insert(button) }
                        setupLongHoldTimer(for: button, mapping: lh)
                        return
                    }
                }
                return
            }

            switch outcome {
            case .interceptDpadNavigation:
                if UniversalControlMouseRelay.shared.sendOnScreenKeyboardNavigation(button) {
                    startDpadNavigationRepeat(button)
                    return
                }
                Task { @MainActor in
                    OnScreenKeyboardManager.shared.handleDPadNavigation(button)
                }
                startDpadNavigationRepeat(button)
                return

            case .interceptKeyboardActivation:
                if UniversalControlMouseRelay.shared.sendOnScreenKeyboardActivate() {
                    return
                }
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

            case .interceptCommandWheel(let holdMode):
                handleCommandWheelPressed(button, holdMode: holdMode)
                return

            case .interceptDirectoryNavigation:
                if UniversalControlMouseRelay.shared.sendDirectoryNavigation(button) {
                    startDpadNavigationRepeat(button)
                    return
                }
                Task { @MainActor in
                    DirectoryNavigatorManager.shared.handleDPadNavigation(button)
                }
                startDpadNavigationRepeat(button)
                return

            case .interceptDirectoryConfirm:
                if UniversalControlMouseRelay.shared.sendDirectoryConfirm() {
                    return
                }
                DispatchQueue.main.async {
                    DirectoryNavigatorManager.shared.dismissAndCd()
                }
                return

            case .interceptDirectoryDismiss:
                if UniversalControlMouseRelay.shared.sendDirectoryDismiss() {
                    return
                }
                DispatchQueue.main.async {
                    DirectoryNavigatorManager.shared.hide()
                }
                return

            case .interceptSwipePredictionNavigation:
                if UniversalControlMouseRelay.shared.sendSwipePredictionNavigation(button) {
                    controllerService.playHaptic(
                        intensity: Config.keyboardActionHapticIntensity,
                        sharpness: Config.keyboardActionHapticSharpness,
                        duration: Config.keyboardActionHapticDuration,
                        transient: true
                    )
                    return
                }
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
                if UniversalControlMouseRelay.shared.sendSwipePredictionConfirm() {
                    controllerService.playHaptic(
                        intensity: Config.keyboardActionHapticIntensity,
                        sharpness: Config.keyboardActionHapticSharpness,
                        duration: Config.keyboardActionHapticDuration,
                        transient: true
                    )
                    return
                }
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
                if UniversalControlMouseRelay.shared.sendSwipePredictionCancel() {
                    state.lock.withLock {
                        state.swipeTypingActive = false
                        state.wasTouchpadTouching = false
                    }
                    return
                }
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
				if context.mapping.isSmoothScrollAction {
					if button.isJoystickDirection {
						state.lock.withLock {
							state.pressConsumedByAction.insert(button)
						}
						return
					}
					handleSmoothScrollMapping(button, mapping: context.mapping)
					return
				}

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

    private struct HeldJoystickDirectionChord {
        let mapping: ChordMapping
        let buttons: Set<ControllerButton>
    }

    /// Treat held virtual stick directions as chord modifiers. Stick direction
    /// buttons are generated while the stick stays deflected, so they often
    /// predate the physical button press by longer than the normal chord window.
    /// - Precondition: Must be called on inputQueue
    nonisolated private func consumeHeldJoystickDirectionChord(for button: ControllerButton) -> HeldJoystickDirectionChord? {
        dispatchPrecondition(condition: .onQueue(inputQueue))

        guard !button.isJoystickDirection else { return nil }

        return state.lock.withLock {
            let heldDirections = state.leftStickHeldDirectionButtons.union(state.rightStickHeldDirectionButtons)
            guard !heldDirections.isEmpty else { return nil }

            let chordButtons = heldDirections.union([button])
            guard let chord = state.chordLookup[chordButtons] else { return nil }

            for chordButton in chordButtons {
                state.pendingReleaseActions[chordButton]?.cancel()
                state.pendingReleaseActions.removeValue(forKey: chordButton)

                state.pendingSingleTap[chordButton]?.cancel()
                state.pendingSingleTap.removeValue(forKey: chordButton)
                state.lastTapTime.removeValue(forKey: chordButton)
            }

            state.activeChordButtons = chordButtons
            return HeldJoystickDirectionChord(mapping: chord, buttons: chordButtons)
        }
    }

    /// Handles mapping that should be treated as continuously held
    nonisolated private func handleHoldMapping(_ button: ControllerButton, mapping: KeyMapping, lastTap: CFAbsoluteTime?, profile: Profile?) {
        LatencyDiagnostics.mark("engine.holdStart \(button.rawValue) \(mapping.feedbackString)")
        if let doubleTapMapping = mapping.doubleTapMapping, !doubleTapMapping.isEmpty {
            let now = CFAbsoluteTimeGetCurrent()
            if let lastTap = lastTap, now - lastTap <= doubleTapMapping.threshold {
                state.lock.withLock {
                    state.lastTapTime.removeValue(forKey: button)
                }
                if handleSpecialActionIntercept(keyCode: doubleTapMapping.keyCode, buttons: [button], logType: .doubleTap) {
                    playActionHaptic(style: doubleTapMapping.hapticStyle)
                    return
                }
                mappingExecutor.executeAction(doubleTapMapping, for: button, profile: profile, logType: .doubleTap)
                playActionHaptic(style: doubleTapMapping.hapticStyle)
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

        if mapping.holdRepeatEnabled,
           let keyCode = mapping.keyCode,
           !KeyCodeMapping.isMouseButton(keyCode) {
            startHoldRepeatTimer(for: button, mapping: mapping)
        }

        playActionHaptic(style: mapping.hapticStyle)
        inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.feedbackString, isHeld: true)
    }

    /// Toggles the controller lock state
    nonisolated func performLockToggle() -> Bool {
        let cleanup: (leftKeys: Set<CGKeyCode>, rightKeys: Set<CGKeyCode>, directionButtons: Set<ControllerButton>)?
        let nowLocked: Bool

        state.lock.lock()
        let wasLocked = state.isLocked
        state.isLocked = !wasLocked
        nowLocked = !wasLocked

        if nowLocked {
            let leftKeys = state.leftStickHeldKeys
            let rightKeys = state.rightStickHeldKeys
            let directionButtons = state.leftStickHeldDirectionButtons.union(state.rightStickHeldDirectionButtons)

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
            state.holdRepeatTimers.values.forEach { $0.cancel() }
            state.holdRepeatTimers.removeAll()
			state.smoothScrollTimers.values.forEach { $0.cancel() }
			state.smoothScrollTimers.removeAll()
			state.smoothScrollMappings.removeAll()
            state.dpadNavigationTimer?.cancel()
            state.dpadNavigationTimer = nil
            state.dpadNavigationButton = nil

            state.sequenceDetector.reset()

            state.smoothedLeftStick = .zero
            state.smoothedRightStick = .zero
            state.leftStickHeldKeys.removeAll()
            state.rightStickHeldKeys.removeAll()
            state.leftStickHeldDirectionButtons.removeAll()
            state.rightStickHeldDirectionButtons.removeAll()

            state.smoothedTouchpadDelta = .zero
            state.lastTouchpadSampleTime = 0
            state.touchpadMomentumVelocity = .zero
            state.touchpadMomentumWasActive = false

            state.onScreenKeyboardButton = nil
            state.onScreenKeyboardHoldMode = false
            state.laserPointerButton = nil
            state.laserPointerHoldMode = false
            state.directoryNavigatorButton = nil
            state.directoryNavigatorHoldMode = false
            state.commandWheelActive = false

            cleanup = (leftKeys, rightKeys, directionButtons)
        } else {
            cleanup = nil
        }
        state.lock.unlock()

        if nowLocked {
            inputSimulator.releaseAllModifiers()
            if let cleanup {
                for key in cleanup.leftKeys {
                    inputSimulator.keyUp(key)
                }
                for key in cleanup.rightKeys {
                    inputSimulator.keyUp(key)
                }
                for button in cleanup.directionButtons {
                    controllerService.handleButton(button, pressed: false)
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

        // Lightbar feedback: solid red while locked, restore layer/profile color on unlock.
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  !self.controllerService.partyModeEnabled else { return }
            if nowLocked {
                var lockedSettings = DualSenseLEDSettings()
                lockedSettings.lightBarEnabled = true
                lockedSettings.lightBarColor = CodableColor(red: 1.0, green: 0.0, blue: 0.0)
                lockedSettings.batteryLightBar = false
                self.controllerService.applyLEDSettings(lockedSettings)
            } else {
                let (activeLayerIds, profile) = self.state.lock.withLock {
                    (self.state.activeLayerIds, self.state.activeProfile)
                }
                if let activeLayerId = activeLayerIds.last,
                   let activeLayer = profile?.layers.first(where: { $0.id == activeLayerId }),
                   let layerLED = activeLayer.dualSenseLEDSettings {
                    self.controllerService.applyLEDSettings(layerLED)
                } else if let profileLED = profile?.dualSenseLEDSettings {
                    self.controllerService.applyLEDSettings(profileLED)
                }
                self.controllerService.updateBatteryLightBar()
            }
        }

        return nowLocked
    }

    nonisolated func handleLongHoldTriggered(_ button: ControllerButton, mapping: LongHoldMapping) {
        let profile = state.lock.withLock {
            state.longHoldTriggered.insert(button)
            return state.activeProfile
        }

        // Route special action keycodes (controller lock, laser pointer, etc.) through
        // the intercept path. Otherwise the bogus keycode would be sent as a real keypress.
        if handleSpecialActionIntercept(keyCode: mapping.keyCode, buttons: [button], logType: .longPress) {
            playActionHaptic(style: mapping.hapticStyle)
            return
        }

        mappingExecutor.executeAction(mapping, for: button, profile: profile, logType: .longPress)
        playActionHaptic(style: mapping.hapticStyle)
    }

    /// - Precondition: Must be called on inputQueue
    nonisolated private func handleButtonReleased(_ button: ControllerButton, holdDuration: TimeInterval) {
        dispatchPrecondition(condition: .onQueue(inputQueue))
        LatencyDiagnostics.mark("engine.release \(button.rawValue)")
		let resolvedButtonForState = peekResolvedReleaseButton(for: button)
		if UniversalControlMouseRelay.shared.shouldRouteControllerInputToRemote {
			let hasLocalButtonState = state.lock.withLock {
					state.heldButtons[resolvedButtonForState] != nil
						|| state.pendingSingleTap[resolvedButtonForState] != nil
						|| state.pendingReleaseActions[resolvedButtonForState] != nil
						|| state.longHoldTimers[resolvedButtonForState] != nil
						|| state.repeatTimers[resolvedButtonForState] != nil
						|| state.holdRepeatTimers[resolvedButtonForState] != nil
						|| state.smoothScrollMappings[resolvedButtonForState] != nil
						|| state.smoothScrollTimers[resolvedButtonForState] != nil
						|| state.buttonsActingAsLayerActivators.contains(resolvedButtonForState)
						|| state.pressConsumedByAction.contains(resolvedButtonForState)
				}
            if !hasLocalButtonState {
                _ = UniversalControlMouseRelay.shared.sendControllerButtonReleased(button, holdDuration: holdDuration)
                return
            }
        }
		let button = endPhysicalButtonResolution(for: button)

        stopRepeatTimer(for: button)

        // If the press was consumed by a special action (e.g., double-tap unlock),
        // skip all release handling so the regular single-tap doesn't fire.
        // Don't clear lastTapTime here — double-tap detection needs that timestamp
        // to survive across presses.
        let consumed = state.lock.withLock { () -> Bool in
            if state.pressConsumedByAction.remove(button) != nil {
                if let timer = state.longHoldTimers.removeValue(forKey: button) { timer.cancel() }
                return true
            }
            return false
        }
        if consumed { return }

        // Layer Activator Release — only deactivate if this button actually activated a layer
        // (it might have been remapped as a regular button within another active layer)
        let layerDeactivation = state.lock.withLock { () -> (didDeactivate: Bool, layerName: String?) in
            guard let layerId = state.layerActivatorMap[button],
                  state.buttonsActingAsLayerActivators.contains(button) else {
                return (false, nil)
            }
            state.activeLayerIds.removeAll { $0 == layerId }
            state.buttonsActingAsLayerActivators.remove(button)
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

            // Revert LED settings: apply next active layer's LED, or fall back to profile default.
            // After applying, also kick the battery monitor so battery-light-bar mode resumes
            // if the profile uses it (otherwise its periodic updates would override our color).
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      !self.controllerService.partyModeEnabled else { return }
                let (remainingLayerIds, profile) = self.state.lock.withLock {
                    (self.state.activeLayerIds, self.state.activeProfile)
                }
                if let activeLayerId = remainingLayerIds.last,
                   let activeLayer = profile?.layers.first(where: { $0.id == activeLayerId }),
                   let ledSettings = activeLayer.dualSenseLEDSettings {
                    self.controllerService.applyLEDSettings(ledSettings)
                } else if let profileLED = profile?.dualSenseLEDSettings {
                    self.controllerService.applyLEDSettings(profileLED)
                }
                self.controllerService.updateBatteryLightBar()
            }
            return
        }

        handleOnScreenKeyboardReleased(button)
        handleLaserPointerReleased(button)
        handleDirectoryNavigatorReleased(button)
        handleCommandWheelReleased(button)

		if state.lock.withLock({ state.smoothScrollMappings[button] != nil }),
		   let releaseResult = cleanupReleaseTimers(for: button) {
			if case .smoothScrollMapping(let scrollMapping) = releaseResult {
				inputLogService?.dismissHeldFeedback(action: scrollMapping.feedbackString)
			}
			return
		}

        let remoteOverlayState = UniversalControlMouseRelay.shared.remoteOverlayState()
        let keyboardVisible = OnScreenKeyboardManager.shared.threadSafeIsVisible
            || remoteOverlayState.keyboardVisible
        let directoryNavigatorVisible = DirectoryNavigatorManager.shared.threadSafeIsVisible
            || remoteOverlayState.directoryNavigatorVisible
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
			switch releaseResult {
			case .heldMapping(let heldMapping):
                inputSimulator.stopHoldMapping(heldMapping)
                inputLogService?.dismissHeldFeedback(action: heldMapping.feedbackString)
			case .smoothScrollMapping(let scrollMapping):
				inputLogService?.dismissHeldFeedback(action: scrollMapping.feedbackString)
			case .chordButton:
				break
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
            playActionHaptic(style: longHoldMapping.hapticStyle)
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
		case smoothScrollMapping(KeyMapping)
        case chordButton
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
    nonisolated func getPendingTapInfo(for button: ControllerButton) -> (DispatchWorkItem?, CFAbsoluteTime?) {
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
        lastTap: CFAbsoluteTime?,
        doubleTapMapping: DoubleTapMapping,
        skipSingleTap: Bool = false,
        profile: Profile? = nil
    ) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()

        if let lastTap = lastTap,
           now - lastTap <= doubleTapMapping.threshold {

            if let pending = pendingSingle {
                pending.cancel()
            }
            clearTapState(for: button)
            if handleSpecialActionIntercept(keyCode: doubleTapMapping.keyCode, buttons: [button], logType: .doubleTap) {
                playActionHaptic(style: doubleTapMapping.hapticStyle)
                return true
            }
            mappingExecutor.executeAction(doubleTapMapping, for: button, profile: profile, logType: .doubleTap)
            playActionHaptic(style: doubleTapMapping.hapticStyle)
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
                self.playActionHaptic(style: mapping.hapticStyle)
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

            LatencyDiagnostics.mark("engine.singleTap \(button.rawValue) \(mapping.feedbackString)")
            self.mappingExecutor.executeAction(mapping, for: button, profile: profile)
            self.playActionHaptic(style: mapping.hapticStyle)
        }

        state.lock.withLock {
            state.pendingReleaseActions[button] = workItem
        }

        let isChordPart = isButtonUsedInChords(button, profile: profile)
        let delay = isChordPart ? Config.chordReleaseProcessingDelay : 0.0

        if delay > 0 {
            inputQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            workItem.perform()
        }
    }

    /// - Precondition: Must be called on inputQueue
    nonisolated private func handleChord(_ buttons: Set<ControllerButton>) {
        dispatchPrecondition(condition: .onQueue(inputQueue))
		if UniversalControlMouseRelay.shared.shouldRouteControllerInputToRemote {
            _ = UniversalControlMouseRelay.shared.sendControllerChord(buttons)
            return
        }
		let buttons = beginPhysicalButtonResolutions(for: buttons)

        guard let (profile, chordButtons) = state.lock.withLock({ () -> (Profile, Set<ControllerButton>)? in
            guard state.isEnabled, let profile = state.activeProfile else {
                #if DEBUG
                if state.isEnabled && state.activeProfile == nil {
                    print("⚠️ MappingEngine: Chord \(buttons) detected but no active profile — input ignored")
                }
                #endif
                return nil
            }

            var layerActivators: Set<ControllerButton> = []
            for button in buttons {
                if let layerId = state.layerActivatorMap[button] {
                    // Same logic as beginButtonPress: if a different layer is already active,
                    // don't activate this button's layer — free it up for remapping.
                    if let activeLayerId = state.activeLayerIds.last, activeLayerId != layerId {
                        continue  // Skip — treat as regular button in the chord
                    }
                    layerActivators.insert(button)
                    state.activeLayerIds.removeAll { $0 == layerId }
                    state.activeLayerIds.append(layerId)
                    state.buttonsActingAsLayerActivators.insert(button)
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

				if let timer = state.smoothScrollTimers.removeValue(forKey: button) {
					timer.cancel()
				}
				state.smoothScrollMappings.removeValue(forKey: button)
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

        // Try the captured set as-is first; if no chord matches, fall back to
        // an alias-substituted lookup so chords authored with `.touchpadButton`
        // continue to match when quadrants mode dispatches `.touchpadRegion*Click`
        // (and similarly for `.touchpadTap` ↔ `.touchpadRegion*Touch`).
        let matchingChord = state.lock.withLock { () -> ChordMapping? in
            if let direct = state.chordLookup[chordButtons] {
                return direct
            }
            let aliased = Set(chordButtons.map { $0.chordSequenceAlias ?? $0 })
            if aliased != chordButtons, let viaAlias = state.chordLookup[aliased] {
                return viaAlias
            }
            return nil
        }

        if let chord = matchingChord {
            state.lock.withLock {
                state.activeChordButtons = chordButtons
            }

            if handleSpecialActionIntercept(keyCode: chord.keyCode, buttons: Array(chordButtons), logType: .chord) {
                return
            }
            if chord.keyCode == nil, state.lock.withLock({ state.isLocked }) { return }

            mappingExecutor.executeAction(chord, for: Array(chordButtons), profile: profile, logType: .chord)
            playActionHaptic(style: chord.hapticStyle)
        } else {
            if state.lock.withLock({ state.isLocked }) { return }

            let sortedButtons = chordButtons.sorted { $0.rawValue < $1.rawValue }
            for button in sortedButtons {
                handleButtonPressed(button)
            }
        }
    }

	nonisolated private func enqueueControllerInputEvent(_ event: ControllerInputEvent) {
		switch ControllerInputEventRouting.queue(for: event) {
		case .input:
			inputQueue.async { [weak self] in
				self?.handleControllerInputEvent(event)
			}
		case .polling:
			pollingQueue.async { [weak self] in
				self?.handleControllerInputEvent(event)
			}
		}
	}

	nonisolated private func handleControllerInputEvent(_ event: ControllerInputEvent) {
		switch event {
		case .buttonPressed(let button):
			handleButtonPressed(button)
		case .buttonReleased(let button, let holdDuration):
			handleButtonReleased(button, holdDuration: holdDuration)
		case .chordDetected(let buttons):
			handleChord(buttons)
		case .touchpadMoved(let delta):
			processTouchpadMovement(delta)
		case .steamLeftTouchpadMoved(let delta):
			processSteamLeftTouchpadScroll(delta)
		case .appleTVRemoteCircularScroll(let angleDelta):
			processAppleTVRemoteCircularScroll(angleDelta)
		case .touchpadGesture(let gesture):
			processTouchpadGesture(gesture)
		case .touchpadTap:
			processTouchpadTap()
		case .controllerButtonTap(let button):
			processTapGesture(button)
		case .touchpadTwoFingerTap:
			processTouchpadTwoFingerTap()
		case .touchpadLongTap:
			processTouchpadLongTap()
		case .touchpadTwoFingerLongTap:
			processTouchpadTwoFingerLongTap()
		case .touchpadRegionTap(let region):
			processTouchpadRegionEvent(region, trigger: .touch)
		case .motionGesture(let gestureType):
			processMotionGesture(gestureType)
		}
	}

    // MARK: - Control

    func enable() {
        isEnabled = true
    }

    func disable() {
        releaseAllDirectionKeys()
        isEnabled = false
    }

    func toggle() {
        isEnabled.toggle()
    }

    // MARK: - Remote Controller Relay

    nonisolated func handleRemoteControllerButtonPressed(_ button: ControllerButton) {
		enqueueControllerInputEvent(.buttonPressed(button))
    }

    nonisolated func handleRemoteControllerButtonReleased(_ button: ControllerButton, holdDuration: TimeInterval) {
		enqueueControllerInputEvent(.buttonReleased(button, holdDuration: holdDuration))
    }

    nonisolated func handleRemoteControllerChord(_ buttons: Set<ControllerButton>) {
		enqueueControllerInputEvent(.chordDetected(buttons))
    }

    nonisolated func resetRemoteControllerInputState() {
        let cleanup = state.lock.withLock { () -> (heldMappings: [KeyMapping], leftKeys: Set<CGKeyCode>, rightKeys: Set<CGKeyCode>, directionButtons: Set<ControllerButton>) in
            let heldMappings = Array(state.heldButtons.values)
            let leftKeys = state.leftStickHeldKeys
            let rightKeys = state.rightStickHeldKeys
            let directionButtons = state.leftStickHeldDirectionButtons.union(state.rightStickHeldDirectionButtons)
            state.resetTransientInputState()
            return (heldMappings, leftKeys, rightKeys, directionButtons)
        }

        for mapping in cleanup.heldMappings {
            inputSimulator.stopHoldMapping(mapping)
        }
        for key in cleanup.leftKeys {
            inputSimulator.keyUp(key)
        }
        for key in cleanup.rightKeys {
            inputSimulator.keyUp(key)
        }
        for button in cleanup.directionButtons {
            controllerService.handleButton(button, pressed: false)
        }
        inputSimulator.releaseAllModifiers()
    }
}
