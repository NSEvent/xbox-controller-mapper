import Foundation
import GameController
import Combine

// MARK: - Thread-Safe Input State (High Performance)

private final class ControllerStorage: @unchecked Sendable {
    let lock = NSLock()
    var leftStick: CGPoint = .zero
    var rightStick: CGPoint = .zero
    var leftTrigger: Float = 0
    var rightTrigger: Float = 0
    
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

    /// Left joystick position (-1 to 1) - UI/Legacy use only
    @Published var leftStick: CGPoint = .zero

    /// Right joystick position (-1 to 1) - UI/Legacy use only
    @Published var rightStick: CGPoint = .zero

    /// Left trigger pressure (0 to 1) - UI/Legacy use only
    @Published var leftTriggerValue: Float = 0

    /// Right trigger pressure (0 to 1) - UI/Legacy use only
    @Published var rightTriggerValue: Float = 0

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

    private var cancellables = Set<AnyCancellable>()
    
    // Low-level monitor for Xbox Guide button
    private let guideMonitor = XboxGuideMonitor()
    
    // Low-level monitor for Battery (Bluetooth Workaround for macOS/Xbox issue)
    private let batteryMonitor = BluetoothBatteryMonitor()

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
        GCController.startWirelessControllerDiscovery {
            print("Wireless controller discovery completed")
        }
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
        updateBatteryInfo()
        startDisplayUpdateTimer()

        print("Controller connected: \(controllerName)")
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
        
        storage.lock.lock()
        storage.activeButtons.removeAll()
        storage.buttonPressTimestamps.removeAll()
        storage.pendingButtons.removeAll()
        storage.capturedButtonsInWindow.removeAll()
        storage.pendingReleases.removeAll()
        storage.chordWorkItem?.cancel()
        storage.leftStick = .zero
        storage.rightStick = .zero
        storage.lock.unlock()

        print("Controller disconnected")
    }

    // MARK: - Display Update Timer

    private func startDisplayUpdateTimer() {
        stopDisplayUpdateTimer()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 15.0, leeway: .milliseconds(10))
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
            
            if abs(self.displayLeftStick.x - tsLeft.x) > 0.01 ||
               abs(self.displayLeftStick.y - tsLeft.y) > 0.01 {
                self.displayLeftStick = tsLeft
            }
            if abs(self.displayRightStick.x - tsRight.x) > 0.01 ||
               abs(self.displayRightStick.y - tsRight.y) > 0.01 {
                self.displayRightStick = tsRight
            }
            if abs(self.displayLeftTrigger - tsLeftTrig) > 0.01 {
                self.displayLeftTrigger = tsLeftTrig
            }
            if abs(self.displayRightTrigger - tsRightTrig) > 0.01 {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
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
}
