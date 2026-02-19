import Foundation
import IOKit
import IOKit.hid

/// Manages a generic HID gamepad not recognized by Apple's GameController framework.
/// Uses IOKit HID to enumerate elements and translates inputs via SDL database mappings.
class GenericHIDController {

    // MARK: - Properties

    let device: IOHIDDevice
    let mapping: SDLControllerMapping
    let deviceName: String

    /// Sorted elements matching SDL's index scheme
    private var buttonElements: [IOHIDElement] = []
    private var axisElements: [IOHIDElement] = []
    private var hatElement: IOHIDElement?

    /// Axis calibration from HID element descriptors
    private struct AxisCalibration {
        let logicalMin: Int
        let logicalMax: Int
        let center: Int
        let range: Double
    }
    private var axisCalibrations: [AxisCalibration] = []

    /// Previous state for change detection
    private var previousButtonStates: [Bool] = []
    private var previousAxisValues: [Double] = []
    private var previousHatBits: Int = -1

    /// Cached stick positions for individual axis updates
    private var cachedLeftX: Float = 0
    private var cachedLeftY: Float = 0
    private var cachedRightX: Float = 0
    private var cachedRightY: Float = 0
    private var callbackContext: UnsafeMutableRawPointer?
    private var isStarted = false

    // MARK: - Callbacks

    var onButtonAction: ((ControllerButton, Bool) -> Void)?
    var onLeftStickMoved: ((Float, Float) -> Void)?
    var onRightStickMoved: ((Float, Float) -> Void)?
    var onLeftTriggerChanged: ((Float, Bool) -> Void)?
    var onRightTriggerChanged: ((Float, Bool) -> Void)?

    // MARK: - Constants

    private static let triggerPressThreshold: Float = 0.12
    private static let axisChangeThreshold: Double = 0.01

    /// Holds a weak controller reference so callback dispatch remains safe
    /// even if HID callbacks race controller teardown.
    private final class CallbackContext {
        weak var controller: GenericHIDController?

        init(controller: GenericHIDController) {
            self.controller = controller
        }
    }

    private static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let holder = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
        holder.controller?.handleInputValue(value)
    }

    // MARK: - Initialization

    init?(device: IOHIDDevice, mapping: SDLControllerMapping) {
        self.device = device
        self.mapping = mapping
        self.deviceName = mapping.name

        guard enumerateElements() else { return nil }

        previousButtonStates = Array(repeating: false, count: buttonElements.count)
        previousAxisValues = Array(repeating: 0.0, count: axisElements.count)
    }

    deinit {
        stop()
    }

    // MARK: - Element Enumeration

    /// Enumerates and sorts HID elements to match SDL's indexing scheme.
    private func enumerateElements() -> Bool {
        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
            return false
        }

        var buttons: [(usage: Int, element: IOHIDElement)] = []
        var axes: [(usage: Int, element: IOHIDElement)] = []

        for element in elements {
            let type = IOHIDElementGetType(element)
            let usagePage = IOHIDElementGetUsagePage(element)
            let usage = Int(IOHIDElementGetUsage(element))

            guard type == kIOHIDElementTypeInput_Button ||
                  type == kIOHIDElementTypeInput_Misc ||
                  type == kIOHIDElementTypeInput_Axis else { continue }

            if usagePage == UInt32(kHIDPage_Button) {
                buttons.append((usage: usage, element: element))
            } else if usagePage == UInt32(kHIDPage_GenericDesktop) {
                switch usage {
                case kHIDUsage_GD_X, kHIDUsage_GD_Y, kHIDUsage_GD_Z,
                     kHIDUsage_GD_Rx, kHIDUsage_GD_Ry, kHIDUsage_GD_Rz:
                    axes.append((usage: usage, element: element))
                case kHIDUsage_GD_Hatswitch:
                    hatElement = element
                default:
                    break
                }
            }
        }

        // Sort by usage to match SDL's indexing
        buttons.sort { $0.usage < $1.usage }
        buttonElements = buttons.map { $0.element }

        axes.sort { $0.usage < $1.usage }
        axisElements = axes.map { $0.element }

        // Build calibration data
        axisCalibrations = axisElements.map { element in
            let logMin = Int(IOHIDElementGetLogicalMin(element))
            let logMax = Int(IOHIDElementGetLogicalMax(element))
            let center = (logMin + logMax) / 2
            let range = Double(max(logMax - logMin, 1))
            return AxisCalibration(logicalMin: logMin, logicalMax: logMax,
                                   center: center, range: range)
        }

        return !buttonElements.isEmpty || !axisElements.isEmpty || hatElement != nil
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }

        let retainedContext = Unmanaged.passRetained(CallbackContext(controller: self)).toOpaque()
        callbackContext = retainedContext
        IOHIDDeviceRegisterInputValueCallback(device, Self.inputValueCallback, retainedContext)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        isStarted = true
    }

    func stop() {
        guard isStarted || callbackContext != nil else { return }

        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        if isStarted {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        if let callbackContext {
            Unmanaged<CallbackContext>.fromOpaque(callbackContext).release()
            self.callbackContext = nil
        }
        isStarted = false
    }

    // MARK: - Input Value Dispatch

    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = Int(IOHIDElementGetUsage(element))
        let intValue = Int(IOHIDValueGetIntegerValue(value))

        if usagePage == UInt32(kHIDPage_Button) {
            handleButtonInput(usage: usage, value: intValue)
        } else if usagePage == UInt32(kHIDPage_GenericDesktop) {
            if usage == kHIDUsage_GD_Hatswitch {
                handleHatInput(value: intValue)
            } else {
                handleAxisInput(usage: usage, value: intValue)
            }
        }
    }

    // MARK: - Button Translation

    private func handleButtonInput(usage: Int, value: Int) {
        // Find button index: buttons sorted by usage, so index = position in sorted array
        guard let buttonIndex = buttonElements.firstIndex(where: {
            Int(IOHIDElementGetUsage($0)) == usage
        }) else { return }

        let pressed = value != 0
        guard buttonIndex < previousButtonStates.count,
              previousButtonStates[buttonIndex] != pressed else { return }
        previousButtonStates[buttonIndex] = pressed

        // Check button mappings for this index
        for (sdlName, ref) in mapping.buttonMap {
            if case .button(let idx) = ref, idx == buttonIndex {
                if let controllerButton = SDLControllerMapping.sdlToControllerButton[sdlName] {
                    onButtonAction?(controllerButton, pressed)
                }
                return
            }
        }

        // Check if triggers are mapped as buttons
        for (sdlName, ref) in mapping.axisMap {
            if case .button(let idx) = ref, idx == buttonIndex {
                let triggerValue: Float = pressed ? 1.0 : 0.0
                if sdlName == "lefttrigger" {
                    onLeftTriggerChanged?(triggerValue, pressed)
                } else if sdlName == "righttrigger" {
                    onRightTriggerChanged?(triggerValue, pressed)
                }
                return
            }
        }
    }

    // MARK: - Axis Translation

    private func handleAxisInput(usage: Int, value: Int) {
        guard let axisIndex = axisElements.firstIndex(where: {
            Int(IOHIDElementGetUsage($0)) == usage
        }) else { return }

        guard axisIndex < axisCalibrations.count else { return }
        let cal = axisCalibrations[axisIndex]

        // Normalize to -1..1 (center-based for sticks)
        let normalizedFull = (Double(value) - Double(cal.center)) / (cal.range / 2.0)
        let clampedFull = max(-1.0, min(1.0, normalizedFull))

        // Change detection
        guard axisIndex < previousAxisValues.count,
              abs(clampedFull - previousAxisValues[axisIndex]) > Self.axisChangeThreshold else { return }
        previousAxisValues[axisIndex] = clampedFull

        // Process stick axes
        for (sdlName, ref) in mapping.axisMap {
            guard SDLControllerMapping.sdlStickAxes.contains(sdlName) else { continue }
            if case .axis(let idx, let inverted) = ref, idx == axisIndex {
                let v = Float(inverted ? -clampedFull : clampedFull)
                switch sdlName {
                case "leftx":
                    cachedLeftX = v
                    onLeftStickMoved?(cachedLeftX, cachedLeftY)
                case "lefty":
                    cachedLeftY = v
                    onLeftStickMoved?(cachedLeftX, cachedLeftY)
                case "rightx":
                    cachedRightX = v
                    onRightStickMoved?(cachedRightX, cachedRightY)
                case "righty":
                    cachedRightY = v
                    onRightStickMoved?(cachedRightX, cachedRightY)
                default:
                    break
                }
            }
        }

        // Process trigger axes
        for (sdlName, ref) in mapping.axisMap {
            guard SDLControllerMapping.sdlTriggerAxes.contains(sdlName) else { continue }
            if case .axis(let idx, let inverted) = ref, idx == axisIndex {
                // Triggers use 0..1 range (min-based, not center-based)
                var normalized = Float((Double(value) - Double(cal.logicalMin)) / cal.range)
                normalized = max(0, min(1, normalized))
                if inverted { normalized = 1.0 - normalized }
                let pressed = normalized > Self.triggerPressThreshold

                if sdlName == "lefttrigger" {
                    onLeftTriggerChanged?(normalized, pressed)
                } else if sdlName == "righttrigger" {
                    onRightTriggerChanged?(normalized, pressed)
                }
            }
        }

        // Process button mappings that reference axes (e.g., dpup:+a1)
        for (sdlName, ref) in mapping.buttonMap {
            if case .axis(let idx, _) = ref, idx == axisIndex {
                guard let button = SDLControllerMapping.sdlToControllerButton[sdlName] else { continue }
                let pressed = abs(clampedFull) > 0.5
                onButtonAction?(button, pressed)
            }
        }
    }

    // MARK: - Hat Switch Translation

    private func handleHatInput(value: Int) {
        let hatBits = hatValueToBits(value)
        guard hatBits != previousHatBits else { return }
        let oldBits = previousHatBits
        previousHatBits = hatBits

        let directions: [(SDLElementRef.HatDirection, ControllerButton)] = [
            (.up, .dpadUp),
            (.right, .dpadRight),
            (.down, .dpadDown),
            (.left, .dpadLeft),
        ]

        for (dir, defaultButton) in directions {
            let wasPressed = oldBits >= 0 && (oldBits & dir.rawValue) != 0
            let isPressed = hatBits >= 0 && (hatBits & dir.rawValue) != 0

            if isPressed != wasPressed {
                // Find mapped button for this hat direction
                var mappedButton = defaultButton
                for (sdlName, ref) in mapping.buttonMap {
                    if case .hat(_, let d) = ref, d == dir {
                        if let b = SDLControllerMapping.sdlToControllerButton[sdlName] {
                            mappedButton = b
                            break
                        }
                    }
                }
                onButtonAction?(mappedButton, isPressed)
            }
        }
    }

    /// Convert 8-position hat value to SDL-style bitmask.
    /// Position: 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW, 8+=neutral
    private func hatValueToBits(_ value: Int) -> Int {
        switch value {
        case 0: return 1          // Up
        case 1: return 1 | 2     // Up + Right
        case 2: return 2          // Right
        case 3: return 4 | 2     // Down + Right
        case 4: return 4          // Down
        case 5: return 4 | 8     // Down + Left
        case 6: return 8          // Left
        case 7: return 1 | 8     // Up + Left
        default: return -1        // Neutral
        }
    }
}
