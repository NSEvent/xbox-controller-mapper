import Foundation
import CoreGraphics
import GameController
import IOKit
import IOKit.hid

struct SteamControllerInputReport: Equatable {
    let reportID: UInt8
    let sequence: UInt8
    let buttons: UInt32
    let leftTrigger: Float
    let rightTrigger: Float
    let leftStickX: Float
    let leftStickY: Float
    let rightStickX: Float
    let rightStickY: Float
    let leftPadX: Int16
    let leftPadY: Int16
    let leftPadPressure: UInt16
    let rightPadX: Int16
    let rightPadY: Int16
    let rightPadPressure: UInt16
    let motion: SteamControllerMotionReport?
}

struct SteamControllerMotionReport: Equatable, Sendable {
    let timestamp: UInt32
    let accelX: Int16
    let accelY: Int16
    let accelZ: Int16
    let gyroX: Int16
    let gyroY: Int16
    let gyroZ: Int16
}

struct SteamControllerBatteryReport: Equatable {
    let reportID: UInt8
    let chargeState: UInt8
    let level: Float
    let state: GCDeviceBattery.State
}

struct SteamControllerTouchpadState: Equatable, Sendable {
    let x: Float
    let y: Float
    let isTouching: Bool
    let isPressed: Bool
}

struct SteamControllerTouchpadTapTracker {
    private var wasTouching = false
    private var touchStartTime: TimeInterval = 0
    private var touchStartPosition = CGPoint.zero
    private var lastTouchPosition = CGPoint.zero
    private var maxDistanceFromStart: Double = 0
    private var clickFiredDuringTouch = false

    mutating func markClickFired() {
        clickFiredDuringTouch = true
    }

    mutating func update(
        state: SteamControllerTouchpadState,
        now: TimeInterval,
        onTap: (TouchpadRegion) -> Void
    ) {
        let position = CGPoint(x: CGFloat(state.x), y: CGFloat(state.y))
        if state.isPressed {
            clickFiredDuringTouch = true
        }

        if state.isTouching {
            if !wasTouching {
                touchStartTime = now
                touchStartPosition = position
                lastTouchPosition = position
                maxDistanceFromStart = 0
                clickFiredDuringTouch = state.isPressed
            } else {
                lastTouchPosition = position
                maxDistanceFromStart = max(
                    maxDistanceFromStart,
                    hypot(Double(position.x - touchStartPosition.x), Double(position.y - touchStartPosition.y))
                )
            }
            wasTouching = true
            return
        }

        guard wasTouching else { return }

        let duration = now - touchStartTime
        if !clickFiredDuringTouch,
           duration < Config.touchpadTapMaxDuration,
           maxDistanceFromStart < Config.touchpadTapMaxMovement {
            onTap(TouchpadRegion.from(position: lastTouchPosition))
        }

        wasTouching = false
        touchStartTime = 0
        touchStartPosition = .zero
        lastTouchPosition = .zero
        maxDistanceFromStart = 0
        clickFiredDuringTouch = false
    }
}

struct SteamControllerTouchpadTapGate {
    private var leftPendingTap: (region: TouchpadRegion, deadline: TimeInterval)?
    private var rightPendingTap: (region: TouchpadRegion, deadline: TimeInterval)?

    mutating func queue(side: SteamTouchpadSide, region: TouchpadRegion, now: TimeInterval) {
        let pending = (region: region, deadline: now + Config.steamTouchpadTapClickSuppressionWindow)
        switch side {
        case .left:
            leftPendingTap = pending
        case .right:
            rightPendingTap = pending
        }
    }

    mutating func cancel(side: SteamTouchpadSide) {
        switch side {
        case .left:
            leftPendingTap = nil
        case .right:
            rightPendingTap = nil
        }
    }

    mutating func flush(now: TimeInterval) -> [(SteamTouchpadSide, TouchpadRegion)] {
        var taps: [(SteamTouchpadSide, TouchpadRegion)] = []
        if let pending = leftPendingTap, now >= pending.deadline {
            taps.append((.left, pending.region))
            leftPendingTap = nil
        }
        if let pending = rightPendingTap, now >= pending.deadline {
            taps.append((.right, pending.region))
            rightPendingTap = nil
        }
        return taps
    }
}

struct SteamControllerTouchpadMovementHapticTracker {
    private var wasTouching = false
    private var lastPosition = CGPoint.zero
    private var lastTickPosition = CGPoint.zero
    private var lastTickTime: TimeInterval = 0

    mutating func update(state: SteamControllerTouchpadState, now: TimeInterval) -> Bool {
        let position = CGPoint(x: CGFloat(state.x), y: CGFloat(state.y))
        guard state.isTouching else {
            wasTouching = false
            lastPosition = .zero
            lastTickPosition = .zero
            return false
        }

        guard wasTouching else {
            wasTouching = true
            lastPosition = position
            lastTickPosition = position
            return false
        }

        guard !state.isPressed else {
            lastPosition = position
            lastTickPosition = position
            return false
        }

        let sampleDistance = hypot(Double(position.x - lastPosition.x), Double(position.y - lastPosition.y))
        guard sampleDistance < 0.3 else {
            lastPosition = position
            lastTickPosition = position
            return false
        }

        guard sampleDistance >= Config.steamTouchpadMovementHapticSampleDeadzone else {
            return false
        }

        lastPosition = position

        let tickDistance = hypot(
            Double(position.x - lastTickPosition.x),
            Double(position.y - lastTickPosition.y)
        )
        guard tickDistance >= Config.steamTouchpadMovementHapticDistanceStep,
              now - lastTickTime >= Config.steamTouchpadMovementHapticMinInterval else {
            return false
        }

        lastTickPosition = position
        lastTickTime = now
        return true
    }
}

private struct SteamControllerPendingTouchpadClickRelease {
    let state: SteamControllerTouchpadState
    let deadline: TimeInterval
}

enum SteamControllerButtonMask {
    static let a: UInt32 = 0x00000001
    static let b: UInt32 = 0x00000002
    static let x: UInt32 = 0x00000004
    static let y: UInt32 = 0x00000008
    static let qam: UInt32 = 0x00000010
    static let rightThumbstick: UInt32 = 0x00000020
    static let menu: UInt32 = 0x00000040
    static let rightUpperGrip: UInt32 = 0x00000080
    static let rightLowerGrip: UInt32 = 0x00000100
    static let rightBumper: UInt32 = 0x00000200
    static let dpadDown: UInt32 = 0x00000400
    static let dpadRight: UInt32 = 0x00000800
    static let dpadLeft: UInt32 = 0x00001000
    static let dpadUp: UInt32 = 0x00002000
    static let view: UInt32 = 0x00004000
    static let leftThumbstick: UInt32 = 0x00008000
    static let steam: UInt32 = 0x00010000
    static let leftUpperGrip: UInt32 = 0x00020000
    static let leftLowerGrip: UInt32 = 0x00040000
    static let leftBumper: UInt32 = 0x00080000
    static let rightPadTouch: UInt32 = 0x00200000
    static let rightPadClick: UInt32 = 0x00400000
    static let rightTriggerClick: UInt32 = 0x00800000
    static let leftPadTouch: UInt32 = 0x02000000
    static let leftPadClick: UInt32 = 0x04000000
    static let leftTriggerClick: UInt32 = 0x08000000
}

struct SteamControllerHIDParser {
    static let wiredProductID = 0x1302
    static let puckProductID = 0x1304
    static let productIDs = [wiredProductID, puckProductID]
    static let valveVendorID = 0x28DE
    static let vendorUsagePage = 0xFF00
    static let vendorDataUsage = 0x0001
    static let vendorCommandUsage = 0x0002
    static let acceptedVendorUsages: Set<Int> = [vendorDataUsage, vendorCommandUsage]
    static let acceptedInputReportIDs: Set<UInt8> = [0x42, 0x45]
    static let batteryReportID: UInt8 = 0x43

    func parse(reportID: UInt32, report: UnsafePointer<UInt8>, length: Int) -> SteamControllerInputReport? {
        guard let id = UInt8(exactly: reportID),
              Self.acceptedInputReportIDs.contains(id) else { return nil }

        let offset = length > 0 && report[0] == id ? 1 : 0
        let payloadLength = length - offset
        guard payloadLength >= 29 else { return nil }

        let sequence = report[offset]
        let buttons = Self.uint32LE(report, offset + 1)
        let leftTrigger = Self.triggerValue(Self.int16LE(report, offset + 5))
        let rightTrigger = Self.triggerValue(Self.int16LE(report, offset + 7))
        let leftStickX = Self.axisValue(Self.int16LE(report, offset + 9))
        let leftStickY = Self.axisValue(Self.int16LE(report, offset + 11))
        let rightStickX = Self.axisValue(Self.int16LE(report, offset + 13))
        let rightStickY = Self.axisValue(Self.int16LE(report, offset + 15))
        let leftPadX = Self.int16LE(report, offset + 17)
        let leftPadY = Self.int16LE(report, offset + 19)
        let leftPadPressure = Self.uint16LE(report, offset + 21)
        let rightPadX = Self.int16LE(report, offset + 23)
        let rightPadY = Self.int16LE(report, offset + 25)
        let rightPadPressure = Self.uint16LE(report, offset + 27)
        let motion: SteamControllerMotionReport?
        if payloadLength >= 45 {
            motion = SteamControllerMotionReport(
                timestamp: Self.uint32LE(report, offset + 29),
                accelX: Self.int16LE(report, offset + 33),
                accelY: Self.int16LE(report, offset + 35),
                accelZ: Self.int16LE(report, offset + 37),
                gyroX: Self.int16LE(report, offset + 39),
                gyroY: Self.int16LE(report, offset + 41),
                gyroZ: Self.int16LE(report, offset + 43)
            )
        } else {
            motion = nil
        }

        return SteamControllerInputReport(
            reportID: id,
            sequence: sequence,
            buttons: buttons,
            leftTrigger: leftTrigger,
            rightTrigger: rightTrigger,
            leftStickX: leftStickX,
            leftStickY: leftStickY,
            rightStickX: rightStickX,
            rightStickY: rightStickY,
            leftPadX: leftPadX,
            leftPadY: leftPadY,
            leftPadPressure: leftPadPressure,
            rightPadX: rightPadX,
            rightPadY: rightPadY,
            rightPadPressure: rightPadPressure,
            motion: motion
        )
    }

    func parseBattery(reportID: UInt32, report: UnsafePointer<UInt8>, length: Int) -> SteamControllerBatteryReport? {
        guard let id = UInt8(exactly: reportID),
              id == Self.batteryReportID else { return nil }

        let offset = length > 0 && report[0] == id ? 1 : 0
        let payloadLength = length - offset
        guard payloadLength >= 14 else { return nil }

        let chargeState = report[offset]
        let batteryPercent = min(100, max(0, Int(report[offset + 1])))
        return SteamControllerBatteryReport(
            reportID: id,
            chargeState: chargeState,
            level: Float(batteryPercent) / 100.0,
            state: Self.batteryState(chargeState: chargeState)
        )
    }

    private static func axisValue(_ raw: Int16) -> Float {
        max(-1.0, min(1.0, Float(raw) / 32767.0))
    }

    private static func triggerValue(_ raw: Int16) -> Float {
        max(0.0, min(1.0, Float(max(Int(raw), 0)) / 32767.0))
    }

    private static func uint16LE(_ report: UnsafePointer<UInt8>, _ offset: Int) -> UInt16 {
        UInt16(report[offset]) | (UInt16(report[offset + 1]) << 8)
    }

    private static func int16LE(_ report: UnsafePointer<UInt8>, _ offset: Int) -> Int16 {
        Int16(bitPattern: uint16LE(report, offset))
    }

    private static func uint32LE(_ report: UnsafePointer<UInt8>, _ offset: Int) -> UInt32 {
        UInt32(report[offset])
            | (UInt32(report[offset + 1]) << 8)
            | (UInt32(report[offset + 2]) << 16)
            | (UInt32(report[offset + 3]) << 24)
    }

    private static func batteryState(chargeState: UInt8) -> GCDeviceBattery.State {
        switch chargeState {
        case 1:
            return .discharging
        case 2:
            return .charging
        case 4:
            return .full
        default:
            return .unknown
        }
    }
}

final class SteamControllerHIDController {
    let device: IOHIDDevice
    let deviceName: String

    var onActivated: ((SteamControllerHIDController) -> Void)?
    var onButtonAction: ((ControllerButton, Bool) -> Void)?
    var onLeftStickMoved: ((Float, Float) -> Void)?
    var onRightStickMoved: ((Float, Float) -> Void)?
    var onLeftTriggerChanged: ((Float, Bool) -> Void)?
    var onRightTriggerChanged: ((Float, Bool) -> Void)?
    var onLeftTouchpadChanged: ((Float, Float, Bool) -> Void)?
    var onRightTouchpadChanged: ((Float, Float, Bool) -> Void)?
    var onTouchpadClickChanged: ((SteamTouchpadSide, SteamControllerTouchpadState, Bool) -> Void)?
    var onTouchpadTapAction: ((SteamTouchpadSide, TouchpadRegion) -> Void)?
    var onBatteryChanged: ((Float, GCDeviceBattery.State) -> Void)?
    var onMotionChanged: ((SteamControllerMotionReport) -> Void)?

    private static let inputReportBufferSize = 128
    private static let triggerPressThreshold: Float = 0.12
    private static let analogDispatchIntervalNanoseconds: UInt64 = 8_000_000
    private static let stickEpsilon: Float = 0.01
    private static let triggerEpsilon: Float = 0.01
    private static let touchpadEpsilon: Float = 0.005
    private static let lizardModeReportID: UInt8 = 0x01
    private static let lizardModeCommand: UInt8 = 0x87
    private static let lizardModeSetting: UInt8 = 0x09
    static let hapticToneReportID: UInt8 = 0x83
    static let hapticStopReportID: UInt8 = 0x82
    static let hapticOutputPayloadSize = 64
    static let hapticOutputReportSize = 65
    static let leftTrackpadActuator: UInt8 = 0
    static let rightTrackpadActuator: UInt8 = 1

    private let lizardModeQueue = DispatchQueue(label: "com.controllerkeys.steam-hid.lizard-mode", qos: .utility)
    private let hapticOutputQueue = DispatchQueue(label: "com.controllerkeys.steam-hid.haptics", qos: .userInitiated)
    private let parser = SteamControllerHIDParser()
    private var previousButtons: UInt32 = 0
    private var lastAnalogDispatchNanoseconds: UInt64 = 0
    private var lastLeftStick: (x: Float, y: Float)?
    private var lastRightStick: (x: Float, y: Float)?
    private var lastLeftTrigger: (value: Float, pressed: Bool)?
    private var lastRightTrigger: (value: Float, pressed: Bool)?
    private var lastLeftTouchpad: SteamControllerTouchpadState?
    private var lastRightTouchpad: SteamControllerTouchpadState?
    private var lastLeftTouchpadClick: Bool?
    private var lastRightTouchpadClick: Bool?
    private var lastLeftTouchpadClickReleaseTime: TimeInterval = 0
    private var lastRightTouchpadClickReleaseTime: TimeInterval = 0
    private var lastLeftTouchpadClickActionTime: TimeInterval = 0
    private var lastRightTouchpadClickActionTime: TimeInterval = 0
    private var suppressedLeftTouchpadClickPress = false
    private var suppressedRightTouchpadClickPress = false
    private var pendingLeftTouchpadClickRelease: SteamControllerPendingTouchpadClickRelease?
    private var pendingRightTouchpadClickRelease: SteamControllerPendingTouchpadClickRelease?
    private var touchpadClickReleaseFlushWorkItem: DispatchWorkItem?
    private var leftTouchpadTapTracker = SteamControllerTouchpadTapTracker()
    private var rightTouchpadTapTracker = SteamControllerTouchpadTapTracker()
    private var touchpadTapGate = SteamControllerTouchpadTapGate()
    private var touchpadTapFlushWorkItem: DispatchWorkItem?
    private var leftTouchpadHapticTracker = SteamControllerTouchpadMovementHapticTracker()
    private var rightTouchpadHapticTracker = SteamControllerTouchpadMovementHapticTracker()
    private var hasActivated = false
    private var isStarted = false
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var callbackContext: UnsafeMutableRawPointer?
    private var scheduledRunLoop: CFRunLoop?
    private var lizardModeTimer: DispatchSourceTimer?
    private var lizardModeDisabled = false

    private final class CallbackContext {
        weak var controller: SteamControllerHIDController?

        init(controller: SteamControllerHIDController) {
            self.controller = controller
        }
    }

    private static let inputReportCallback: IOHIDReportCallback = { context, result, _, _, reportID, report, reportLength in
        guard result == kIOReturnSuccess, let context else { return }
        let holder = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
        holder.controller?.handleInputReport(reportID: reportID, report: report, length: Int(reportLength))
    }

    init(device: IOHIDDevice) {
        self.device = device
        self.deviceName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Steam Controller"
    }

    deinit {
        stop()
    }

    func start() {
        guard !isStarted else { return }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.inputReportBufferSize)
        reportBuffer = buffer

        let retainedContext = Unmanaged.passRetained(CallbackContext(controller: self)).toOpaque()
        callbackContext = retainedContext

        let currentRunLoop = CFRunLoopGetCurrent()!
        scheduledRunLoop = currentRunLoop
        IOHIDDeviceScheduleWithRunLoop(device, currentRunLoop, CFRunLoopMode.defaultMode.rawValue)

        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            Self.inputReportBufferSize,
            Self.inputReportCallback,
            retainedContext
        )

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            NSLog("[ControllerKeys] Steam Controller HID open returned 0x%08X", openResult)
        }

        isStarted = true
        if sendLizardMode(enabled: false) {
            lizardModeDisabled = true
            onActivated?(self)
            startLizardModeTimer()
        }
    }

    func stop() {
        lizardModeTimer?.cancel()
        lizardModeTimer = nil

        if isStarted && lizardModeDisabled {
            stopAllHaptics()
            sendLizardMode(enabled: true)
            lizardModeDisabled = false
        }

        if isStarted {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            if let scheduledRunLoop {
                IOHIDDeviceUnscheduleFromRunLoop(device, scheduledRunLoop, CFRunLoopMode.defaultMode.rawValue)
            }
        }
        scheduledRunLoop = nil

        if let callbackContext {
            Unmanaged<CallbackContext>.fromOpaque(callbackContext).release()
            self.callbackContext = nil
        }

        reportBuffer?.deallocate()
        reportBuffer = nil
        isStarted = false
        hasActivated = false
        previousButtons = 0
        lastAnalogDispatchNanoseconds = 0
        lastLeftStick = nil
        lastRightStick = nil
        lastLeftTrigger = nil
        lastRightTrigger = nil
        lastLeftTouchpad = nil
        lastRightTouchpad = nil
        lastLeftTouchpadClick = nil
        lastRightTouchpadClick = nil
        lastLeftTouchpadClickReleaseTime = 0
        lastRightTouchpadClickReleaseTime = 0
        lastLeftTouchpadClickActionTime = 0
        lastRightTouchpadClickActionTime = 0
        suppressedLeftTouchpadClickPress = false
        suppressedRightTouchpadClickPress = false
        pendingLeftTouchpadClickRelease = nil
        pendingRightTouchpadClickRelease = nil
        touchpadClickReleaseFlushWorkItem?.cancel()
        touchpadClickReleaseFlushWorkItem = nil
        leftTouchpadTapTracker = SteamControllerTouchpadTapTracker()
        rightTouchpadTapTracker = SteamControllerTouchpadTapTracker()
        touchpadTapGate = SteamControllerTouchpadTapGate()
        touchpadTapFlushWorkItem?.cancel()
        touchpadTapFlushWorkItem = nil
    }

    static func supportsDevice(_ device: IOHIDDevice) -> Bool {
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
        guard vendorID == SteamControllerHIDParser.valveVendorID,
              productID.map({ SteamControllerHIDParser.productIDs.contains($0) }) == true else {
            return false
        }

        if let usagePairs = IOHIDDeviceGetProperty(device, "DeviceUsagePairs" as CFString) as? [[String: Any]],
           usagePairs.contains(where: isAcceptedSteamUsagePair) {
            return true
        }

        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int
        if let usagePage, let usage {
            return usagePage == SteamControllerHIDParser.vendorUsagePage
                && SteamControllerHIDParser.acceptedVendorUsages.contains(usage)
        }

        return false
    }

    private static func isAcceptedSteamUsagePair(_ pair: [String: Any]) -> Bool {
        let usagePage = pair[kIOHIDDeviceUsagePageKey as String] as? Int
            ?? pair["DeviceUsagePage"] as? Int
        let usage = pair[kIOHIDDeviceUsageKey as String] as? Int
            ?? pair["DeviceUsage"] as? Int

        return usagePage == SteamControllerHIDParser.vendorUsagePage
            && usage.map { SteamControllerHIDParser.acceptedVendorUsages.contains($0) } == true
    }

    static func buttonEvents(previous: UInt32, current: UInt32) -> [ControllerButtonEvent] {
        buttonMap.compactMap { mask, button in
            let wasPressed = (previous & mask) != 0
            let isPressed = (current & mask) != 0
            guard wasPressed != isPressed else { return nil }
            return ControllerButtonEvent(button: button, pressed: isPressed)
        }
    }

    static func rightTouchpadState(from report: SteamControllerInputReport) -> SteamControllerTouchpadState {
        let isTouching = (report.buttons & SteamControllerButtonMask.rightPadTouch) != 0
        let isPressed = (report.buttons & SteamControllerButtonMask.rightPadClick) != 0
        guard isTouching else {
            return SteamControllerTouchpadState(x: 0, y: 0, isTouching: false, isPressed: isPressed)
        }

        return SteamControllerTouchpadState(
            x: normalizedTouchpadAxis(report.rightPadX),
            y: normalizedTouchpadAxis(report.rightPadY),
            isTouching: true,
            isPressed: isPressed
        )
    }

    static func leftTouchpadState(from report: SteamControllerInputReport) -> SteamControllerTouchpadState {
        let isTouching = (report.buttons & SteamControllerButtonMask.leftPadTouch) != 0
        let isPressed = (report.buttons & SteamControllerButtonMask.leftPadClick) != 0
        guard isTouching else {
            return SteamControllerTouchpadState(x: 0, y: 0, isTouching: false, isPressed: isPressed)
        }

        return SteamControllerTouchpadState(
            x: normalizedTouchpadAxis(report.leftPadX),
            y: normalizedTouchpadAxis(report.leftPadY),
            isTouching: true,
            isPressed: isPressed
        )
    }

    static func hapticTonePayload(
        actuator: UInt8,
        frequencyHz: UInt16,
        gain: Int8,
        count: UInt16
    ) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: hapticOutputPayloadSize)
        payload[0] = actuator
        payload[1] = UInt8(bitPattern: gain)
        payload[2] = UInt8(frequencyHz & 0xFF)
        payload[3] = UInt8((frequencyHz >> 8) & 0xFF)
        payload[4] = UInt8(count & 0xFF)
        payload[5] = UInt8((count >> 8) & 0xFF)
        return payload
    }

    static func hapticStopPayload(actuator: UInt8) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: hapticOutputPayloadSize)
        payload[0] = actuator
        return payload
    }

    static func hapticOutputReport(reportID: UInt8, payload: [UInt8]) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: hapticOutputReportSize)
        report[0] = reportID
        let copyCount = min(payload.count, report.count - 1)
        for index in 0..<copyCount {
            report[index + 1] = payload[index]
        }
        return report
    }

    static func lizardModeFeatureReport(enabled: Bool, includesReportID: Bool) -> [UInt8] {
        let value: UInt8 = enabled ? 1 : 0
        let count = 64
        let offset = includesReportID ? 1 : 0
        var report = [UInt8](repeating: 0, count: count)
        if includesReportID {
            report[0] = lizardModeReportID
        }
        report[offset] = lizardModeCommand
        report[offset + 1] = 0x03
        report[offset + 2] = lizardModeSetting
        report[offset + 3] = value
        report[offset + 4] = 0x00
        return report
    }

    func playHaptic(intensity: Float, sharpness: Float, duration: TimeInterval, transient: Bool) {
        playHaptic(
            actuators: Self.trackpadActuators,
            intensity: intensity,
            sharpness: sharpness,
            duration: duration,
            transient: transient
        )
    }

    func playTouchpadHaptic(
        side: SteamTouchpadSide,
        intensity: Float,
        sharpness: Float,
        duration: TimeInterval,
        transient: Bool
    ) {
        playHaptic(
            actuators: [Self.trackpadActuator(for: side)],
            intensity: intensity,
            sharpness: sharpness,
            duration: duration,
            transient: transient
        )
    }

    private func playHaptic(
        actuators: [UInt8],
        intensity: Float,
        sharpness: Float,
        duration: TimeInterval,
        transient: Bool
    ) {
        let clampedIntensity = max(0.05, min(1.0, intensity))
        let clampedSharpness = max(0.0, min(1.0, sharpness))
        let frequency = UInt16(180 + round(clampedSharpness * 360))
        let gain = Self.hapticGain(for: clampedIntensity)
        let pulseCount: UInt16
        if transient {
            pulseCount = 6
        } else {
            pulseCount = UInt16(min(0x7FFF, max(8, Int(duration * Double(frequency)))))
        }
        let stopDelay = max(duration, transient ? 0.04 : 0.02)

        hapticOutputQueue.async { [weak self] in
            guard let self else { return }
            for actuator in actuators {
                _ = self.sendHapticTone(
                    actuator: actuator,
                    frequencyHz: frequency,
                    gain: gain,
                    count: pulseCount
                )
            }

            self.hapticOutputQueue.asyncAfter(deadline: .now() + stopDelay) { [weak self] in
                guard let self else { return }
                for actuator in actuators {
                    _ = self.sendHapticStop(actuator: actuator)
                }
            }
        }
    }

    private static let buttonMap: [(UInt32, ControllerButton)] = [
        (SteamControllerButtonMask.a, .a),
        (SteamControllerButtonMask.b, .b),
        (SteamControllerButtonMask.x, .x),
        (SteamControllerButtonMask.y, .y),
        (SteamControllerButtonMask.qam, .share),
        (SteamControllerButtonMask.rightThumbstick, .rightThumbstick),
        (SteamControllerButtonMask.menu, .menu),
        (SteamControllerButtonMask.rightUpperGrip, .xboxPaddle2),
        (SteamControllerButtonMask.rightLowerGrip, .xboxPaddle4),
        (SteamControllerButtonMask.rightBumper, .rightBumper),
        (SteamControllerButtonMask.dpadDown, .dpadDown),
        (SteamControllerButtonMask.dpadRight, .dpadRight),
        (SteamControllerButtonMask.dpadLeft, .dpadLeft),
        (SteamControllerButtonMask.dpadUp, .dpadUp),
        (SteamControllerButtonMask.view, .view),
        (SteamControllerButtonMask.leftThumbstick, .leftThumbstick),
        (SteamControllerButtonMask.steam, .xbox),
        (SteamControllerButtonMask.leftUpperGrip, .xboxPaddle1),
        (SteamControllerButtonMask.leftLowerGrip, .xboxPaddle3),
        (SteamControllerButtonMask.leftBumper, .leftBumper),
    ]

    private func handleInputReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        if let battery = parser.parseBattery(reportID: reportID, report: UnsafePointer(report), length: length) {
            onBatteryChanged?(battery.level, battery.state)
            return
        }

        guard let parsed = parser.parse(reportID: reportID, report: UnsafePointer(report), length: length) else { return }

        if !hasActivated {
            hasActivated = true
            onActivated?(self)
        }

        for event in Self.buttonEvents(previous: previousButtons, current: parsed.buttons) {
            onButtonAction?(event.button, event.pressed)
        }
        previousButtons = parsed.buttons

        dispatchTouchpadChanges(from: parsed)
        dispatchAnalogChanges(from: parsed)
        if let motion = parsed.motion {
            onMotionChanged?(motion)
        }
    }

    private func dispatchTouchpadChanges(from parsed: SteamControllerInputReport) {
        let left = Self.leftTouchpadState(from: parsed)
        let right = Self.rightTouchpadState(from: parsed)
        let now = CFAbsoluteTimeGetCurrent()

        dispatchTouchpadClickIfNeeded(
            side: .left,
            state: left,
            now: now,
            lastClick: &lastLeftTouchpadClick,
            lastReleaseTime: &lastLeftTouchpadClickReleaseTime,
            lastActionTime: &lastLeftTouchpadClickActionTime,
            suppressedPress: &suppressedLeftTouchpadClickPress,
            pendingRelease: &pendingLeftTouchpadClickRelease
        )

        dispatchTouchpadClickIfNeeded(
            side: .right,
            state: right,
            now: now,
            lastClick: &lastRightTouchpadClick,
            lastReleaseTime: &lastRightTouchpadClickReleaseTime,
            lastActionTime: &lastRightTouchpadClickActionTime,
            suppressedPress: &suppressedRightTouchpadClickPress,
            pendingRelease: &pendingRightTouchpadClickRelease
        )

        flushPendingTouchpadTaps(now: now)

        leftTouchpadTapTracker.update(
            state: left,
            now: now
        ) { [weak self] region in
            self?.queueTouchpadTap(side: .left, region: region, now: now)
        }
        rightTouchpadTapTracker.update(
            state: right,
            now: now
        ) { [weak self] region in
            self?.queueTouchpadTap(side: .right, region: region, now: now)
        }

        if leftTouchpadHapticTracker.update(state: left, now: now) {
            playTouchpadHaptic(
                side: .left,
                intensity: Config.steamTouchpadMovementHapticIntensity,
                sharpness: Config.steamTouchpadMovementHapticSharpness,
                duration: Config.steamTouchpadMovementHapticDuration,
                transient: true
            )
        }
        if rightTouchpadHapticTracker.update(state: right, now: now) {
            playTouchpadHaptic(
                side: .right,
                intensity: Config.steamTouchpadMovementHapticIntensity,
                sharpness: Config.steamTouchpadMovementHapticSharpness,
                duration: Config.steamTouchpadMovementHapticDuration,
                transient: true
            )
        }

        if shouldDispatchTouchpad(lastLeftTouchpad, current: left) {
            onLeftTouchpadChanged?(left.x, left.y, left.isTouching)
            lastLeftTouchpad = left
        } else if lastLeftTouchpad == nil {
            lastLeftTouchpad = left
        }

        if shouldDispatchTouchpad(lastRightTouchpad, current: right) {
            onRightTouchpadChanged?(right.x, right.y, right.isTouching)
            lastRightTouchpad = right
        } else if lastRightTouchpad == nil {
            lastRightTouchpad = right
        }
    }

    private func dispatchTouchpadClickIfNeeded(
        side: SteamTouchpadSide,
        state: SteamControllerTouchpadState,
        now: TimeInterval,
        lastClick: inout Bool?,
        lastReleaseTime: inout TimeInterval,
        lastActionTime: inout TimeInterval,
        suppressedPress: inout Bool,
        pendingRelease: inout SteamControllerPendingTouchpadClickRelease?
    ) {
        if state.isPressed {
            pendingRelease = nil
        } else if let pending = pendingRelease {
            if now < pending.deadline {
                return
            }
            completePendingTouchpadClickRelease(
                side: side,
                pendingRelease: &pendingRelease,
                now: now,
                lastClick: &lastClick,
                lastReleaseTime: &lastReleaseTime,
                lastActionTime: &lastActionTime,
                suppressedPress: &suppressedPress
            )
            return
        }

        guard lastClick != state.isPressed else { return }
        if lastClick != nil || state.isPressed {
            touchpadTapGate.cancel(side: side)
        }

        if state.isPressed {
            markTouchpadClickFired(side: side)
            lastActionTime = now
        }

        if state.isPressed,
           lastClick != nil,
           now - lastReleaseTime < Config.steamTouchpadClickDebounceInterval {
            suppressedPress = true
            lastClick = true
            return
        }

        if !state.isPressed {
            pendingRelease = SteamControllerPendingTouchpadClickRelease(
                state: state,
                deadline: now + Config.steamTouchpadClickReleaseSettleInterval
            )
            scheduleTouchpadClickReleaseFlush()
            return
        }

        if lastClick != nil || state.isPressed {
            onTouchpadClickChanged?(side, state, state.isPressed)
        }
        lastClick = state.isPressed
    }

    private func queueTouchpadTap(side: SteamTouchpadSide, region: TouchpadRegion, now: TimeInterval) {
        let lastClickAction = side == .left ? lastLeftTouchpadClickActionTime : lastRightTouchpadClickActionTime
        guard now - lastClickAction >= Config.steamTouchpadPostClickTapSuppressionInterval else { return }

        touchpadTapGate.queue(side: side, region: region, now: now)
        scheduleTouchpadTapFlush()
    }

    private func markTouchpadClickFired(side: SteamTouchpadSide) {
        switch side {
        case .left:
            leftTouchpadTapTracker.markClickFired()
        case .right:
            rightTouchpadTapTracker.markClickFired()
        }
    }

    private func completePendingTouchpadClickRelease(
        side: SteamTouchpadSide,
        pendingRelease: inout SteamControllerPendingTouchpadClickRelease?,
        now: TimeInterval,
        lastClick: inout Bool?,
        lastReleaseTime: inout TimeInterval,
        lastActionTime: inout TimeInterval,
        suppressedPress: inout Bool
    ) {
        guard let pending = pendingRelease else { return }
        pendingRelease = nil
        lastReleaseTime = now

        if suppressedPress {
            suppressedPress = false
            lastClick = false
            return
        }

        if lastClick != nil {
            lastActionTime = now
            onTouchpadClickChanged?(side, pending.state, false)
        }
        lastClick = false
    }

    private func flushPendingTouchpadClickReleases(now: TimeInterval) {
        if let pending = pendingLeftTouchpadClickRelease, now >= pending.deadline {
            completePendingTouchpadClickRelease(
                side: .left,
                pendingRelease: &pendingLeftTouchpadClickRelease,
                now: now,
                lastClick: &lastLeftTouchpadClick,
                lastReleaseTime: &lastLeftTouchpadClickReleaseTime,
                lastActionTime: &lastLeftTouchpadClickActionTime,
                suppressedPress: &suppressedLeftTouchpadClickPress
            )
        }

        if let pending = pendingRightTouchpadClickRelease, now >= pending.deadline {
            completePendingTouchpadClickRelease(
                side: .right,
                pendingRelease: &pendingRightTouchpadClickRelease,
                now: now,
                lastClick: &lastRightTouchpadClick,
                lastReleaseTime: &lastRightTouchpadClickReleaseTime,
                lastActionTime: &lastRightTouchpadClickActionTime,
                suppressedPress: &suppressedRightTouchpadClickPress
            )
        }
    }

    private func scheduleTouchpadClickReleaseFlush() {
        touchpadClickReleaseFlushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let runLoop = self.scheduledRunLoop else { return }
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
                self?.flushPendingTouchpadClickReleases(now: CFAbsoluteTimeGetCurrent())
            }
            CFRunLoopWakeUp(runLoop)
        }
        touchpadClickReleaseFlushWorkItem = workItem
        DispatchQueue.global(qos: .userInteractive).asyncAfter(
            deadline: .now() + Config.steamTouchpadClickReleaseSettleInterval,
            execute: workItem
        )
    }

    private func flushPendingTouchpadTaps(now: TimeInterval) {
        for (side, region) in touchpadTapGate.flush(now: now) {
            onTouchpadTapAction?(side, region)
        }
    }

    private func scheduleTouchpadTapFlush() {
        touchpadTapFlushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let runLoop = self.scheduledRunLoop else { return }
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
                self?.flushPendingTouchpadTaps(now: CFAbsoluteTimeGetCurrent())
            }
            CFRunLoopWakeUp(runLoop)
        }
        touchpadTapFlushWorkItem = workItem
        DispatchQueue.global(qos: .userInteractive).asyncAfter(
            deadline: .now() + Config.steamTouchpadTapClickSuppressionWindow,
            execute: workItem
        )
    }

    private func dispatchAnalogChanges(from parsed: SteamControllerInputReport) {
        let now = DispatchTime.now().uptimeNanoseconds
        let intervalElapsed = lastAnalogDispatchNanoseconds == 0
            || now - lastAnalogDispatchNanoseconds >= Self.analogDispatchIntervalNanoseconds
        let leftTriggerPressed = parsed.leftTrigger > Self.triggerPressThreshold
        let rightTriggerPressed = parsed.rightTrigger > Self.triggerPressThreshold

        let leftTriggerPressChanged = lastLeftTrigger?.pressed != leftTriggerPressed
        let rightTriggerPressChanged = lastRightTrigger?.pressed != rightTriggerPressed
        guard intervalElapsed || leftTriggerPressChanged || rightTriggerPressChanged else { return }

        var dispatched = false
        if shouldDispatchStick(lastLeftStick, x: parsed.leftStickX, y: parsed.leftStickY) {
            lastLeftStick = (parsed.leftStickX, parsed.leftStickY)
            onLeftStickMoved?(parsed.leftStickX, parsed.leftStickY)
            dispatched = true
        }
        if shouldDispatchStick(lastRightStick, x: parsed.rightStickX, y: parsed.rightStickY) {
            lastRightStick = (parsed.rightStickX, parsed.rightStickY)
            onRightStickMoved?(parsed.rightStickX, parsed.rightStickY)
            dispatched = true
        }
        if shouldDispatchTrigger(lastLeftTrigger, value: parsed.leftTrigger, pressed: leftTriggerPressed) {
            lastLeftTrigger = (parsed.leftTrigger, leftTriggerPressed)
            onLeftTriggerChanged?(parsed.leftTrigger, leftTriggerPressed)
            dispatched = true
        }
        if shouldDispatchTrigger(lastRightTrigger, value: parsed.rightTrigger, pressed: rightTriggerPressed) {
            lastRightTrigger = (parsed.rightTrigger, rightTriggerPressed)
            onRightTriggerChanged?(parsed.rightTrigger, rightTriggerPressed)
            dispatched = true
        }
        if dispatched {
            lastAnalogDispatchNanoseconds = now
        }
    }

    private func shouldDispatchTouchpad(_ previous: SteamControllerTouchpadState?, current: SteamControllerTouchpadState) -> Bool {
        guard let previous else { return current.isTouching || current.isPressed }
        if previous.isTouching != current.isTouching || previous.isPressed != current.isPressed {
            return true
        }
        guard current.isTouching else { return false }
        return abs(previous.x - current.x) >= Self.touchpadEpsilon
            || abs(previous.y - current.y) >= Self.touchpadEpsilon
    }

    private func shouldDispatchStick(_ previous: (x: Float, y: Float)?, x: Float, y: Float) -> Bool {
        guard let previous else { return true }
        return abs(previous.x - x) >= Self.stickEpsilon
            || abs(previous.y - y) >= Self.stickEpsilon
    }

    private func shouldDispatchTrigger(_ previous: (value: Float, pressed: Bool)?, value: Float, pressed: Bool) -> Bool {
        guard let previous else { return true }
        return previous.pressed != pressed
            || abs(previous.value - value) >= Self.triggerEpsilon
    }

    private static func normalizedTouchpadAxis(_ raw: Int16, inverted: Bool = false) -> Float {
        let value = Float(raw) / 32768.0
        return max(-1.0, min(1.0, inverted ? -value : value))
    }

    private static let trackpadActuators = [leftTrackpadActuator, rightTrackpadActuator]

    private static func trackpadActuator(for side: SteamTouchpadSide) -> UInt8 {
        switch side {
        case .left:
            return leftTrackpadActuator
        case .right:
            return rightTrackpadActuator
        }
    }

    private static func hapticGain(for intensity: Float) -> Int8 {
        Int8(round(-18.0 + (Double(intensity) * 16.0)))
    }

    private func stopAllHaptics() {
        hapticOutputQueue.sync {
            for actuator in Self.trackpadActuators {
                _ = sendHapticStop(actuator: actuator)
            }
        }
    }

    @discardableResult
    private func sendHapticTone(
        actuator: UInt8,
        frequencyHz: UInt16,
        gain: Int8,
        count: UInt16
    ) -> Bool {
        let payload = Self.hapticTonePayload(
            actuator: actuator,
            frequencyHz: frequencyHz,
            gain: gain,
            count: count
        )
        return sendOutputReport(reportID: Self.hapticToneReportID, payload: payload)
    }

    @discardableResult
    private func sendHapticStop(actuator: UInt8) -> Bool {
        sendOutputReport(
            reportID: Self.hapticStopReportID,
            payload: Self.hapticStopPayload(actuator: actuator)
        )
    }

    @discardableResult
    private func sendOutputReport(reportID: UInt8, payload: [UInt8]) -> Bool {
        let reportWithID = Self.hapticOutputReport(reportID: reportID, payload: payload)
        let fullReportZeroIDResult = setOutputReport(reportID: 0, report: reportWithID)
        let fullReportResult = setOutputReport(reportID: reportID, report: reportWithID)
        let strippedPayloadResult = setOutputReport(reportID: reportID, report: payload)
        if fullReportZeroIDResult == kIOReturnSuccess ||
            fullReportResult == kIOReturnSuccess ||
            strippedPayloadResult == kIOReturnSuccess {
            return true
        }

        NSLog(
            "[ControllerKeys] Steam Controller output report 0x%02X failed: zero=0x%08X full=0x%08X stripped=0x%08X",
            reportID,
            fullReportZeroIDResult,
            fullReportResult,
            strippedPayloadResult
        )
        return false
    }

    private func setOutputReport(reportID: UInt8, report: [UInt8]) -> IOReturn {
        report.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(reportID),
                buffer.baseAddress!,
                buffer.count
            )
        }
    }

    private func startLizardModeTimer() {
        let timer = DispatchSource.makeTimerSource(queue: lizardModeQueue)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.sendLizardMode(enabled: false)
        }
        lizardModeTimer = timer
        timer.resume()
    }

    @discardableResult
    private func sendLizardMode(enabled: Bool) -> Bool {
        let attempts: [(reportID: UInt8, report: [UInt8])] = [
            (Self.lizardModeReportID, Self.lizardModeFeatureReport(enabled: enabled, includesReportID: false)),
            (Self.lizardModeReportID, Self.lizardModeFeatureReport(enabled: enabled, includesReportID: true)),
            (0x00, Self.lizardModeFeatureReport(enabled: enabled, includesReportID: true)),
        ]

        var succeeded = false
        var failures: [String] = []
        for attempt in attempts {
            let result = attempt.report.withUnsafeBufferPointer { buffer in
                IOHIDDeviceSetReport(
                    device,
                    kIOHIDReportTypeFeature,
                    CFIndex(attempt.reportID),
                    buffer.baseAddress!,
                    buffer.count
                )
            }

            if result == kIOReturnSuccess {
                succeeded = true
            } else {
                failures.append(String(format: "id=0x%02X len=%d result=0x%08X", attempt.reportID, attempt.report.count, result))
            }
        }

        if succeeded {
            return true
        }

        NSLog(
            "[ControllerKeys] Steam Controller lizard mode %@ failed: %@",
            enabled ? "enable" : "disable",
            failures.joined(separator: ", ")
        )
        return false
    }
}
