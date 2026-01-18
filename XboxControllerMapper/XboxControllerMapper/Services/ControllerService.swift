import Foundation
import GameController
import Combine
import CoreHaptics

// MARK: - Thread-Safe Input State (High Performance)

private final class ControllerStorage: @unchecked Sendable {
    let lock = NSLock()
    var leftStick: CGPoint = .zero
    var rightStick: CGPoint = .zero
    var leftTrigger: Float = 0
    var rightTrigger: Float = 0

    // Touchpad State (DualSense only)
    var touchpadPosition: CGPoint = .zero
    var touchpadPreviousPosition: CGPoint = .zero
    var isTouchpadTouching: Bool = false
    var isDualSense: Bool = false
    var pendingTouchpadDelta: CGPoint? = nil  // Delayed by 1 frame to filter lift artifacts
    var touchpadFramesSinceTouch: Int = 0  // Skip first frames after touch to let position settle
    var touchpadSuppressUntil: TimeInterval = 0

    // Button State
    var activeButtons: Set<ControllerButton> = []
    var buttonPressTimestamps: [ControllerButton: Date] = [:]

    // Chord Detection State
    var pendingButtons: Set<ControllerButton> = []
    var capturedButtonsInWindow: Set<ControllerButton> = []
    var pendingReleases: [ControllerButton: TimeInterval] = [:]
    var chordWorkItem: DispatchWorkItem?
    var chordWindow: TimeInterval = 0.15

    // Callbacks
    var onButtonPressed: ((ControllerButton) -> Void)?
    var onButtonReleased: ((ControllerButton, TimeInterval) -> Void)?
    var onChordDetected: ((Set<ControllerButton>) -> Void)?
    var onLeftStickMoved: ((CGPoint) -> Void)?
    var onRightStickMoved: ((CGPoint) -> Void)?
    var onTouchpadMoved: ((CGPoint) -> Void)?  // Delta movement
}

/// Service for managing Xbox controller connection and input
@MainActor
class ControllerService: ObservableObject {
    @Published var isConnected = false
    @Published var connectedController: GCController?
    @Published var controllerName: String = ""

    /// Currently pressed buttons (UI use only, updated asynchronously)
    @Published var activeButtons: Set<ControllerButton> = []
    
    private let controllerQueue = DispatchQueue(label: "com.xboxmapper.controller", qos: .userInteractive)
    private let storage = ControllerStorage()
    
    nonisolated var threadSafeLeftStick: CGPoint {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.leftStick
    }
    
    nonisolated var threadSafeRightStick: CGPoint {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.rightStick
    }
    
    nonisolated var threadSafeLeftTrigger: Float {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.leftTrigger
    }
    
    nonisolated var threadSafeRightTrigger: Float {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.rightTrigger
    }
    
    // Accessor for MappingEngine to check active buttons thread-safely
    nonisolated var threadSafeActiveButtons: Set<ControllerButton> {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.activeButtons
    }

    // Touchpad accessors (DualSense only)
    nonisolated var threadSafeTouchpadDelta: CGPoint {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        guard storage.isTouchpadTouching else { return .zero }
        let delta = CGPoint(
            x: storage.touchpadPosition.x - storage.touchpadPreviousPosition.x,
            y: storage.touchpadPosition.y - storage.touchpadPreviousPosition.y
        )
        return delta
    }

    nonisolated var threadSafeIsTouchpadTouching: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isTouchpadTouching
    }

    nonisolated var threadSafeIsDualSense: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isDualSense
    }

    /// Left joystick position (-1 to 1) - UI/Legacy use only
    @Published var leftStick: CGPoint = .zero

    /// Right joystick position (-1 to 1) - UI/Legacy use only
    @Published var rightStick: CGPoint = .zero

    /// Left trigger pressure (0 to 1) - UI/Legacy use only
    @Published var leftTriggerValue: Float = 0

    /// Right trigger pressure (0 to 1) - UI/Legacy use only
    @Published var rightTriggerValue: Float = 0

    /// Chord detection window (accessible for testing and configuration)
    var chordWindow: TimeInterval {
        get {
            storage.lock.lock()
            defer { storage.lock.unlock() }
            return storage.chordWindow
        }
        set {
            storage.lock.lock()
            storage.chordWindow = newValue
            storage.lock.unlock()
        }
    }

    // MARK: - Throttled UI Display Values (updated at ~15Hz to avoid UI blocking)
    @Published var displayLeftStick: CGPoint = .zero
    @Published var displayRightStick: CGPoint = .zero
    @Published var displayLeftTrigger: Float = 0
    @Published var displayRightTrigger: Float = 0
    private var displayUpdateTimer: DispatchSourceTimer?

    /// Battery level (0 to 1)
    @Published var batteryLevel: Float = -1
    
    /// Battery state
    @Published var batteryState: GCDeviceBattery.State = .unknown

    // Callback proxies (Thread-safe storage backing)
    var onButtonPressed: ((ControllerButton) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onButtonPressed }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onButtonPressed = newValue }
    }
    var onButtonReleased: ((ControllerButton, TimeInterval) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onButtonReleased }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onButtonReleased = newValue }
    }
    var onChordDetected: ((Set<ControllerButton>) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onChordDetected }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onChordDetected = newValue }
    }
    var onLeftStickMoved: ((CGPoint) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onLeftStickMoved }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onLeftStickMoved = newValue }
    }
    var onRightStickMoved: ((CGPoint) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onRightStickMoved }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onRightStickMoved = newValue }
    }
    var onTouchpadMoved: ((CGPoint) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onTouchpadMoved }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onTouchpadMoved = newValue }
    }

    private var cancellables = Set<AnyCancellable>()
    
    // Low-level monitor for Xbox Guide button
    private let guideMonitor = XboxGuideMonitor()
    
    // Low-level monitor for Battery (Bluetooth Workaround for macOS/Xbox issue)
    private let batteryMonitor = BluetoothBatteryMonitor()

    // Haptic engines for controller feedback (try multiple localities)
    private var hapticEngines: [CHHapticEngine] = []
    private let hapticQueue = DispatchQueue(label: "com.xboxmapper.haptic", qos: .userInitiated)

    init() {
        GCController.shouldMonitorBackgroundEvents = true

        setupNotifications()
        startDiscovery()
        checkConnectedControllers()
        
        guideMonitor.onGuideButtonAction = { [weak self] isPressed in
            guard let self = self else { return }
            self.controllerQueue.async {
                self.handleButton(.xbox, pressed: isPressed)
            }
        }
        
        batteryMonitor.startMonitoring()
        batteryMonitor.$batteryLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.updateBatteryInfo()
            }
            .store(in: &cancellables)
    }

    func cleanup() {
        stopDiscovery()
        batteryMonitor.stopMonitoring()
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
        GCController.startWirelessControllerDiscovery()
    }

    private func stopDiscovery() {
        GCController.stopWirelessControllerDiscovery()
    }

    private func checkConnectedControllers() {
        if let controller = GCController.controllers().first {
            controllerConnected(controller)
        }
    }

    private func controllerConnected(_ controller: GCController) {
        connectedController = controller
        isConnected = true
        controllerName = controller.vendorName ?? "Xbox Controller"

        setupInputHandlers(for: controller)
        setupHaptics(for: controller)
        updateBatteryInfo()
        startDisplayUpdateTimer()
    }

    private func controllerDisconnected() {
        connectedController = nil
        isConnected = false
        controllerName = ""
        activeButtons.removeAll()
        leftStick = .zero
        rightStick = .zero
        batteryLevel = -1
        batteryState = .unknown
        stopDisplayUpdateTimer()
        stopHaptics()

        storage.lock.lock()
        storage.activeButtons.removeAll()
        storage.buttonPressTimestamps.removeAll()
        storage.pendingButtons.removeAll()
        storage.capturedButtonsInWindow.removeAll()
        storage.pendingReleases.removeAll()
        storage.chordWorkItem?.cancel()
        storage.leftStick = .zero
        storage.rightStick = .zero
        // Reset DualSense state
        storage.isDualSense = false
        storage.isTouchpadTouching = false
        storage.touchpadPosition = .zero
        storage.touchpadPreviousPosition = .zero
        storage.pendingTouchpadDelta = nil
        storage.touchpadFramesSinceTouch = 0
        storage.lock.unlock()
    }

    // MARK: - Display Update Timer

    private func startDisplayUpdateTimer() {
        stopDisplayUpdateTimer()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: Config.displayRefreshInterval, leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            let tsLeft = self.threadSafeLeftStick
            let tsRight = self.threadSafeRightStick
            let tsLeftTrig = self.threadSafeLeftTrigger
            let tsRightTrig = self.threadSafeRightTrigger
            
            self.leftStick = tsLeft
            self.rightStick = tsRight
            self.leftTriggerValue = tsLeftTrig
            self.rightTriggerValue = tsRightTrig
            
            if abs(self.displayLeftStick.x - tsLeft.x) > Config.displayUpdateDeadzone ||
               abs(self.displayLeftStick.y - tsLeft.y) > Config.displayUpdateDeadzone {
                self.displayLeftStick = tsLeft
            }
            if abs(self.displayRightStick.x - tsRight.x) > Config.displayUpdateDeadzone ||
               abs(self.displayRightStick.y - tsRight.y) > Config.displayUpdateDeadzone {
                self.displayRightStick = tsRight
            }
            if abs(self.displayLeftTrigger - tsLeftTrig) > Float(Config.displayUpdateDeadzone) {
                self.displayLeftTrigger = tsLeftTrig
            }
            if abs(self.displayRightTrigger - tsRightTrig) > Float(Config.displayUpdateDeadzone) {
                self.displayRightTrigger = tsRightTrig
            }
        }
        timer.resume()
        displayUpdateTimer = timer
    }

    private func stopDisplayUpdateTimer() {
        displayUpdateTimer?.cancel()
        displayUpdateTimer = nil
        displayLeftStick = .zero
        displayRightStick = .zero
        displayLeftTrigger = 0
        displayRightTrigger = 0
    }

    private func updateBatteryInfo() {
        if let ioLevel = batteryMonitor.batteryLevel {
            batteryLevel = Float(ioLevel) / 100.0
            batteryState = batteryMonitor.isCharging ? .charging : .discharging
            return
        }
        
        if let battery = connectedController?.battery {
            batteryLevel = battery.batteryLevel
            batteryState = battery.batteryState
        }
        
        if isConnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.batteryUpdateInterval) { [weak self] in
                self?.updateBatteryInfo()
            }
        }
    }

    private func setupInputHandlers(for controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }

        // Use controllerQueue for all button inputs
        
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.a, pressed: pressed) }
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.b, pressed: pressed) }
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.x, pressed: pressed) }
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.y, pressed: pressed) }
        }

        // Bumpers
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.leftBumper, pressed: pressed) }
        }
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.rightBumper, pressed: pressed) }
        }

        // Triggers
        gamepad.leftTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            self?.updateLeftTrigger(value, pressed: pressed)
        }
        gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            self?.updateRightTrigger(value, pressed: pressed)
        }

        // D-pad
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.dpadUp, pressed: pressed) }
        }
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.dpadDown, pressed: pressed) }
        }
        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.dpadLeft, pressed: pressed) }
        }
        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.dpadRight, pressed: pressed) }
        }

        // Special buttons
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.menu, pressed: pressed) }
        }
        gamepad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.view, pressed: pressed) }
        }
        
        if let extendedGamepad = gamepad as? GCExtendedGamepad {
            extendedGamepad.buttonHome?.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.controllerQueue.async { self?.handleButton(.xbox, pressed: pressed) }
            }
        }

        if let xboxGamepad = gamepad as? GCXboxGamepad {
            xboxGamepad.buttonShare?.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.controllerQueue.async { self?.handleButton(.share, pressed: pressed) }
            }
        }

        gamepad.leftThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.leftThumbstick, pressed: pressed) }
        }
        gamepad.rightThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.rightThumbstick, pressed: pressed) }
        }

        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.updateLeftStick(x: xValue, y: yValue)
        }

        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.updateRightStick(x: xValue, y: yValue)
        }

        // DualSense-specific: Touchpad support
        if let dualSenseGamepad = gamepad as? GCDualSenseGamepad {
            storage.lock.lock()
            storage.isDualSense = true
            storage.lock.unlock()

            // Touchpad button (click)
            dualSenseGamepad.touchpadButton.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.suppressTouchpadMovement()
                self?.controllerQueue.async { self?.handleButton(.touchpadButton, pressed: pressed) }
            }

            // Touchpad primary finger position (for mouse control)
            // The touchpad provides X/Y from -1 to 1, we track position and calculate delta
            dualSenseGamepad.touchpadPrimary.valueChangedHandler = { [weak self] _, xValue, yValue in
                self?.updateTouchpad(x: xValue, y: yValue)
            }
        }
    }

    // MARK: - Thread-Safe Update Helpers
    
    nonisolated private func updateLeftStick(x: Float, y: Float) {
        storage.lock.lock()
        storage.leftStick = CGPoint(x: CGFloat(x), y: CGFloat(y))
        storage.lock.unlock()
        
        Task { @MainActor in
            self.onLeftStickMoved?(CGPoint(x: CGFloat(x), y: CGFloat(y)))
        }
    }
    
    nonisolated private func updateRightStick(x: Float, y: Float) {
        storage.lock.lock()
        storage.rightStick = CGPoint(x: CGFloat(x), y: CGFloat(y))
        storage.lock.unlock()

        Task { @MainActor in
            self.onRightStickMoved?(CGPoint(x: CGFloat(x), y: CGFloat(y)))
        }
    }

    nonisolated private func updateTouchpad(x: Float, y: Float) {
        storage.lock.lock()

        let newPosition = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let wasTouching = storage.isTouchpadTouching
        let now = CFAbsoluteTimeGetCurrent()

        // Detect if finger is on touchpad (non-zero position indicates touch)
        // GCControllerDirectionPad returns 0,0 when no finger is present
        let isTouching = abs(x) > 0.001 || abs(y) > 0.001

        if now < storage.touchpadSuppressUntil {
            if isTouching {
                storage.isTouchpadTouching = true
                storage.touchpadFramesSinceTouch = 0
                storage.pendingTouchpadDelta = nil
                storage.touchpadPosition = newPosition
                storage.touchpadPreviousPosition = newPosition
            } else {
                storage.isTouchpadTouching = false
                storage.touchpadPosition = .zero
                storage.touchpadPreviousPosition = .zero
                storage.touchpadFramesSinceTouch = 0
                storage.pendingTouchpadDelta = nil
            }
            storage.lock.unlock()
            return
        }

        if isTouching {
            if wasTouching {
                // Increment frame counter
                storage.touchpadFramesSinceTouch += 1

                // Skip first 2 frames after touch to let position settle
                // This prevents spurious movement when finger first contacts touchpad
                if storage.touchpadFramesSinceTouch <= 2 {
                    storage.touchpadPosition = newPosition
                    storage.touchpadPreviousPosition = newPosition
                    storage.lock.unlock()
                    return
                }

                // Finger still touching - calculate delta
                let delta = CGPoint(
                    x: newPosition.x - storage.touchpadPosition.x,
                    y: newPosition.y - storage.touchpadPosition.y
                )

                // Detect sudden large jumps which indicate:
                // 1. Finger lift (touchpad sends edge position before resetting)
                // 2. Position wrap/reset during long drags
                // Ignore deltas larger than threshold (normal finger movement is much smaller)
                let jumpThreshold: CGFloat = 0.3
                let isJump = abs(delta.x) > jumpThreshold || abs(delta.y) > jumpThreshold

                if isJump {
                    // Treat as new touch - reset position, don't apply delta
                    storage.touchpadPosition = newPosition
                    storage.touchpadPreviousPosition = newPosition
                    storage.pendingTouchpadDelta = nil
                    storage.lock.unlock()
                    return
                }

                storage.touchpadPreviousPosition = storage.touchpadPosition
                storage.touchpadPosition = newPosition

                // Apply the PREVIOUS pending delta (if any), then store current as pending
                // This 1-frame delay filters out artifacts right before finger lift
                let previousPending = storage.pendingTouchpadDelta
                let callback = storage.onTouchpadMoved

                // Store current delta as pending for next frame
                if abs(delta.x) > 0.001 || abs(delta.y) > 0.001 {
                    storage.pendingTouchpadDelta = delta
                } else {
                    storage.pendingTouchpadDelta = nil
                }

                storage.lock.unlock()

                // Apply previous pending delta
                if let pending = previousPending {
                    callback?(pending)
                }
            } else {
                // Finger just touched - initialize position, no delta yet
                storage.touchpadPosition = newPosition
                storage.touchpadPreviousPosition = newPosition
                storage.isTouchpadTouching = true
                storage.touchpadFramesSinceTouch = 0
                storage.pendingTouchpadDelta = nil
                storage.lock.unlock()
            }
        } else {
            // Finger lifted - discard any pending delta (it was likely lift artifact)
            storage.isTouchpadTouching = false
            storage.touchpadPosition = .zero
            storage.touchpadPreviousPosition = .zero
            storage.touchpadFramesSinceTouch = 0
            storage.pendingTouchpadDelta = nil
            storage.lock.unlock()
        }
    }

    nonisolated private func suppressTouchpadMovement() {
        storage.lock.lock()
        storage.touchpadSuppressUntil = CFAbsoluteTimeGetCurrent() + Config.touchpadClickSuppressDuration
        storage.pendingTouchpadDelta = nil
        storage.touchpadFramesSinceTouch = 0
        storage.lock.unlock()
    }

    nonisolated private func updateLeftTrigger(_ value: Float, pressed: Bool) {
        storage.lock.lock()
        storage.leftTrigger = value
        storage.lock.unlock()
        
        controllerQueue.async {
            self.handleButton(.leftTrigger, pressed: pressed)
        }
    }
    
    nonisolated private func updateRightTrigger(_ value: Float, pressed: Bool) {
        storage.lock.lock()
        storage.rightTrigger = value
        storage.lock.unlock()
        
        controllerQueue.async {
            self.handleButton(.rightTrigger, pressed: pressed)
        }
    }

    nonisolated private func handleButton(_ button: ControllerButton, pressed: Bool) {
        if pressed {
            buttonPressed(button)
        } else {
            buttonReleased(button)
        }
    }

    nonisolated internal func buttonPressed(_ button: ControllerButton) {
        storage.lock.lock()
        
        // Fast Double Tap Check
        if storage.capturedButtonsInWindow.contains(button) {
            storage.chordWorkItem?.cancel()
            storage.lock.unlock()
            processChordOrSinglePress()
            storage.lock.lock()
        }

        guard !storage.activeButtons.contains(button) else {
            storage.lock.unlock()
            return
        }

        storage.activeButtons.insert(button)
        storage.buttonPressTimestamps[button] = Date()
        storage.pendingButtons.insert(button)
        storage.capturedButtonsInWindow.insert(button)
        
        let uiButtons = storage.activeButtons
        
        // Chord Detection
        storage.chordWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.processChordOrSinglePress()
        }
        storage.chordWorkItem = workItem
        let window = storage.chordWindow
        storage.lock.unlock()
        
        Task { @MainActor in
            self.activeButtons = uiButtons
        }
        
        controllerQueue.asyncAfter(deadline: .now() + window, execute: workItem)
    }

    nonisolated internal func buttonReleased(_ button: ControllerButton) {
        storage.lock.lock()
        guard storage.activeButtons.contains(button) else {
            storage.lock.unlock()
            return
        }

        storage.activeButtons.remove(button)
        let pressTime = storage.buttonPressTimestamps.removeValue(forKey: button)
        let uiButtons = storage.activeButtons
        storage.lock.unlock()
        
        Task { @MainActor in
            self.activeButtons = uiButtons
        }
        
        let holdDuration: TimeInterval
        if let time = pressTime {
            holdDuration = Date().timeIntervalSince(time)
        } else {
            holdDuration = 0
        }

        storage.lock.lock()
        if storage.pendingButtons.contains(button) {
            storage.pendingReleases[button] = holdDuration
            storage.lock.unlock()
        } else {
            let callback = storage.onButtonReleased
            storage.lock.unlock()
            callback?(button, holdDuration)
        }
    }

    nonisolated private func processChordOrSinglePress() {
        storage.lock.lock()
        let captured = storage.capturedButtonsInWindow
        
        // Clear state
        storage.capturedButtonsInWindow.removeAll()
        storage.pendingButtons.removeAll()
        
        // Copy releases to process
        let releases = storage.pendingReleases
        storage.pendingReleases.removeAll()
        
        let chordCallback = storage.onChordDetected
        let pressCallback = storage.onButtonPressed
        let releaseCallback = storage.onButtonReleased
        
        storage.lock.unlock()

        if captured.count >= 2 {
            chordCallback?(captured)
        } else if let button = captured.first {
            pressCallback?(button)
        }
        
        for button in captured {
            if let duration = releases[button] {
                releaseCallback?(button, duration)
            }
        }
    }

    // MARK: - Haptic Feedback

    private func setupHaptics(for controller: GCController) {
        guard let haptics = controller.haptics else {
            return
        }

        // Try multiple localities - Xbox controllers may respond to different ones
        let localities: [GCHapticsLocality] = [.default, .handles, .leftHandle, .rightHandle, .leftTrigger, .rightTrigger]

        for locality in localities {
            if let engine = haptics.createEngine(withLocality: locality) {
                engine.resetHandler = { [weak engine] in
                    // Restart engine if it stops
                    try? engine?.start()
                }
                do {
                    try engine.start()
                    hapticEngines.append(engine)
                } catch {
                    // Engine startup failed, continue to next locality
                }
            }
        }
    }

    private func stopHaptics() {
        for engine in hapticEngines {
            engine.stop()
        }
        hapticEngines.removeAll()
    }

    /// Plays a haptic pulse on the controller
    /// - Parameters:
    ///   - intensity: Haptic intensity from 0.0 to 1.0
    ///   - duration: Duration in seconds
    nonisolated func playHaptic(intensity: Float = 0.5, sharpness: Float = 0.5, duration: TimeInterval = 0.1) {
        hapticQueue.async { [weak self] in
            guard let engines = self?.hapticEngines, !engines.isEmpty else { return }

            // Use continuous haptic for more noticeable feedback on game controllers
            do {
                let events = [
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                        ],
                        relativeTime: 0,
                        duration: duration
                    )
                ]
                let pattern = try CHHapticPattern(events: events, parameters: [])

                // Play on all available engines for maximum effect
                for engine in engines {
                    do {
                        let player = try engine.makePlayer(with: pattern)
                        try player.start(atTime: CHHapticTimeImmediate)
                    } catch {
                        // Try to restart engine and retry once
                        try? engine.start()
                        if let player = try? engine.makePlayer(with: pattern) {
                            try? player.start(atTime: CHHapticTimeImmediate)
                        }
                    }
                }
            } catch {
                // Haptic pattern error, continue silently
            }
        }
    }
}
