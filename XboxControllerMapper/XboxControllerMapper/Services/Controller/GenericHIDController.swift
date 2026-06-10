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

    /// SDL index lookups keyed by element cookie — O(1) per input event and
    /// alias-safe (elements with duplicate usages still have distinct cookies).
    private var buttonIndexByCookie: [IOHIDElementCookie: Int] = [:]
    private var axisIndexByCookie: [IOHIDElementCookie: Int] = [:]

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

	static func stickAxisValue(_ value: Double, inverted: Bool, polarity: SDLElementRef.AxisPolarity) -> Double {
		let adjusted = inverted ? -value : value
		switch polarity {
		case .full:
			return adjusted
		case .positive:
			return max(0.0, adjusted)
		case .negative:
			return min(0.0, adjusted)
		}
	}

	static func outputStickAxisValue(
		_ value: Double,
		sourcePolarity: SDLElementRef.AxisPolarity,
		outputPolarity: SDLElementRef.AxisPolarity
	) -> Double {
		switch outputPolarity {
		case .full:
			return value
		case .positive:
			return sourcePolarity == .negative ? abs(value) : max(0.0, value)
		case .negative:
			return sourcePolarity == .positive ? -abs(value) : min(0.0, value)
		}
	}

	static func triggerAxisValue(
		minBasedValue: Float,
		centeredValue: Double,
		inverted: Bool,
		polarity: SDLElementRef.AxisPolarity
	) -> Float {
		switch polarity {
		case .full:
			return inverted ? 1.0 - minBasedValue : minBasedValue
		case .positive:
			let adjusted = inverted ? -centeredValue : centeredValue
			return Float(max(0.0, min(1.0, adjusted)))
		case .negative:
			let adjusted = inverted ? centeredValue : -centeredValue
			return Float(max(0.0, min(1.0, adjusted)))
		}
	}

	static func axisButtonPressed(_ value: Double, inverted: Bool, polarity: SDLElementRef.AxisPolarity) -> Bool {
		let adjusted = inverted ? -value : value
		switch polarity {
		case .full:
			return abs(adjusted) > 0.5
		case .positive:
			return adjusted > 0.5
		case .negative:
			return adjusted < -0.5
		}
	}

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
        buttonIndexByCookie = Self.indexByCookie(for: buttonElements)

        axes.sort { $0.usage < $1.usage }
        axisElements = axes.map { $0.element }
        axisIndexByCookie = Self.indexByCookie(for: axisElements)

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

    private static func indexByCookie(for elements: [IOHIDElement]) -> [IOHIDElementCookie: Int] {
        var map: [IOHIDElementCookie: Int] = [:]
        for (index, element) in elements.enumerated() {
            let cookie = IOHIDElementGetCookie(element)
            // Keep the first index on (unlikely) duplicate cookies to match
            // the previous firstIndex(where:) semantics.
            if map[cookie] == nil {
                map[cookie] = index
            }
        }
        return map
    }

    // MARK: - Lifecycle

    /// Opens the device and registers for input values. Returns false (without
    /// registering anything) when IOHIDDeviceOpen fails, so callers can avoid
    /// presenting a phantom controller that will never deliver input.
    @discardableResult
    func start() -> Bool {
        guard !isStarted else { return true }

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            NSLog("[ControllerKeys] Generic HID device open returned 0x%08X for %@", openResult, deviceName)
            return false
        }

        let retainedContext = Unmanaged.passRetained(CallbackContext(controller: self)).toOpaque()
        callbackContext = retainedContext
        IOHIDDeviceRegisterInputValueCallback(device, Self.inputValueCallback, retainedContext)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        isStarted = true
        return true
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
        let cookie = IOHIDElementGetCookie(element)

        if usagePage == UInt32(kHIDPage_Button) {
            handleButtonInput(cookie: cookie, value: intValue)
        } else if usagePage == UInt32(kHIDPage_GenericDesktop) {
            if usage == kHIDUsage_GD_Hatswitch {
                handleHatInput(value: intValue)
            } else {
                handleAxisInput(cookie: cookie, value: intValue)
            }
        }
    }

    // MARK: - Button Translation

    private func handleButtonInput(cookie: IOHIDElementCookie, value: Int) {
        guard let buttonIndex = buttonIndexByCookie[cookie] else { return }

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

    private func handleAxisInput(cookie: IOHIDElementCookie, value: Int) {
        guard let axisIndex = axisIndexByCookie[cookie] else { return }

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
		var changedStickAxes = Set<String>()
		for (sdlName, ref) in mapping.axisMap {
			guard let targetAxis = SDLControllerMapping.normalizedAxisName(sdlName),
			      SDLControllerMapping.sdlStickAxes.contains(targetAxis.name),
			      case .axis(let idx, _, _) = ref,
			      idx == axisIndex else { continue }
			changedStickAxes.insert(targetAxis.name)
		}
		for sdlName in changedStickAxes {
			emitStickAxis(sdlName, value: composedStickAxisValue(for: sdlName))
		}

        // Process trigger axes
        for (sdlName, ref) in mapping.axisMap {
            guard SDLControllerMapping.sdlTriggerAxes.contains(sdlName) else { continue }
	    if case .axis(let idx, let inverted, let polarity) = ref, idx == axisIndex {
                // Triggers use 0..1 range (min-based, not center-based)
                var normalized = Float((Double(value) - Double(cal.logicalMin)) / cal.range)
                normalized = max(0, min(1, normalized))
				normalized = Self.triggerAxisValue(
					minBasedValue: normalized,
					centeredValue: clampedFull,
					inverted: inverted,
					polarity: polarity
				)
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
			if case .axis(let idx, let inverted, let polarity) = ref, idx == axisIndex {
				guard let button = SDLControllerMapping.sdlToControllerButton[sdlName] else { continue }
				let pressed = Self.axisButtonPressed(clampedFull, inverted: inverted, polarity: polarity)
				onButtonAction?(button, pressed)
			}
        }
    }

	private func composedStickAxisValue(for sdlAxisName: String) -> Float {
		var value = 0.0
		for (mappedName, ref) in mapping.axisMap {
			guard let targetAxis = SDLControllerMapping.normalizedAxisName(mappedName),
			      targetAxis.name == sdlAxisName,
			      SDLControllerMapping.sdlStickAxes.contains(targetAxis.name),
			      case .axis(let idx, let inverted, let polarity) = ref,
			      idx < previousAxisValues.count else { continue }
			let sourceValue = Self.stickAxisValue(
				previousAxisValues[idx],
				inverted: inverted,
				polarity: polarity
			)
			value += Self.outputStickAxisValue(
				sourceValue,
				sourcePolarity: polarity,
				outputPolarity: targetAxis.polarity
			)
		}
		return Float(max(-1.0, min(1.0, value)))
	}

	private func emitStickAxis(_ sdlName: String, value: Float) {
		switch sdlName {
		case "leftx":
			cachedLeftX = value
			onLeftStickMoved?(cachedLeftX, cachedLeftY)
		case "lefty":
			cachedLeftY = value
			onLeftStickMoved?(cachedLeftX, cachedLeftY)
		case "rightx":
			cachedRightX = value
			onRightStickMoved?(cachedRightX, cachedRightY)
		case "righty":
			cachedRightY = value
			onRightStickMoved?(cachedRightX, cachedRightY)
		default:
			break
		}
	}

    // MARK: - Hat Switch Translation

    private func handleHatInput(value: Int) {
		let logicalMin = hatElement.map { Int(IOHIDElementGetLogicalMin($0)) } ?? 0
		let logicalMax = hatElement.map { Int(IOHIDElementGetLogicalMax($0)) } ?? 7
		let hatBits = Self.hatValueToBits(value, logicalMin: logicalMin, logicalMax: logicalMax)
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

}
