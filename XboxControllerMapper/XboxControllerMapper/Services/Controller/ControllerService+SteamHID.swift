import Combine
import Foundation
import GameController
import IOKit
import IOKit.hid

// MARK: - Steam Controller HID Monitoring

fileprivate final class SteamHIDCallbackContext {
    weak var service: ControllerService?
    init(service: ControllerService) { self.service = service }
}

private let steamHIDSetupQueue = DispatchQueue(label: "com.controllerkeys.steam-hid.setup", qos: .utility)
private let steamHIDRunLoop = SteamHIDRunLoop()
private let steamTrackpadCompatibilityOverride = SteamControllerTrackpadCompatibilityOverride()

private final class SteamHIDRunLoop: @unchecked Sendable {
    private let lock = NSLock()
    private var runLoop: CFRunLoop?

    func perform(_ work: @escaping @Sendable () -> Void) {
        let runLoop = startIfNeeded()
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }

    func performAndWait(_ work: @escaping @Sendable () -> Void) {
        let semaphore = DispatchSemaphore(value: 0)
        perform {
            work()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1.0)
    }

    private func startIfNeeded() -> CFRunLoop {
        lock.lock()
        if let runLoop {
            lock.unlock()
            return runLoop
        }

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            let currentRunLoop = CFRunLoopGetCurrent()
            var sourceContext = CFRunLoopSourceContext()
            if let keepAliveSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &sourceContext) {
                CFRunLoopAddSource(currentRunLoop, keepAliveSource, CFRunLoopMode.defaultMode)
            }
            self.lock.lock()
            self.runLoop = currentRunLoop
            self.lock.unlock()
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "ControllerKeys Steam HID"
        thread.qualityOfService = .userInteractive
        thread.start()
        lock.unlock()

        ready.wait()
        lock.lock()
        let currentRunLoop = runLoop!
        lock.unlock()
        return currentRunLoop
    }
}

private final class SteamControllerTrackpadCompatibilityOverride: @unchecked Sendable {
    private static let domain = "com.apple.AppleMultitouchTrackpad" as CFString
    private static let key = "USBMouseStopsTrackpad" as CFString
    private static let activateSettingsPath = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
    private static let legacyOverrideKeys = [
        "steamTrackpadCompatibilityOverrideActive",
        "steamTrackpadCompatibilityOriginalValue",
        "steamTrackpadCompatibilityHadOriginalValue"
    ]

    private let queue = DispatchQueue(label: "com.controllerkeys.steam-trackpad-compatibility", qos: .utility)

    func keepBuiltInTrackpadEnabled() {
        queue.async { self.keepBuiltInTrackpadEnabledLocked() }
    }

    private func keepBuiltInTrackpadEnabledLocked() {
        removeLegacyOverrideState()
        guard currentPreferenceValue() != false else { return }

        setPreferenceValue(false)
        activateTrackpadSettings()
        NSLog("[ControllerKeys] Steam Controller disabled macOS USBMouseStopsTrackpad")
    }

    private func removeLegacyOverrideState() {
        let defaults = UserDefaults.standard
        for key in Self.legacyOverrideKeys {
            if defaults.object(forKey: key) != nil {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func currentPreferenceValue() -> Bool? {
        guard let value = CFPreferencesCopyValue(
            Self.key,
            Self.domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) else {
            return nil
        }

        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean))
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private func setPreferenceValue(_ value: Bool) {
        CFPreferencesSetValue(
            Self.key,
            value ? kCFBooleanTrue : kCFBooleanFalse,
            Self.domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private func activateTrackpadSettings() {
        guard FileManager.default.isExecutableFile(atPath: Self.activateSettingsPath) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.activateSettingsPath)
        process.arguments = ["-u"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("[ControllerKeys] activateSettings failed after Steam Controller trackpad override: %@", "\(error)")
        }
    }
}

@MainActor
extension ControllerService {

    func setupSteamControllerHIDMonitoring() {
        steamTrackpadCompatibilityOverride.keepBuiltInTrackpadEnabled()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        steamHIDManager = manager

        let ctx = SteamHIDCallbackContext(service: self)
        let retainedContext = Unmanaged.passRetained(ctx).toOpaque()
        steamHIDCallbackContext = retainedContext

        steamHIDSetupQueue.async {
            let matching = SteamControllerHIDParser.matchingDictionaries()

            IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

            IOHIDManagerRegisterDeviceMatchingCallback(manager, steamHIDDeviceMatched, retainedContext)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, steamHIDDeviceRemoved, retainedContext)
            steamHIDRunLoop.perform {
                IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
                let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                if openResult != kIOReturnSuccess {
                    NSLog("[ControllerKeys] Steam Controller HID manager open returned 0x%08X", openResult)
                }

                if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
                    for device in devices {
                        steamHIDDeviceMatched(
                            context: retainedContext,
                            result: kIOReturnSuccess,
                            sender: nil,
                            device: device
                        )
                    }
                }
            }
        }
    }

    func cleanupSteamControllerHIDMonitoring() {
        stopSteamControllerHIDSessions()

        if let manager = steamHIDManager {
            steamHIDRunLoop.performAndWait {
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            }
        }
        steamHIDManager = nil

        if let ctx = steamHIDCallbackContext {
            Unmanaged<SteamHIDCallbackContext>.fromOpaque(ctx).release()
            steamHIDCallbackContext = nil
        }
    }

    func steamControllerDeviceAppeared(_ device: IOHIDDevice) {
        guard SteamControllerHIDController.supportsDevice(device) else { return }
        guard !steamHIDControllers.contains(where: { $0.device == device }) else { return }
        steamTrackpadCompatibilityOverride.keepBuiltInTrackpadEnabled()

        let controller = SteamControllerHIDController(device: device)
        controller.onActivated = { [weak self] controller in
            DispatchQueue.main.async {
                self?.steamControllerActivated(controller)
            }
        }
        controller.onButtonAction = { [weak self] button, pressed in
            self?.controllerQueue.async {
                self?.handleButton(button, pressed: pressed)
            }
        }
        controller.onLeftStickMoved = { [weak self] x, y in
            self?.updateLeftStick(x: x, y: y)
        }
        controller.onRightStickMoved = { [weak self] x, y in
            self?.updateRightStick(x: x, y: y)
        }
        controller.onLeftTriggerChanged = { [weak self] value, pressed in
            self?.updateLeftTrigger(value, pressed: pressed)
        }
        controller.onRightTriggerChanged = { [weak self] value, pressed in
            self?.updateRightTrigger(value, pressed: pressed)
        }
        controller.onLeftTouchpadChanged = { [weak self] x, y, isTouching in
            self?.updateSteamTouchpad(side: .left, x: x, y: y, isTouching: isTouching)
        }
        controller.onRightTouchpadChanged = { [weak self] x, y, isTouching in
            self?.updateSteamTouchpad(side: .right, x: x, y: y, isTouching: isTouching)
        }
        controller.onTouchpadClickChanged = { [weak self] side, state, pressed in
            self?.handleSteamTouchpadClick(side: side, state: state, pressed: pressed)
        }
        controller.onTouchpadTapAction = { [weak self] side, region in
            guard let self else { return }
            storage.lock.lock()
            let mode = storage.touchpadInputMode
            let callback = storage.onControllerButtonTap
            storage.lock.unlock()

            let button: ControllerButton?
            switch mode {
            case .wholePad:
                button = side.wholeTapButton
            case .quadrants:
                button = ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .touch)
            }
            if let button {
                callback?(button)
            }
        }
        controller.onBatteryChanged = { [weak self, weak controller] level, state in
            DispatchQueue.main.async { [weak self, weak controller] in
                guard let self,
                      let controller,
                      self.steamHIDActiveDevice == controller.device else { return }
                self.batteryLevel = level
                self.batteryState = state
            }
        }
        controller.onMotionChanged = { [weak self] motion in
            self?.processSteamMotion(motion)
        }

        steamHIDControllers.append(controller)
        steamHIDRunLoop.perform { [weak controller] in
            guard let controller else { return }
            controller.start()
            NSLog("[ControllerKeys] Steam Controller HID candidate started: %@", controller.deviceName)
        }
    }

    func steamControllerDeviceRemoved(_ device: IOHIDDevice) {
        guard let index = steamHIDControllers.firstIndex(where: { $0.device == device }) else { return }
        let controller = steamHIDControllers.remove(at: index)
        let wasActive = steamHIDActiveDevice == device
        steamHIDRunLoop.perform {
            controller.stop()
        }

        if wasActive {
            steamHIDActiveDevice = nil
            steamHIDControllerLock.lock()
            if activeSteamHIDController === controller {
                activeSteamHIDController = nil
            }
            steamHIDControllerLock.unlock()
            controllerDisconnected()
        }
    }

    func steamControllerActivated(_ controller: SteamControllerHIDController) {
        guard steamHIDControllers.contains(where: { $0 === controller }) else { return }
        guard steamHIDActiveDevice == nil || steamHIDActiveDevice == controller.device else { return }

        genericHIDFallbackTimer?.cancel()
        genericHIDFallbackTimer = nil
        if genericHIDController != nil {
            genericHIDController?.stop()
            genericHIDController = nil
            isGenericController = false
        }

        steamHIDActiveDevice = controller.device
        steamHIDControllerLock.lock()
        activeSteamHIDController = controller
        steamHIDControllerLock.unlock()
        if let gameController = connectedController {
            clearGameControllerHandlers(for: gameController)
        }
        connectedController = nil
        currentControllerIdentity = ControllerIdentityResolver.identity(
            for: controller.device,
            fallbackName: controller.deviceName
        )
        controllerName = controller.deviceName
        isGenericController = false

        detectConnectionType(device: controller.device)

        storage.lock.lock()
        resetMotionStateLocked()
        resetTouchpadStateLocked()
        storage.isDualSense = false
        storage.isDualSenseEdge = false
        storage.isDualShock = false
        storage.isNintendo = false
        storage.isJoyConLeft = false
        storage.isJoyConRight = false
        storage.isXboxElite = false
        storage.isSteamController = true
        storage.elitePaddleEventSource = .none
        storage.lock.unlock()

        isConnected = true

        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasXboxEliteKey)
        UserDefaults.standard.set(true, forKey: Config.lastControllerWasSteamControllerKey)

        batteryLevel = -1
        batteryState = .unknown
        startDisplayUpdateTimer()

        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }

        NSLog("[ControllerKeys] Steam Controller connected via raw HID: %@", controller.deviceName)
    }

    func stopSteamControllerHIDSessions() {
        let controllers = steamHIDControllers
        steamHIDRunLoop.performAndWait {
            controllers.forEach { $0.stop() }
        }
        steamHIDControllers.removeAll()
        steamHIDActiveDevice = nil
        steamHIDControllerLock.lock()
        activeSteamHIDController = nil
        steamHIDControllerLock.unlock()
    }

    nonisolated func updateSteamTouchpad(
        side: SteamTouchpadSide,
        x: Float,
        y: Float,
        isTouching: Bool
    ) {
        updateSteamTouchpadDisplay(side: side, x: x, y: y, isTouching: isTouching)

        let virtualPosition = steamTouchpadVirtualPosition(side: side, x: x, y: y, isTouching: isTouching)
        switch side {
        case .left:
            updateTouchpadSecondary(
                x: Float(virtualPosition.x),
                y: Float(virtualPosition.y),
                isTouching: isTouching
            )
        case .right:
            refreshSteamSecondaryTouchIfNeeded()
            updateTouchpad(
                x: Float(virtualPosition.x),
                y: Float(virtualPosition.y),
                isTouching: isTouching
            )
        }
    }

    private nonisolated func updateSteamTouchpadDisplay(
        side: SteamTouchpadSide,
        x: Float,
        y: Float,
        isTouching: Bool
    ) {
        storage.lock.lock()
        let position = isTouching ? CGPoint(x: CGFloat(x), y: CGFloat(y)) : .zero
        switch side {
        case .left:
            storage.steamLeftTouchpadPosition = position
            storage.isSteamLeftTouchpadTouching = isTouching
        case .right:
            storage.steamRightTouchpadPosition = position
            storage.isSteamRightTouchpadTouching = isTouching
        }
        storage.lock.unlock()
    }

    private nonisolated func refreshSteamSecondaryTouchIfNeeded() {
        storage.lock.lock()
        if storage.isSteamLeftTouchpadTouching && storage.isTouchpadSecondaryTouching {
            let now = CFAbsoluteTimeGetCurrent()
            storage.touchpadSecondaryLastTouchTime = now
        }
        storage.lock.unlock()
    }

    private nonisolated func steamTouchpadVirtualPosition(
        side: SteamTouchpadSide,
        x: Float,
        y: Float,
        isTouching: Bool
    ) -> CGPoint {
        guard isTouching else { return .zero }
        let centerOffset: CGFloat = 1.35
        let sideOffset = side == .left ? -centerOffset : centerOffset
        return CGPoint(x: sideOffset + CGFloat(x), y: CGFloat(y))
    }

    nonisolated func handleSteamTouchpadClick(
        side: SteamTouchpadSide,
        state: SteamControllerTouchpadState,
        pressed: Bool
    ) {
        updateSteamTouchpadClickMovementGate(side: side, state: state, pressed: pressed)
        if pressed {
            playSteamTouchpadHaptic(
                side: side,
                intensity: Config.steamTouchpadClickHapticIntensity,
                sharpness: Config.steamTouchpadClickHapticSharpness,
                duration: Config.steamTouchpadClickHapticDuration,
                transient: false
            )
        }

        let position = CGPoint(x: CGFloat(state.x), y: CGFloat(state.y))
        var buttonToDispatch: ControllerButton?

        storage.lock.lock()
        let mode = storage.touchpadInputMode
        switch mode {
        case .wholePad:
            buttonToDispatch = side.wholeClickButton
        case .quadrants:
            switch side {
            case .left:
                if pressed {
                    if ControllerService.shouldFireRegionClick(
                        willBeTwoFingerClick: false,
                        clickPosition: position,
                        isCurrentlyTouching: state.isTouching,
                        requireActiveTouch: storage.requireActiveTouchForRegionClick
                    ) {
                        let region = TouchpadRegion.from(position: position)
                        let button = ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .click)
                        storage.activeSteamLeftTouchpadClickQuadrant = button
                        buttonToDispatch = button
                    }
                } else {
                    buttonToDispatch = storage.activeSteamLeftTouchpadClickQuadrant
                    storage.activeSteamLeftTouchpadClickQuadrant = nil
                }
            case .right:
                if pressed {
                    if ControllerService.shouldFireRegionClick(
                        willBeTwoFingerClick: false,
                        clickPosition: position,
                        isCurrentlyTouching: state.isTouching,
                        requireActiveTouch: storage.requireActiveTouchForRegionClick
                    ) {
                        let region = TouchpadRegion.from(position: position)
                        let button = ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .click)
                        storage.activeSteamRightTouchpadClickQuadrant = button
                        buttonToDispatch = button
                    }
                } else {
                    buttonToDispatch = storage.activeSteamRightTouchpadClickQuadrant
                    storage.activeSteamRightTouchpadClickQuadrant = nil
                }
            }
        }
        storage.lock.unlock()

        guard let buttonToDispatch else { return }
        controllerQueue.async { [weak self] in
            self?.handleButton(buttonToDispatch, pressed: pressed)
        }
    }

    private nonisolated func updateSteamTouchpadClickMovementGate(
        side: SteamTouchpadSide,
        state: SteamControllerTouchpadState,
        pressed: Bool
    ) {
        guard side == .right else { return }
        storage.lock.lock()
        if pressed {
            let position = steamTouchpadVirtualPosition(
                side: side,
                x: state.x,
                y: state.y,
                isTouching: true
            )
            storage.touchpadClickArmed = true
            storage.touchpadClickStartPosition = position
            storage.touchpadClickFiredDuringTouch = true
            storage.pendingTouchpadDelta = nil
            storage.touchpadFramesSinceTouch = 0
        } else {
            storage.touchpadClickArmed = false
        }
        storage.lock.unlock()
    }
}

private nonisolated func steamHIDDeviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard result == kIOReturnSuccess, let context else { return }
    let holder = Unmanaged<SteamHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
    guard let service = holder.service else { return }
    DispatchQueue.main.async {
        service.steamControllerDeviceAppeared(device)
    }
}

private nonisolated func steamHIDDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard result == kIOReturnSuccess, let context else { return }
    let holder = Unmanaged<SteamHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
    guard let service = holder.service else { return }
    DispatchQueue.main.async {
        service.steamControllerDeviceRemoved(device)
    }
}
