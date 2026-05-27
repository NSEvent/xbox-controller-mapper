import Foundation
import GameController
import IOKit
import IOKit.hid

// MARK: - PlayStation HID Monitoring (PS button, mic, Edge paddles)

/// Weak callback context for the PlayStation HID input report callback.
/// Prevents use-after-free when ControllerService is deallocated while a
/// pending HID callback fires on the run loop.
fileprivate final class PSHIDCallbackContext {
    weak var service: ControllerService?
    init(service: ControllerService) { self.service = service }
}

struct PlayStationHIDRegistration {
    let device: IOHIDDevice
    let reportBuffer: UnsafeMutablePointer<UInt8>
    let callbackContext: UnsafeMutableRawPointer
}

private enum PlayStationHIDProduct {
    static let sonyVendorId = 0x054C
    static let dualSense = 0x0CE6
    static let dualSenseEdge = 0x0DF2
    static let dualShock4V1 = 0x05C4
    static let dualShock4V2 = 0x09CC

    static let dualSenseFamily: Set<Int> = [dualSense, dualSenseEdge]
    static let dualShock4Family: Set<Int> = [dualShock4V1, dualShock4V2]
    static let all: Set<Int> = dualSenseFamily.union(dualShock4Family)

    static func matchingDictionary(productId: Int) -> [String: Any] {
        [
            kIOHIDVendorIDKey as String: sonyVendorId,
            kIOHIDProductIDKey as String: productId,
        ]
    }
}

@MainActor
extension ControllerService {

    /// Size of the HID input report buffer. Used for both allocation and callback registration.
    private static let hidReportBufferSize = 100

    func setupPlayStationHIDMonitoring() {
        // Guard: if already monitoring, clean up first to avoid leaking the old manager/buffer/context.
        // This handles rapid controllerConnected() calls safely.
        if hidManager != nil || !psHIDRegistrations.isEmpty {
            cleanupHIDMonitoring()
        }

        // Create HID manager
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else { return }

        // Match all PlayStation controllers, then narrow to the active
        // GameController model before binding identity or raw HID callbacks.
        let matchingDicts = PlayStationHIDProduct.all
            .map { PlayStationHIDProduct.matchingDictionary(productId: $0) } as CFArray
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts)

        // Schedule with run loop first
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        let allDevices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>).map(Array.init) ?? []
        let fallbackName = connectedController?.vendorName ?? connectedController?.productCategory
        let allIdentities = allDevices.map {
            ControllerIdentityResolver.identity(for: $0, fallbackName: fallbackName)
        }
        let activeProductIds = activePlayStationProductIds()
        let candidates = ControllerIdentityResolver.candidatesMatchingProductIds(
            devices: allDevices,
            identities: allIdentities,
            productIds: activeProductIds
        )
        let devices = candidates.devices
        let identities = candidates.identities
        let callbackDevices = ControllerIdentityResolver.devicesForSinglePhysicalIdentity(
            devices: devices,
            identities: identities
        )

        if allDevices.count != devices.count {
            NSLog("[ControllerKeys] Ignoring %d non-active PlayStation HID device(s) while resolving current controller identity", allDevices.count - devices.count)
        }

        if let device = callbackDevices.first {
            hidDevice = device
        } else {
            hidDevice = nil
            if devices.count > 1 {
                NSLog("[ControllerKeys] Multiple PlayStation HID identities found; disabling PlayStation HID-only buttons until one physical controller is available")
            }
        }

        if let controller = connectedController {
            if identities.isEmpty {
                currentControllerIdentity = fallbackPlayStationIdentity(
                    for: controller,
                    productIds: activeProductIds
                )
            } else {
                currentControllerIdentity = ControllerIdentityResolver.resolvedIdentity(
                    candidates: identities,
                    fallbackName: controller.vendorName ?? controller.productCategory
                )
            }
        }

        // Device-specific HID reports are safe only when all matching HID
        // interfaces resolve to one physical controller.
        for device in callbackDevices {
            setupHIDDeviceCallback(device)
        }
    }

    func setupHIDDeviceCallback(_ device: IOHIDDevice) {
        detectConnectionType(device: device)

        // DualSense-specific detection
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
        let isDualSenseDevice = (productID == 0x0CE6 || productID == 0x0DF2)

        if isDualSenseDevice {
            detectDualSenseEdge(device: device)
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.hidReportBufferSize)
        let ctx = PSHIDCallbackContext(service: self)
        let retainedContext = Unmanaged.passRetained(ctx).toOpaque()
        psHIDRegistrations.append(
            PlayStationHIDRegistration(
                device: device,
                reportBuffer: buffer,
                callbackContext: retainedContext
            )
        )
        IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.hidReportBufferSize, { context, result, sender, type, reportID, report, reportLength in
            guard let context = context else { return }
            let holder = Unmanaged<PSHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
            guard let service = holder.service else { return }
            service.handleHIDReport(reportID: reportID, report: report, length: Int(reportLength))
        }, retainedContext)

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Enable microphone when connected via USB (DualSense only)
        if isDualSenseDevice {
            storage.lock.lock()
            let isBluetooth = storage.isBluetoothConnection
            storage.lock.unlock()
            if !isBluetooth {
                enableMicrophone(device: device)
            }
        }
    }

    private func activePlayStationProductIds() -> Set<Int> {
        storage.lock.lock()
        let isDualSense = storage.isDualSense
        let isDualShock = storage.isDualShock
        storage.lock.unlock()

        if isDualSense {
            return PlayStationHIDProduct.dualSenseFamily
        }
        if isDualShock {
            return PlayStationHIDProduct.dualShock4Family
        }
        return PlayStationHIDProduct.all
    }

    private func fallbackPlayStationIdentity(
        for controller: GCController,
        productIds: Set<Int>
    ) -> ControllerIdentity {
        let fallbackName = controller.vendorName ?? controller.productCategory
        let lowercasedName = fallbackName.lowercased()
        let productId: Int?
        if lowercasedName.contains("edge") {
            productId = PlayStationHIDProduct.dualSenseEdge
        } else if productIds == PlayStationHIDProduct.dualSenseFamily {
            productId = PlayStationHIDProduct.dualSense
        } else if productIds.count == 1 {
            productId = productIds.first
        } else {
            productId = nil
        }

        return ControllerIdentityResolver.fallbackIdentity(
            vendorId: PlayStationHIDProduct.sonyVendorId,
            productId: productId,
            productName: fallbackName,
            transport: nil
        )
    }

    func cleanupHIDMonitoring() {
        // ORDERING IS CRITICAL for memory safety:
        //   1. Unregister input report callbacks (register nil) — stops IOKit from invoking
        //      the callback, which references both the context pointer and the report buffer.
        //   2. Unschedule devices from the run loop — prevents any queued events from firing.
        //   3. Close the HID manager and unschedule it.
        //   4. Release callback contexts (passRetained balanced by release).
        //   5. Deallocate report buffers — safe now because no callback can reference them.
        //
        // Violating this order can cause use-after-free: IOKit does NOT retain the buffer
        // or context, so they must outlive all possible callback invocations.

        // Step 1: Unregister callbacks by passing nil — IOKit will no longer invoke our closure.
        for registration in psHIDRegistrations {
            IOHIDDeviceRegisterInputReportCallback(
                registration.device,
                registration.reportBuffer,
                Self.hidReportBufferSize,
                nil,
                nil
            )
        }

        // Step 2: Unschedule devices from run loop.
        for registration in psHIDRegistrations {
            IOHIDDeviceUnscheduleFromRunLoop(
                registration.device,
                CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue
            )
        }
        hidDevice = nil

        // Step 3: Close and unschedule HID manager.
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        hidManager = nil

        // Steps 4/5: Release callback contexts and report buffers.
        for registration in psHIDRegistrations {
            Unmanaged<PSHIDCallbackContext>.fromOpaque(registration.callbackContext).release()
            registration.reportBuffer.deallocate()
        }
        psHIDRegistrations.removeAll()
    }

    nonisolated func handleHIDReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        storage.lock.lock()
        let isDualShockController = storage.isDualShock
        storage.lastInputTime = CFAbsoluteTimeGetCurrent()
        storage.lock.unlock()

        // DS4 reports also carry gyroscope data — parse motion before delegating
        // button/battery extraction to the report parser. Motion has its own
        // stateful pipeline (gyro-bias calibration) so it stays handler-side.
        if isDualShockController {
            if reportID == 0x11 && length >= 10 {
                parseDualShock4Motion(report: report, length: length, isBluetooth: true)
            } else if reportID == 0x01 && length >= 8 {
                parseDualShock4Motion(report: report, length: length, isBluetooth: false)
            }
        }

        let parser: HIDReportParser = isDualShockController ? DualShockHIDParser() : DualSenseHIDParser()
        guard let parsed = parser.parse(reportID: reportID, report: UnsafePointer(report), length: length) else { return }

        applyParsedHIDReport(parsed)
    }

    /// Diff parsed HID button state against `storage.last*`, write back the
    /// new values, and dispatch state-change events. Battery transitions
    /// trigger a main-thread `updateBatteryInfo()`.
    nonisolated private func applyParsedHIDReport(_ parsed: HIDReportParseResult) {
        storage.lock.lock()
        let isEdge = storage.isDualSenseEdge

        let psChanged = parsed.ps.map { $0 != storage.lastPSButtonState } ?? false
        let micChanged = parsed.mic.map { $0 != storage.lastMicButtonState } ?? false
        let leftFnChanged = parsed.edgeLeftFunction.map { $0 != storage.lastLeftFunctionState } ?? false
        let rightFnChanged = parsed.edgeRightFunction.map { $0 != storage.lastRightFunctionState } ?? false
        let leftPaddleChanged = parsed.edgeLeftPaddle.map { $0 != storage.lastLeftPaddleState } ?? false
        let rightPaddleChanged = parsed.edgeRightPaddle.map { $0 != storage.lastRightPaddleState } ?? false

        if let ps = parsed.ps, psChanged { storage.lastPSButtonState = ps }
        if let mic = parsed.mic, micChanged { storage.lastMicButtonState = mic }
        if let lf = parsed.edgeLeftFunction, leftFnChanged { storage.lastLeftFunctionState = lf }
        if let rf = parsed.edgeRightFunction, rightFnChanged { storage.lastRightFunctionState = rf }
        if let lp = parsed.edgeLeftPaddle, leftPaddleChanged { storage.lastLeftPaddleState = lp }
        if let rp = parsed.edgeRightPaddle, rightPaddleChanged { storage.lastRightPaddleState = rp }

        let previousCharging = storage.lastHIDBatteryCharging
        if let charging = parsed.batteryCharging {
            storage.lastHIDBatteryCharging = charging
        }
        storage.lock.unlock()

        if let ps = parsed.ps, psChanged {
            controllerQueue.async { [weak self] in
                self?.handleButton(.xbox, pressed: ps)
            }
        }
        if let mic = parsed.mic, micChanged {
            controllerQueue.async { [weak self] in
                self?.handleButton(.micMute, pressed: mic)
            }
        }

        // Edge buttons fire only on Edge controllers (the parser still extracts
        // the bits on non-Edge DualSense, but suppressing here matches the
        // original behavior bit-for-bit).
        if isEdge {
            if let lf = parsed.edgeLeftFunction, leftFnChanged {
                controllerQueue.async { [weak self] in self?.handleButton(.leftFunction, pressed: lf) }
            }
            if let rf = parsed.edgeRightFunction, rightFnChanged {
                controllerQueue.async { [weak self] in self?.handleButton(.rightFunction, pressed: rf) }
            }
            if let lp = parsed.edgeLeftPaddle, leftPaddleChanged {
                controllerQueue.async { [weak self] in self?.handleButton(.leftPaddle, pressed: lp) }
            }
            if let rp = parsed.edgeRightPaddle, rightPaddleChanged {
                controllerQueue.async { [weak self] in self?.handleButton(.rightPaddle, pressed: rp) }
            }
        }

        if let charging = parsed.batteryCharging, previousCharging != nil, previousCharging != charging {
            DispatchQueue.main.async { [weak self] in
                self?.updateBatteryInfo()
            }
        }
    }

    /// Parses gyroscope data from DS4 HID input reports. macOS's GameController
    /// framework exposes GCMotion for DS4 but the rotationRate values are always
    /// (0, 0, 0). The DS4 hardware does have a gyro — the values are in the raw
    /// HID report at the same offsets used by the Linux hid-playstation driver.
    ///
    /// Common-struct layout (32 bytes): bytes 12-13 = gyro X (LE16 signed),
    /// bytes 14-15 = gyro Y, bytes 16-17 = gyro Z. The common struct sits at
    /// offset 1 in USB report 0x01 (after the stripped report ID) and offset 3
    /// in BT report 0x11 (after stripped ID + 2-byte BT header).
    nonisolated func parseDualShock4Motion(
        report: UnsafeMutablePointer<UInt8>,
        length: Int,
        isBluetooth: Bool
    ) {
        let commonOffset = isBluetooth ? 3 : 1
        let gyroXOffset = commonOffset + 12
        let gyroYOffset = commonOffset + 14
        guard gyroYOffset + 1 < length else { return }

        // Per Linux hid-playstation, gyro is signed LE16, ~1024 LSB per rad/s.
        // Empirical mapping for DS4 (different from DualSense's GCMotion axes):
        //   gyro X = pitch (tilt forward/back) — matches DualSense rotationRate.x
        //   gyro Y = yaw   (steer left/right)  — DualSense uses rotationRate.z
        //                                        for the same gesture, but DS4
        //                                        gyro Y already matches the
        //                                        sign convention (positive = right).
        // Discovered by capturing the highest-amplitude axis during a controlled
        // steering motion; gyro Y produced ~2× the signal of gyro Z.
        let gyroX = signedLE16(report, gyroXOffset)
        let gyroY = signedLE16(report, gyroYOffset)
        let scale: Double = 1.0 / 1024.0
        let rawPitch = Double(gyroX) * scale
        let rawRoll = Double(gyroY) * scale

        let shouldProcessMotion = storage.lock.withLock { storage.motionInputEnabled }
        guard shouldProcessMotion else { return }

        // Auto-calibrate gyro bias: average the first ~60 frames after motion
        // enable (assumes the user lays the controller still on startup) and
        // then subtract that bias from every subsequent reading. Without this,
        // hardware drift biases tilts asymmetrically — one direction feels
        // stronger than the other.
        let biasCalibrationFrames = 60
        let (pitch, roll): (Double, Double) = storage.lock.withLock {
            if storage.ds4GyroBiasSampleCount < biasCalibrationFrames {
                storage.ds4GyroPitchBiasSum += rawPitch
                storage.ds4GyroRollBiasSum += rawRoll
                storage.ds4GyroBiasSampleCount += 1
                if storage.ds4GyroBiasSampleCount == biasCalibrationFrames {
                    storage.ds4GyroPitchBias = storage.ds4GyroPitchBiasSum / Double(biasCalibrationFrames)
                    storage.ds4GyroRollBias = storage.ds4GyroRollBiasSum / Double(biasCalibrationFrames)
                }
                // Don't feed motion through the pipeline during calibration.
                return (0, 0)
            }
            return (rawPitch - storage.ds4GyroPitchBias, rawRoll - storage.ds4GyroRollBias)
        }
        if pitch == 0 && roll == 0 { return }

        storage.lock.lock()
        storage.motionPitchAccum += pitch
        storage.motionRollAccum += roll
        storage.motionSampleCount += 1
        storage.lock.unlock()

        processMotionUpdate(pitchVelocity: pitch, rollVelocity: roll)
    }

    /// Reads a little-endian signed 16-bit integer from a byte array.
    nonisolated private func signedLE16(_ buffer: UnsafeMutablePointer<UInt8>, _ offset: Int) -> Int16 {
        let lo = UInt16(buffer[offset])
        let hi = UInt16(buffer[offset + 1])
        return Int16(bitPattern: lo | (hi << 8))
    }
}
