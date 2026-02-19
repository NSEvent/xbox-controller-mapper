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

@MainActor
class MappingEngine: ObservableObject {
    @Published var isEnabled = true

    private let controllerService: ControllerService
    private let profileManager: ProfileManager
    private let appMonitor: AppMonitor
    nonisolated private let inputSimulator: InputSimulatorProtocol
    private let inputLogService: InputLogService?
    nonisolated private let usageStatsService: UsageStatsService?
    nonisolated private let mappingExecutor: MappingExecutor

    // MARK: - Thread-Safe State
    
    private let inputQueue = DispatchQueue(label: "com.xboxmapper.input", qos: .userInteractive)
    private let pollingQueue = DispatchQueue(label: "com.xboxmapper.polling", qos: .userInteractive)

    private let state = EngineState()
    
    // Joystick polling
    private var joystickTimer: DispatchSourceTimer?

    private var cancellables = Set<AnyCancellable>()

    init(controllerService: ControllerService, profileManager: ProfileManager, appMonitor: AppMonitor, inputSimulator: InputSimulatorProtocol = InputSimulator(), inputLogService: InputLogService? = nil, usageStatsService: UsageStatsService? = nil) {
        self.controllerService = controllerService
        self.profileManager = profileManager
        self.appMonitor = appMonitor
        self.inputSimulator = inputSimulator
        self.inputLogService = inputLogService
        self.usageStatsService = usageStatsService
        self.mappingExecutor = MappingExecutor(inputSimulator: inputSimulator, inputQueue: inputQueue, inputLogService: inputLogService, profileManager: profileManager, usageStatsService: usageStatsService)

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

            // Play haptic feedback
            if success {
                self.controllerService.playHaptic(
                    intensity: Config.webhookSuccessHapticIntensity,
                    sharpness: Config.webhookSuccessHapticSharpness,
                    duration: Config.webhookSuccessHapticDuration,
                    transient: true
                )
            } else {
                // Double-pulse for failure
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

            // Show visual feedback overlay
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
        self.state.frontmostBundleId = appMonitor.frontmostBundleId
        rebuildLayerActivatorMap(profile: profileManager.activeProfile)
    }

    /// Rebuilds the layer activator button -> layer ID lookup map
    /// Must be called with state.lock held or during init
    private func rebuildLayerActivatorMap(profile: Profile?) {
        state.layerActivatorMap.removeAll()
        guard let profile = profile else { return }
        for layer in profile.layers {
            // Only include layers that have an activator button assigned
            if let activatorButton = layer.activatorButton {
                state.layerActivatorMap[activatorButton] = layer.id
            }
        }
    }
    
    private func setupBindings() {
        // Sync Profile
        profileManager.$activeProfile
            .sink { [weak self] profile in
                guard let self = self else { return }
                self.state.lock.withLock {
                    self.state.activeProfile = profile
                    self.state.joystickSettings = profile?.joystickSettings
                    // Clear active layers when profile changes - prevents stale layer state
                    // if user was holding a layer activator during profile switch
                    self.state.activeLayerIds.removeAll()
                    self.rebuildLayerActivatorMap(profile: profile)
                }
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
                let keysToRelease: (left: Set<CGKeyCode>, right: Set<CGKeyCode>)? = self.state.lock.withLock {
                    self.state.isEnabled = enabled
                    guard !enabled else { return nil }
                    // Capture direction keys before reset clears them
                    let leftKeys = self.state.leftStickHeldKeys
                    let rightKeys = self.state.rightStickHeldKeys
                    self.state.reset()
                    return (leftKeys, rightKeys)
                }
                // Release modifiers and direction keys after lock is released
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

    // MARK: - Button Handling (Background Queue)

    nonisolated private func isButtonUsedInChords(_ button: ControllerButton, profile: Profile) -> Bool {
        return profile.chordMappings.contains { chord in
            chord.buttons.contains(button)
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
                // Remove if already present, then append (most recent = last in array)
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
        let mapping = effectiveMapping(for: button, in: profile)
        let navigationModeActive = keyboardVisible ? OnScreenKeyboardManager.shared.threadSafeNavigationModeActive : false
        let isChordPart = mapping != nil ? isButtonUsedInChords(button, profile: profile) : false

        return ButtonPressOrchestrationPolicy.resolve(
            button: button,
            mapping: mapping,
            keyboardVisible: keyboardVisible,
            navigationModeActive: navigationModeActive,
            isChordPart: isChordPart,
            lastTap: lastTap
        )
    }

    nonisolated private func handleButtonPressed(_ button: ControllerButton) {
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
            switch resolveButtonPressOutcome(button, profile: profile, lastTap: lastTap) {
            case .interceptDpadNavigation:
                // First navigation happens immediately
                Task { @MainActor in
                    OnScreenKeyboardManager.shared.handleDPadNavigation(button)
                }
                // Start repeat timer for held D-pad
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

            case .unmapped:
                // Log unmapped button presses so they still appear in history
                inputLogService?.log(buttons: [button], type: .singlePress, action: "(unmapped)")
                return

            case .mapping(let context):
                if context.shouldTreatAsHold {
                    handleHoldMapping(button, mapping: context.mapping, lastTap: context.lastTap, profile: profile)
                    return
                }

                // Set up long-hold timer if applicable
                if let longHold = context.mapping.longHoldMapping, !longHold.isEmpty {
                    setupLongHoldTimer(for: button, mapping: longHold)
                }

                // Set up repeat if applicable
                if let repeatConfig = context.mapping.repeatMapping, repeatConfig.enabled {
                    startRepeatTimer(for: button, mapping: context.mapping, interval: repeatConfig.interval)
                }
            }
        }
    }

    /// Handles mapping that should be treated as continuously held
    nonisolated private func handleHoldMapping(_ button: ControllerButton, mapping: KeyMapping, lastTap: Date?, profile: Profile?) {
        // Check for double-tap
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

        // Start holding the mapping
        state.lock.withLock {
            state.heldButtons[button] = mapping
        }

        inputSimulator.startHoldMapping(mapping)
        inputLogService?.log(buttons: [button], type: .singlePress, action: mapping.feedbackString, isHeld: true)
    }

    /// Handles on-screen keyboard button press
    /// - holdMode: If true, shows keyboard while held. If false, toggles keyboard on/off.
    nonisolated private func handleOnScreenKeyboardPressed(_ button: ControllerButton, holdMode: Bool) {
        state.lock.withLock {
            state.onScreenKeyboardButton = button
            state.onScreenKeyboardHoldMode = holdMode
            if holdMode {
                state.commandWheelActive = true
            }
        }

        DispatchQueue.main.async { [weak self] in
            if holdMode {
                // Hold mode: always show on press
                OnScreenKeyboardManager.shared.show()
                self?.controllerService.playHaptic(
                    intensity: Config.keyboardShowHapticIntensity,
                    sharpness: Config.keyboardShowHapticSharpness,
                    duration: Config.keyboardShowHapticDuration,
                    transient: true
                )
                // Prepare command wheel with both apps and websites (shows on stick movement)
                let settings = self?.profileManager.onScreenKeyboardSettings
                let apps = settings?.appBarItems ?? []
                let websites = settings?.websiteLinks ?? []
                let showWebsitesFirst = settings?.wheelShowsWebsites == true
                // Store alternate modifiers in state for 120Hz checking
                if let self = self {
                    self.state.lock.withLock {
                        self.state.wheelAlternateModifiers = settings?.wheelAlternateModifiers ?? ModifierFlags()
                    }
                }
                if !apps.isEmpty || !websites.isEmpty {
                    CommandWheelManager.shared.prepare(apps: apps, websites: websites, showWebsitesFirst: showWebsitesFirst)
                    CommandWheelManager.shared.onSegmentChanged = { [weak self] in
                        self?.controllerService.playHaptic(
                            intensity: Config.wheelSegmentHapticIntensity,
                            sharpness: Config.wheelSegmentHapticSharpness,
                            transient: true
                        )
                    }
                    CommandWheelManager.shared.onPerimeterCrossed = { [weak self] in
                        self?.controllerService.playHaptic(
                            intensity: Config.wheelPerimeterHapticIntensity,
                            sharpness: Config.wheelPerimeterHapticSharpness,
                            transient: true
                        )
                    }
                    CommandWheelManager.shared.onForceQuitReady = { [weak self] in
                        // Double-tap: two quick pulses for destructive action confirmation
                        self?.controllerService.playHaptic(
                            intensity: Config.wheelForceQuitHapticIntensity,
                            sharpness: Config.wheelForceQuitHapticSharpness,
                            transient: true
                        )
                        DispatchQueue.main.asyncAfter(deadline: .now() + Config.wheelForceQuitHapticGap) {
                            self?.controllerService.playHaptic(
                                intensity: Config.wheelForceQuitHapticIntensity,
                                sharpness: Config.wheelForceQuitHapticSharpness,
                                transient: true
                            )
                        }
                    }
                    CommandWheelManager.shared.onSelectionActivated = { [weak self] isSecondary in
                        let intensity = isSecondary ? Config.wheelSecondaryHapticIntensity : Config.wheelActivateHapticIntensity
                        let sharpness = isSecondary ? Config.wheelSecondaryHapticSharpness : Config.wheelActivateHapticSharpness
                        let duration = isSecondary ? Config.wheelSecondaryHapticDuration : Config.wheelActivateHapticDuration
                        self?.controllerService.playHaptic(
                            intensity: intensity,
                            sharpness: sharpness,
                            duration: duration,
                            transient: true
                        )
                    }
                    CommandWheelManager.shared.onItemSetChanged = { [weak self] isAlternate in
                        let intensity = isAlternate ? Config.wheelSetEnterHapticIntensity : Config.wheelSetExitHapticIntensity
                        let sharpness = isAlternate ? Config.wheelSetEnterHapticSharpness : Config.wheelSetExitHapticSharpness
                        let duration = isAlternate ? Config.wheelSetEnterHapticDuration : Config.wheelSetExitHapticDuration
                        self?.controllerService.playHaptic(
                            intensity: intensity,
                            sharpness: sharpness,
                            duration: duration,
                            transient: true
                        )
                    }
                }
            } else {
                // Toggle mode: toggle visibility on press
                let wasVisible = OnScreenKeyboardManager.shared.isVisible
                OnScreenKeyboardManager.shared.toggle()
                let isVisible = OnScreenKeyboardManager.shared.isVisible
                if isVisible != wasVisible {
                    let intensity = isVisible ? Config.keyboardShowHapticIntensity : Config.keyboardHideHapticIntensity
                    let sharpness = isVisible ? Config.keyboardShowHapticSharpness : Config.keyboardHideHapticSharpness
                    let duration = isVisible ? Config.keyboardShowHapticDuration : Config.keyboardHideHapticDuration
                    self?.controllerService.playHaptic(
                        intensity: intensity,
                        sharpness: sharpness,
                        duration: duration,
                        transient: true
                    )
                }
            }
        }
        inputLogService?.log(buttons: [button], type: .singlePress, action: "On-Screen Keyboard")
    }

    /// Handles on-screen keyboard button release (hides keyboard only in hold mode)
    nonisolated private func handleOnScreenKeyboardReleased(_ button: ControllerButton) {
        let (wasKeyboardButton, wasHoldMode) = state.lock.withLock {
            let wasKeyboardButton = state.onScreenKeyboardButton == button
            let wasHoldMode = state.onScreenKeyboardHoldMode
            if wasKeyboardButton {
                state.onScreenKeyboardButton = nil
                state.commandWheelActive = false
            }
            return (wasKeyboardButton, wasHoldMode)
        }

        // Only hide on release if in hold mode
        if wasKeyboardButton && wasHoldMode {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                CommandWheelManager.shared.activateSelection()
                CommandWheelManager.shared.hide()
                OnScreenKeyboardManager.shared.hide()
                self.controllerService.playHaptic(
                    intensity: Config.keyboardHideHapticIntensity,
                    sharpness: Config.keyboardHideHapticSharpness,
                    duration: Config.keyboardHideHapticDuration,
                    transient: true
                )
            }
        }
    }

    /// Handles laser pointer button press
    nonisolated private func handleLaserPointerPressed(_ button: ControllerButton, holdMode: Bool) {
        state.lock.withLock {
            state.laserPointerButton = button
            state.laserPointerHoldMode = holdMode
        }

        DispatchQueue.main.async {
            if holdMode {
                LaserPointerOverlay.shared.show()
            } else {
                LaserPointerOverlay.shared.toggle()
            }
        }
        inputLogService?.log(buttons: [button], type: .singlePress, action: "Laser Pointer")
    }

    /// Handles laser pointer button release (hides laser only in hold mode)
    nonisolated private func handleLaserPointerReleased(_ button: ControllerButton) {
        let (wasLaserButton, wasHoldMode) = state.lock.withLock {
            let wasLaserButton = state.laserPointerButton == button
            let wasHoldMode = state.laserPointerHoldMode
            if wasLaserButton {
                state.laserPointerButton = nil
            }
            return (wasLaserButton, wasHoldMode)
        }

        if wasLaserButton && wasHoldMode {
            DispatchQueue.main.async {
                LaserPointerOverlay.shared.hide()
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
            // Check if button is still held (by checking active buttons from controller service?
            // ControllerService is MainActor. Accessing activeButtons is tricky.
            // Better to rely on state.heldButtons or just stop timer on release.)
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

    // MARK: - D-Pad Navigation Repeat

    /// Initial delay before repeat starts (similar to keyboard repeat delay)
    private static let dpadRepeatInitialDelay: TimeInterval = 0.4
    /// Interval between repeats once started
    private static let dpadRepeatInterval: TimeInterval = 0.08

    nonisolated private func startDpadNavigationRepeat(_ button: ControllerButton) {
        let timer = DispatchSource.makeTimerSource(queue: inputQueue)
        // Initial delay before repeat starts, then repeat at interval
        timer.schedule(
            deadline: .now() + Self.dpadRepeatInitialDelay,
            repeating: Self.dpadRepeatInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Check if keyboard is still visible
            guard OnScreenKeyboardManager.shared.threadSafeIsVisible else {
                self.stopDpadNavigationRepeat(button)
                return
            }
            // Use Task for MainActor context
            Task { @MainActor in
                OnScreenKeyboardManager.shared.handleDPadNavigation(button)
            }
        }
        state.lock.withLock {
            // Cancel any existing timer
            state.dpadNavigationTimer?.cancel()
            state.dpadNavigationButton = button
            state.dpadNavigationTimer = timer
        }
        timer.resume()
    }

    nonisolated private func stopDpadNavigationRepeat(_ button: ControllerButton) {
        state.lock.lock()
        defer { state.lock.unlock() }
        // Only stop if this is the button that started the timer
        if state.dpadNavigationButton == button {
            state.dpadNavigationTimer?.cancel()
            state.dpadNavigationTimer = nil
            state.dpadNavigationButton = nil
        }
    }

    nonisolated private func handleLongHoldTriggered(_ button: ControllerButton, mapping: LongHoldMapping) {
        let profile = state.lock.withLock {
            state.longHoldTriggered.insert(button)
            return state.activeProfile
        }

        mappingExecutor.executeAction(mapping, for: button, profile: profile, logType: .longPress)
    }

    nonisolated private func handleButtonReleased(_ button: ControllerButton, holdDuration: TimeInterval) {
        stopRepeatTimer(for: button)

        // MARK: - Layer Activator Release
        // If this button is a layer activator, deactivate the layer and return
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

        // Check if this button was showing the on-screen keyboard
        handleOnScreenKeyboardReleased(button)

        // Check if this button was showing the laser pointer
        handleLaserPointerReleased(button)

        // Skip all release handling for D-pad when keyboard is visible
        // This prevents double-tap and long-hold from triggering
        let keyboardVisible = OnScreenKeyboardManager.shared.threadSafeIsVisible
        if keyboardVisible {
            switch button {
            case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
                stopDpadNavigationRepeat(button)
                return  // Skip all release processing
            default:
                break
            }
        }

        // Cleanup: cancel long hold timer and check for held/chord buttons
        if let releaseResult = cleanupReleaseTimers(for: button) {
            if case .heldMapping(let heldMapping) = releaseResult {
                inputSimulator.stopHoldMapping(heldMapping)
                inputLogService?.dismissHeldFeedback(action: heldMapping.feedbackString)
            }
            return
        }

        // Get button mapping and verify constraints
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
    nonisolated private func getReleaseContext(for button: ControllerButton) -> (KeyMapping, Profile, Bool)? {
        guard let (profile, isLongHoldTriggered) = state.lock.withLock({ () -> (Profile, Bool)? in
            guard state.isEnabled, let profile = state.activeProfile else {
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
    nonisolated private func effectiveMapping(for button: ControllerButton, in profile: Profile) -> KeyMapping? {
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
    nonisolated private func getPendingTapInfo(for button: ControllerButton) -> (DispatchWorkItem?, Date?) {
        state.lock.lock()
        defer { state.lock.unlock() }

        return (state.pendingSingleTap[button], state.lastTapTime[button])
    }

    /// Clear pending tap state (used when double-tap window expires or long-hold triggers)
    nonisolated private func clearTapState(for button: ControllerButton) {
        state.lock.withLock {
            state.pendingSingleTap[button]?.cancel()
            state.pendingSingleTap.removeValue(forKey: button)
            state.lastTapTime.removeValue(forKey: button)
        }
    }

    /// Handle double-tap detection - returns true if double-tap was executed
    /// - Parameter skipSingleTap: If true, don't schedule single-tap fallback (used for repeat mappings where primary action already fired)
    nonisolated private func handleDoubleTapIfReady(
        _ button: ControllerButton,
        mapping: KeyMapping,
        pendingSingle: DispatchWorkItem?,
        lastTap: Date?,
        doubleTapMapping: DoubleTapMapping,
        skipSingleTap: Bool = false,
        profile: Profile? = nil
    ) -> Bool {
        let now = Date()

        // Check if we have a pending tap within the double-tap window
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
            // First tap in potential double-tap sequence
            state.lastTapTime[button] = now

            if skipSingleTap {
                // For repeat mappings: just record tap time, don't schedule single-tap
                // (the repeat action already fired on press)
                return nil
            }

            // Schedule single tap fallback
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.clearTapState(for: button)

                // Need to re-fetch profile to execute macro
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

    nonisolated private func handleChord(_ buttons: Set<ControllerButton>) {
        guard let (profile, chordButtons) = state.lock.withLock({ () -> (Profile, Set<ControllerButton>)? in
            guard state.isEnabled, let profile = state.activeProfile else {
                return nil
            }

            // MARK: - Filter out layer activators
            // Layer activator buttons activate their layers but don't participate in chords
            var layerActivators: Set<ControllerButton> = []
            for button in buttons {
                if let layerId = state.layerActivatorMap[button] {
                    layerActivators.insert(button)
                    // Activate the layer (remove if exists, then append for correct ordering)
                    state.activeLayerIds.removeAll { $0 == layerId }
                    state.activeLayerIds.append(layerId)
                    #if DEBUG
                    if let layer = profile.layers.first(where: { $0.id == layerId }) {
                        print("🔷 Layer activated (via chord): \(layer.name)")
                    }
                    #endif
                }
            }

            // Get the remaining non-activator buttons
            let chordButtons = buttons.subtracting(layerActivators)

            // Cancel pending actions for all buttons
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

        // If all buttons were layer activators, we're done
        if chordButtons.isEmpty {
            return
        }

        // If only one button remains, process as individual press
        if chordButtons.count == 1 {
            for button in chordButtons {
                handleButtonPressed(button)
            }
            return
        }

        // Try to match remaining buttons as a chord
        let matchingChord = profile.chordMappings.first { chord in
            chord.buttons == chordButtons
        }

        if let chord = matchingChord {
            // Register active chord only when there's a matching mapping
            // (don't set for fallback case - we want individual button handling)
            state.lock.withLock {
                state.activeChordButtons = chordButtons
            }

            mappingExecutor.executeAction(chord, for: Array(chordButtons), profile: profile, logType: .chord)
        } else {
            // Fallback: Individual handling for non-activator buttons
            let sortedButtons = chordButtons.sorted { $0.rawValue < $1.rawValue }
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
            // Compute timestamp once per tick to avoid redundant system calls
            let now = CFAbsoluteTimeGetCurrent()
            self?.processJoysticks(now: now)
            self?.processTouchpadMomentumTick(now: now)
        }
        timer.resume()
        joystickTimer = timer
    }

    private func stopJoystickPolling() {
        joystickTimer?.cancel()
        joystickTimer = nil

        state.lock.withLock {
            state.reset()
        }
    }

    nonisolated private func processJoysticks(now: CFAbsoluteTime) {
        state.lock.lock()
        defer { state.lock.unlock() }

        guard state.isEnabled, let settings = state.joystickSettings else { return }

        let dt = state.lastJoystickSampleTime > 0 ? now - state.lastJoystickSampleTime : Config.joystickPollInterval
        state.lastJoystickSampleTime = now

        // Process left joystick based on mode
        // Note: accessing controllerService.threadSafeLeftStick is safe (atomic/lock-free usually)
        let leftStick = controllerService.threadSafeLeftStick

        switch settings.leftStickMode {
        case .none:
            break  // Stick disabled
        case .mouse:
            // Remove smoothing - pass raw value (pass now to avoid redundant CFAbsoluteTimeGetCurrent call)
            processMouseMovement(leftStick, settings: settings, now: now)
        case .scroll:
            let leftMagnitudeSquared = leftStick.x * leftStick.x + leftStick.y * leftStick.y
            let leftDeadzoneSquared = settings.mouseDeadzone * settings.mouseDeadzone
            if leftMagnitudeSquared <= leftDeadzoneSquared {
                state.smoothedLeftStick = .zero
            } else {
                state.smoothedLeftStick = smoothStick(leftStick, previous: state.smoothedLeftStick, dt: dt)
            }
            processScrolling(state.smoothedLeftStick, rawStick: leftStick, settings: settings, now: now)
        case .wasdKeys, .arrowKeys:
            processDirectionKeys(
                stick: leftStick,
                deadzone: settings.mouseDeadzone,
                mode: settings.leftStickMode,
                heldKeys: &state.leftStickHeldKeys,
                invertY: settings.invertMouseY
            )
        }

        // Process right joystick (scroll or command wheel)
        let rightStick = controllerService.threadSafeRightStick

        if state.commandWheelActive {
            // Check if alternate modifier is held and swap wheel content
            let altMods = state.wheelAlternateModifiers
            let alternateHeld: Bool = {
                guard altMods.command || altMods.option || altMods.shift || altMods.control else { return false }
                let flags = CGEventSource.flagsState(.combinedSessionState)
                if altMods.command && !flags.contains(.maskCommand) { return false }
                if altMods.option && !flags.contains(.maskAlternate) { return false }
                if altMods.shift && !flags.contains(.maskShift) { return false }
                if altMods.control && !flags.contains(.maskControl) { return false }
                return true
            }()
            // Redirect right stick to command wheel selection
            DispatchQueue.main.async {
                CommandWheelManager.shared.setShowingAlternate(alternateHeld)
                CommandWheelManager.shared.updateSelection(stickX: rightStick.x, stickY: rightStick.y)
            }
        } else {
            // Process right joystick based on mode
            switch settings.rightStickMode {
            case .none:
                break  // Stick disabled
            case .mouse:
                processMouseMovement(rightStick, settings: settings, now: now)
            case .scroll:
                updateScrollDoubleTapState(rawStick: rightStick, settings: settings, now: now)
                let rightMagnitudeSquared = rightStick.x * rightStick.x + rightStick.y * rightStick.y
                let rightDeadzoneSquared = settings.scrollDeadzone * settings.scrollDeadzone

                if rightMagnitudeSquared <= rightDeadzoneSquared {
                    state.smoothedRightStick = .zero
                } else {
                    state.smoothedRightStick = smoothStick(rightStick, previous: state.smoothedRightStick, dt: dt)
                }
                processScrolling(state.smoothedRightStick, rawStick: rightStick, settings: settings, now: now)
            case .wasdKeys, .arrowKeys:
                processDirectionKeys(
                    stick: rightStick,
                    deadzone: settings.scrollDeadzone,
                    mode: settings.rightStickMode,
                    heldKeys: &state.rightStickHeldKeys,
                    invertY: settings.invertScrollY
                )
            }
        }
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

    nonisolated private func processMouseMovement(_ stick: CGPoint, settings: JoystickSettings, now: CFAbsoluteTime) {
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

        if isFocusActive != wasFocusActive {
            state.wasFocusActive = isFocusActive
            // Haptic feedback runs async internally, won't block input
            performFocusModeHaptic(entering: isFocusActive)

            // Show/hide focus mode cursor indicator
            Task { @MainActor in
                if isFocusActive {
                    FocusModeIndicator.shared.show()
                } else {
                    FocusModeIndicator.shared.hide()
                }
            }

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
        usageStatsService?.recordJoystickMouseDistance(dx: Double(dx), dy: Double(dy))
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
        guard let profile = state.lock.withLock({
            guard state.isEnabled else { return nil as Profile? }
            return state.activeProfile
        }) else { return }

        guard let mapping = effectiveMapping(for: button, in: profile) else {
            inputLogService?.log(buttons: [button], type: .singlePress, action: "(unmapped)")
            return
        }

        if let doubleTapMapping = mapping.doubleTapMapping, !doubleTapMapping.isEmpty {
            let (pendingSingle, lastTap) = getPendingTapInfo(for: button)
            _ = handleDoubleTapIfReady(
                button,
                mapping: mapping,
                pendingSingle: pendingSingle,
                lastTap: lastTap,
                doubleTapMapping: doubleTapMapping,
                profile: profile
            )
            return
        }

        mappingExecutor.executeAction(mapping, for: button, profile: profile)
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
        guard let profile = state.lock.withLock({
            guard state.isEnabled else { return nil as Profile? }
            // Cancel any pending single tap for this button
            state.pendingSingleTap[button]?.cancel()
            state.pendingSingleTap.removeValue(forKey: button)
            state.lastTapTime.removeValue(forKey: button)
            return state.activeProfile
        }) else { return }

        // Long tap only executes if there's an explicit long hold mapping configured
        // (no default fallback like regular taps have)
        guard let mapping = profile.buttonMappings[button],
              let longHoldMapping = mapping.longHoldMapping,
              !longHoldMapping.isEmpty else {
            return
        }

        mappingExecutor.executeAction(longHoldMapping, for: button, profile: profile, logType: .longPress)
    }

    /// Process touchpad movement for mouse control (DualSense only)
    /// Unlike joystick which is position-based (continuous velocity), touchpad is delta-based (like a laptop trackpad)
    nonisolated private func processTouchpadMovement(_ delta: CGPoint) {
        guard let (settings, isGestureActive) = state.lock.withLock({
            guard state.isEnabled, let settings = state.joystickSettings else { return nil as (JoystickSettings, Bool)? }
            return (settings, state.isTouchpadGestureActive)
        }) else { return }

        let movementBlocked = controllerService.threadSafeIsTouchpadMovementBlocked
        if isGestureActive || movementBlocked {
            state.lock.withLock {
                state.smoothedTouchpadDelta = .zero
                state.lastTouchpadSampleTime = 0
            }
            return
        }

        let now = CFAbsoluteTimeGetCurrent()

        let (smoothedDeltaSnapshot, lastSampleTime) = state.lock.withLock {
            (state.smoothedTouchpadDelta, state.lastTouchpadSampleTime)
        }
        var smoothedDelta = smoothedDeltaSnapshot

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

        state.lock.withLock {
            state.smoothedTouchpadDelta = smoothedDelta
            state.lastTouchpadSampleTime = now
        }

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
        usageStatsService?.recordTouchpadMouseDistance(dx: dx, dy: dy)
    }

    // MARK: - Two-Finger Touchpad Gestures

    /// Process two-finger touchpad gestures (pan + pinch zoom)
    /// This method handles:
    /// 1. Gesture lifecycle (begin/change/end phases)
    /// 2. Delta smoothing for consistent feel
    /// 3. Pinch vs Pan discrimination
    /// 4. Native magnify gestures or Cmd+Plus/Minus zoom
    nonisolated private func processTouchpadGesture(_ gesture: TouchpadGesture) {
        // MARK: State Snapshot
        let isActive = gesture.isPrimaryTouching && gesture.isSecondaryTouching
        guard let snapshot = state.lock.withLock({ () -> (settings: JoystickSettings, wasActive: Bool, smoothedCenter: CGPoint, smoothedDistance: Double, lastSampleTime: TimeInterval, smoothedVelocity: CGPoint)? in
            guard state.isEnabled, let settings = state.joystickSettings else { return nil }
            let wasActive = state.isTouchpadGestureActive
            state.isTouchpadGestureActive = isActive
            return (settings, wasActive, state.smoothedTouchpadCenterDelta, state.smoothedTouchpadDistanceDelta, state.lastTouchpadGestureSampleTime, state.smoothedTouchpadPanVelocity)
        }) else { return }
        let settings = snapshot.settings
        let wasActive = snapshot.wasActive
        var smoothedCenter = snapshot.smoothedCenter
        var smoothedDistance = snapshot.smoothedDistance
        let lastSampleTime = snapshot.lastSampleTime
        var smoothedVelocity = snapshot.smoothedVelocity

        guard isActive else {
            // End magnify gesture if it was active
            let wasMagnifyActive = state.lock.withLock {
                let wasMagnify = state.touchpadMagnifyGestureActive
                if wasMagnify {
                    state.touchpadMagnifyGestureActive = false
                    state.touchpadPinchAccumulator = 0
                    state.touchpadMagnifyDirection = 0
                    state.touchpadMagnifyDirectionLockUntil = 0
                }
                state.touchpadPanActive = false
                return wasMagnify
            }
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
                    flags: inputSimulator.getHeldModifiers()
                )
            }
            state.lock.withLock {
                state.smoothedTouchpadCenterDelta = .zero
                state.smoothedTouchpadDistanceDelta = 0
                state.lastTouchpadGestureSampleTime = 0
                state.touchpadScrollResidualX = 0
                state.touchpadScrollResidualY = 0
            }
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

        state.lock.withLock {
            state.smoothedTouchpadCenterDelta = smoothedCenter
            state.smoothedTouchpadDistanceDelta = smoothedDistance
            state.lastTouchpadGestureSampleTime = now
        }

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
                flags: inputSimulator.getHeldModifiers()
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
            // Capture all pinch decisions under a single lock acquisition
            let pinchResult: (shouldBeginMagnify: Bool, shouldPostMagnify: Bool, magnification: Double, zoomSteps: Int, zoomDirection: Int) = state.lock.withLock {
                // Reset pan-related state since we're doing pinch
                state.touchpadScrollResidualX = 0
                state.touchpadScrollResidualY = 0
                state.touchpadPanActive = false

                if settings.touchpadUseNativeZoom {
                    // Use native macOS magnify gesture
                    var pinchDelta = smoothedDistance
                    if pinchDelta != 0 {
                        let direction = pinchDelta > 0 ? 1.0 : -1.0
                        if !state.touchpadMagnifyGestureActive || state.touchpadMagnifyDirection == 0 {
                            state.touchpadMagnifyDirection = direction
                            state.touchpadMagnifyDirectionLockUntil = now + Config.touchpadPinchDirectionLockInterval
                        } else if direction != state.touchpadMagnifyDirection {
                            if now < state.touchpadMagnifyDirectionLockUntil {
                                pinchDelta = 0
                            } else {
                                state.touchpadMagnifyDirection = direction
                                state.touchpadMagnifyDirectionLockUntil = now + Config.touchpadPinchDirectionLockInterval
                            }
                        }
                    }

                    let magnification = pinchDelta * Config.touchpadPinchSensitivityMultiplier / 1000.0
                    let shouldPostMagnify = pinchDelta != 0
                    let shouldBeginMagnify = !state.touchpadMagnifyGestureActive

                    state.touchpadPinchAccumulator += abs(pinchDelta)
                    state.touchpadMagnifyGestureActive = true
                    return (shouldBeginMagnify, shouldPostMagnify, magnification, 0, 0)
                } else {
                    // Cmd+Plus/Minus zoom (accumulator-based)
                    state.touchpadPinchAccumulator += smoothedDistance
                    let threshold = 0.08
                    if state.touchpadPinchAccumulator > threshold {
                        let steps = min(3, max(1, Int(state.touchpadPinchAccumulator / threshold)))
                        state.touchpadPinchAccumulator = 0
                        return (false, false, 0, steps, 1)  // zoom in
                    } else if state.touchpadPinchAccumulator < -threshold {
                        let steps = min(3, max(1, Int(abs(state.touchpadPinchAccumulator) / threshold)))
                        state.touchpadPinchAccumulator = 0
                        return (false, false, 0, steps, -1)  // zoom out
                    }
                    return (false, false, 0, 0, 0)  // no zoom action
                }
            }

            // Act on decisions outside the lock
            if pinchResult.shouldBeginMagnify {
                postMagnifyGestureEvent(0, 0)  // begin gesture (phase 0)
            }
            if pinchResult.shouldPostMagnify {
                postMagnifyGestureEvent(pinchResult.magnification, 1)  // magnify (phase 1)
            }
            if pinchResult.zoomDirection > 0 {
                for _ in 0..<pinchResult.zoomSteps {
                    inputSimulator.pressKey(KeyCodeMapping.equal, modifiers: [.maskCommand])
                }
            } else if pinchResult.zoomDirection < 0 {
                for _ in 0..<pinchResult.zoomSteps {
                    inputSimulator.pressKey(KeyCodeMapping.minus, modifiers: [.maskCommand])
                }
            }
            return
        }

        // If we've accumulated significant pinch, suppress scrolling
        // Only suppress when accumulator is large enough to indicate intentional pinch
        let pinchAccumMagnitude = state.lock.withLock { abs(state.touchpadPinchAccumulator) }
        if pinchAccumMagnitude > 0.05 {
            return
        }

        guard panMagnitude > Config.touchpadPanDeadzone else {
            let now = CFAbsoluteTimeGetCurrent()
            state.lock.withLock {
                state.smoothedTouchpadPanVelocity = .zero
                state.touchpadPanActive = false
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
            }
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
        state.lock.withLock {
            state.smoothedTouchpadPanVelocity = smoothedVelocity
            state.touchpadPanActive = true
            state.touchpadMomentumLastGestureTime = now
            if velocityMagnitude <= Config.touchpadMomentumStopVelocity {
                state.touchpadMomentumCandidateVelocity = .zero
                state.touchpadMomentumCandidateTime = 0
                state.touchpadMomentumHighVelocityStartTime = 0
                state.touchpadMomentumHighVelocitySampleCount = 0
                state.touchpadMomentumPeakVelocity = .zero
                state.touchpadMomentumPeakMagnitude = 0
            } else if velocityMagnitude >= Config.touchpadMomentumStartVelocity {
                // Track high velocity samples and peak
                if state.touchpadMomentumHighVelocityStartTime == 0 {
                    state.touchpadMomentumHighVelocityStartTime = now
                }
                state.touchpadMomentumHighVelocitySampleCount += 1
                if velocityMagnitude > state.touchpadMomentumPeakMagnitude {
                    state.touchpadMomentumPeakMagnitude = velocityMagnitude
                    state.touchpadMomentumPeakVelocity = smoothedVelocity
                }

                // Require 2+ samples to filter out edge-exit spikes (single sample spikes)
                let sustainedDuration = now - state.touchpadMomentumHighVelocityStartTime
                if state.touchpadMomentumHighVelocitySampleCount >= 2 &&
                    sustainedDuration >= Config.touchpadMomentumSustainedDuration {
                    let baseMagnitude = velocityMagnitude
                    let baseVelocity = smoothedVelocity
                    let clampedMagnitude = min(baseMagnitude, Config.touchpadMomentumMaxVelocity)
                    let velocityScale = baseMagnitude > 0 ? clampedMagnitude / baseMagnitude : 0
                    let boostRange = Config.touchpadMomentumBoostMax - Config.touchpadMomentumBoostMin
                    let velocityRange = Config.touchpadMomentumBoostMaxVelocity - Config.touchpadMomentumStartVelocity
                    let velocityAboveThreshold = min(baseMagnitude - Config.touchpadMomentumStartVelocity, velocityRange)
                    let boostFactor = velocityRange > 0 ? velocityAboveThreshold / velocityRange : 0
                    let boost = Config.touchpadMomentumBoostMin + boostRange * boostFactor
                    let clampedVelocity = CGPoint(
                        x: baseVelocity.x * velocityScale * boost,
                        y: baseVelocity.y * velocityScale * boost
                    )
                    state.touchpadMomentumCandidateVelocity = clampedVelocity
                    state.touchpadMomentumCandidateTime = now
                }
            } else {
                // Velocity is between stop and start thresholds - reset high velocity tracking
                state.touchpadMomentumCandidateVelocity = .zero
                state.touchpadMomentumCandidateTime = 0
                state.touchpadMomentumHighVelocityStartTime = 0
                state.touchpadMomentumHighVelocitySampleCount = 0
                state.touchpadMomentumPeakVelocity = .zero
                state.touchpadMomentumPeakMagnitude = 0
            }
        }
    }

    nonisolated private func processTouchpadMomentumTick(now: CFAbsoluteTime) {
        guard let snapshot = state.lock.withLock({ () -> (isGestureActive: Bool, panActive: Bool, panVelocity: CGPoint, lastGestureTime: TimeInterval, velocity: CGPoint, wasActive: Bool, residualX: Double, residualY: Double, lastUpdate: TimeInterval)? in
            guard state.isEnabled else { return nil }
            return (state.isTouchpadGestureActive, state.touchpadPanActive, state.smoothedTouchpadPanVelocity, state.touchpadMomentumLastGestureTime, state.touchpadMomentumVelocity, state.touchpadMomentumWasActive, state.touchpadScrollResidualX, state.touchpadScrollResidualY, state.touchpadMomentumLastUpdate)
        }) else { return }
        let isGestureActive = snapshot.isGestureActive
        let panActive = snapshot.panActive
        let panVelocity = snapshot.panVelocity
        let lastGestureTime = snapshot.lastGestureTime
        var velocity = snapshot.velocity
        var wasActive = snapshot.wasActive
        var residualX = snapshot.residualX
        var residualY = snapshot.residualY
        let lastUpdate = snapshot.lastUpdate

        if isGestureActive {
            if lastUpdate == 0 {
                state.lock.withLock { state.touchpadMomentumLastUpdate = now }
                return
            }
            guard panActive else {
                state.lock.withLock { state.touchpadMomentumLastUpdate = now }
                return
            }
            let dt = max(now - lastUpdate, Config.touchpadMomentumMinDeltaTime)
            let dx = Double(panVelocity.x) * dt
            let dy = Double(panVelocity.y) * dt
            let combinedDx = dx + residualX
            let combinedDy = dy + residualY
            // Use standard rounding so values >= 0.5 round to 1, enabling smoother diagonals
            let sendDx = combinedDx.rounded()
            let sendDy = combinedDy.rounded()
            residualX = combinedDx - sendDx
            residualY = combinedDy - sendDy
            if sendDx != 0 || sendDy != 0 {
                inputSimulator.scroll(
                    dx: CGFloat(sendDx),
                    dy: CGFloat(sendDy),
                    phase: .changed,
                    momentumPhase: nil,
                    isContinuous: true,
                    flags: inputSimulator.getHeldModifiers()
                )
                usageStatsService?.recordScrollDistance(dx: sendDx, dy: sendDy)
            }
            state.lock.withLock {
                state.touchpadMomentumLastUpdate = now
                state.touchpadScrollResidualX = residualX
                state.touchpadScrollResidualY = residualY
            }
            return
        }

        if lastUpdate == 0 {
            state.lock.withLock { state.touchpadMomentumLastUpdate = now }
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
                    flags: inputSimulator.getHeldModifiers()
                )
            }
            state.lock.withLock {
                state.touchpadMomentumVelocity = .zero
                state.touchpadMomentumWasActive = false
                state.touchpadMomentumLastUpdate = now
                state.touchpadScrollResidualX = 0
                state.touchpadScrollResidualY = 0
            }
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
                    flags: inputSimulator.getHeldModifiers()
                )
            }
            state.lock.withLock {
                state.touchpadMomentumVelocity = .zero
                state.touchpadMomentumWasActive = false
                state.touchpadMomentumLastUpdate = now
                state.touchpadScrollResidualX = 0
                state.touchpadScrollResidualY = 0
            }
            return
        }

        let dx = Double(velocity.x) * dt
        let dy = Double(velocity.y) * dt
        let combinedDx = dx + residualX
        let combinedDy = dy + residualY
        // Use standard rounding so values >= 0.5 round to 1, enabling smoother diagonals
        let sendDx = combinedDx.rounded()
        let sendDy = combinedDy.rounded()
        residualX = combinedDx - sendDx
        residualY = combinedDy - sendDy

        if sendDx != 0 || sendDy != 0 {
            let momentumPhase: CGMomentumScrollPhase = wasActive ? .continuous : .begin
            inputSimulator.scroll(
                dx: CGFloat(sendDx),
                dy: CGFloat(sendDy),
                phase: nil,
                momentumPhase: momentumPhase,
                isContinuous: true,
                flags: inputSimulator.getHeldModifiers()
            )
            wasActive = true
        }

        state.lock.withLock {
            state.touchpadMomentumVelocity = velocity
            state.touchpadMomentumWasActive = wasActive
            state.touchpadMomentumLastUpdate = now
            state.touchpadScrollResidualX = residualX
            state.touchpadScrollResidualY = residualY
        }
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

        // Suppress horizontal scroll when vertical is dominant to prevent accidental panning
        // Only apply horizontal scroll if |x| >= |y| * threshold ratio
        let absX = abs(stick.x)
        let absY = abs(stick.y)
        let effectiveX: CGFloat
        if absY > absX && absX < absY * Config.scrollHorizontalThresholdRatio {
            effectiveX = 0  // Suppress horizontal when scrolling mostly vertical
        } else {
            effectiveX = stick.x
        }

        let dx = -effectiveX * scale
        var dy = stick.y * scale

        dy = settings.invertScrollY ? -dy : dy

        if state.scrollBoostDirection != 0,
           (rawStick.y >= 0 ? 1 : -1) == state.scrollBoostDirection {
            dy *= settings.scrollBoostMultiplier
        }

        inputSimulator.scroll(
            dx: dx,
            dy: dy,
            phase: nil,
            momentumPhase: nil,
            isContinuous: false,
            flags: inputSimulator.getHeldModifiers()
        )
        usageStatsService?.recordScrollDistance(dx: Double(dx), dy: Double(dy))
    }

    /// Processes stick input as direction keys (WASD or Arrow keys)
    /// Keys are held while stick is deflected and released when returning to center
    nonisolated private func processDirectionKeys(
        stick: CGPoint,
        deadzone: Double,
        mode: StickMode,
        heldKeys: inout Set<CGKeyCode>,
        invertY: Bool
    ) {
        // Key codes for WASD and Arrow keys
        let upKey: CGKeyCode = mode == .wasdKeys ? 13 : 126      // W or Up
        let downKey: CGKeyCode = mode == .wasdKeys ? 1 : 125     // S or Down
        let leftKey: CGKeyCode = mode == .wasdKeys ? 0 : 123     // A or Left
        let rightKey: CGKeyCode = mode == .wasdKeys ? 2 : 124    // D or Right

        // Calculate which keys should be held based on stick direction
        var targetKeys: Set<CGKeyCode> = []

        let magnitudeSquared = stick.x * stick.x + stick.y * stick.y
        let deadzoneSquared = deadzone * deadzone

        if magnitudeSquared > deadzoneSquared {
            // Apply deadzone and normalize
            let stickX = Double(stick.x)
            let stickY = Double(stick.y) * (invertY ? -1.0 : 1.0)

            // Use diagonal threshold to determine key presses
            // 8-direction support: diagonals hold two keys
            let threshold = 0.4  // ~sin(23.5°), allows smooth 8-way movement

            if stickY > threshold {
                targetKeys.insert(upKey)
            } else if stickY < -threshold {
                targetKeys.insert(downKey)
            }

            if stickX > threshold {
                targetKeys.insert(rightKey)
            } else if stickX < -threshold {
                targetKeys.insert(leftKey)
            }
        }

        // Release keys that should no longer be held
        for key in heldKeys {
            if !targetKeys.contains(key) {
                inputSimulator.keyUp(key)
            }
        }

        // Press keys that should now be held
        for key in targetKeys {
            if !heldKeys.contains(key) {
                inputSimulator.keyDown(key, modifiers: [])
            }
        }

        // Update held keys state
        heldKeys = targetKeys
    }

    /// Releases all direction keys for both sticks (called on disable)
    nonisolated private func releaseAllDirectionKeys() {
        let (leftKeys, rightKeys) = state.lock.withLock {
            let left = state.leftStickHeldKeys
            let right = state.rightStickHeldKeys
            state.leftStickHeldKeys.removeAll()
            state.rightStickHeldKeys.removeAll()
            return (left, right)
        }

        for key in leftKeys {
            inputSimulator.keyUp(key)
        }
        for key in rightKeys {
            inputSimulator.keyUp(key)
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
