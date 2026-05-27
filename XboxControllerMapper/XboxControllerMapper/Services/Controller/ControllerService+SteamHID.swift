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

@MainActor
extension ControllerService {

    func setupSteamControllerHIDMonitoring() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        steamHIDManager = manager

        let ctx = SteamHIDCallbackContext(service: self)
        let retainedContext = Unmanaged.passRetained(ctx).toOpaque()
        steamHIDCallbackContext = retainedContext

        steamHIDSetupQueue.async {
            let matching = SteamControllerHIDParser.productIDs.flatMap { productID in
                SteamControllerHIDParser.acceptedVendorUsages.sorted().map { usage in
                    [
                        kIOHIDVendorIDKey as String: SteamControllerHIDParser.valveVendorID,
                        kIOHIDProductIDKey as String: productID,
                        kIOHIDDeviceUsagePageKey as String: SteamControllerHIDParser.vendorUsagePage,
                        kIOHIDDeviceUsageKey as String: usage,
                    ] as CFDictionary
                }
            }

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
        controller.onRightTouchpadChanged = { [weak self] x, y, isTouching in
            self?.updateTouchpad(x: x, y: y, isTouching: isTouching)
        }
        controller.onRightTouchpadClickChanged = { [weak self] pressed in
            self?.updateTouchpadClick(pressed: pressed)
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
            controllerDisconnected()
        }
    }

    func steamControllerActivated(_ controller: SteamControllerHIDController) {
        guard steamHIDControllers.contains(where: { $0 === controller }) else { return }
        guard !isConnected || steamHIDActiveDevice == controller.device else { return }

        genericHIDFallbackTimer?.cancel()
        genericHIDFallbackTimer = nil
        if genericHIDController != nil {
            genericHIDController?.stop()
            genericHIDController = nil
            isGenericController = false
        }

        steamHIDActiveDevice = controller.device
        connectedController = nil
        currentControllerIdentity = ControllerIdentityResolver.identity(
            for: controller.device,
            fallbackName: controller.deviceName
        )
        controllerName = controller.deviceName
        isConnected = true
        isGenericController = false

        detectConnectionType(device: controller.device)

        storage.lock.lock()
        resetTouchpadStateLocked()
        storage.isDualSense = false
        storage.isDualSenseEdge = false
        storage.isDualShock = false
        storage.isNintendo = false
        storage.isJoyConLeft = false
        storage.isJoyConRight = false
        storage.isXboxElite = true
        storage.isSteamController = true
        storage.elitePaddleEventSource = .none
        storage.lock.unlock()

        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)
        UserDefaults.standard.set(true, forKey: Config.lastControllerWasXboxEliteKey)
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
