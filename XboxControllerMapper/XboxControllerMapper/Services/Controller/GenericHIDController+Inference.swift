import Foundation
import IOKit
import IOKit.hid

extension GenericHIDController {
	private static let fallbackButtonNames = [
		"a",
		"b",
		"x",
		"y",
		"leftshoulder",
		"rightshoulder",
		"back",
		"start",
		"leftstick",
		"rightstick",
		"guide",
		"misc1",
	]
	private static let fallbackAxisNames = [
		"leftx",
		"lefty",
		"rightx",
		"righty",
		"lefttrigger",
		"righttrigger",
	]
	private static let controllerTopLevelUsages: Set<Int> = [
		kHIDUsage_GD_Joystick,
		kHIDUsage_GD_GamePad,
		kHIDUsage_GD_MultiAxisController,
	]
	private static let ignoredTopLevelUsages: Set<Int> = [
		kHIDUsage_GD_Pointer,
		kHIDUsage_GD_Mouse,
		kHIDUsage_GD_Keyboard,
	]

	static func canInferMapping(from device: IOHIDDevice) -> Bool {
		guard !hasKeyboardOrPointerTopLevelUsage(device) else { return false }
		guard let summary = elementSummary(for: device) else { return false }
		return inferredMapping(
			buttonCount: summary.buttonCount,
			axisCount: summary.axisCount,
			hasHat: summary.hasHat,
			name: "Generic HID Controller"
		) != nil
	}

	static func canUseKnownMapping(from device: IOHIDDevice) -> Bool {
		!hasKeyboardOrPointerTopLevelUsage(device)
	}

	static func inferredMapping(
		for device: IOHIDDevice,
		fallbackName: String,
		guid: String
	) -> SDLControllerMapping? {
		guard let summary = elementSummary(for: device) else { return nil }
		return inferredMapping(
			buttonCount: summary.buttonCount,
			axisCount: summary.axisCount,
			hasHat: summary.hasHat,
			name: fallbackName,
			guid: guid
		)
	}

	static func inferredMapping(
		buttonCount: Int,
		axisCount: Int,
		hasHat: Bool,
		name: String,
		guid: String = "00000000000000000000000000000000"
	) -> SDLControllerMapping? {
		let hasGamepadShape = hasHat || axisCount >= 4 || buttonCount >= 6
		guard buttonCount >= 4, axisCount >= 2 || hasHat, hasGamepadShape else { return nil }

		var buttonMap: [String: SDLElementRef] = [:]
		for (index, buttonName) in fallbackButtonNames.prefix(buttonCount).enumerated() {
			buttonMap[buttonName] = .button(index)
		}
		if hasHat {
			buttonMap["dpup"] = .hat(0, direction: .up)
			buttonMap["dpright"] = .hat(0, direction: .right)
			buttonMap["dpdown"] = .hat(0, direction: .down)
			buttonMap["dpleft"] = .hat(0, direction: .left)
		}

		var axisMap: [String: SDLElementRef] = [:]
		for (index, axisName) in fallbackAxisNames.prefix(axisCount).enumerated() {
			axisMap[axisName] = .axis(index, inverted: false, polarity: .full)
		}

		return SDLControllerMapping(
			guid: guid,
			name: name,
			buttonMap: buttonMap,
			axisMap: axisMap
		)
	}

	private static func elementSummary(for device: IOHIDDevice) -> (buttonCount: Int, axisCount: Int, hasHat: Bool)? {
		guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
			return nil
		}

		var buttonCount = 0
		var axisCount = 0
		var hasHat = false
		for element in elements {
			let type = IOHIDElementGetType(element)
			let usagePage = IOHIDElementGetUsagePage(element)
			let usage = Int(IOHIDElementGetUsage(element))

			guard type == kIOHIDElementTypeInput_Button ||
			      type == kIOHIDElementTypeInput_Misc ||
			      type == kIOHIDElementTypeInput_Axis else { continue }

			if usagePage == UInt32(kHIDPage_Button) {
				buttonCount += 1
			} else if usagePage == UInt32(kHIDPage_GenericDesktop) {
				switch usage {
				case kHIDUsage_GD_X, kHIDUsage_GD_Y, kHIDUsage_GD_Z,
				     kHIDUsage_GD_Rx, kHIDUsage_GD_Ry, kHIDUsage_GD_Rz:
					axisCount += 1
				case kHIDUsage_GD_Hatswitch:
					hasHat = true
				default:
					break
				}
			}
		}

		return (buttonCount: buttonCount, axisCount: axisCount, hasHat: hasHat)
	}

	private static func hasKeyboardOrPointerTopLevelUsage(_ device: IOHIDDevice) -> Bool {
		let usagePairs = topLevelUsagePairs(for: device)
		if usagePairs.contains(where: { isControllerTopLevelUsage(usagePage: $0.usagePage, usage: $0.usage) }) {
			return false
		}
		if usagePairs.contains(where: { isIgnoredTopLevelUsage(usagePage: $0.usagePage, usage: $0.usage) }) {
			return true
		}

		guard let usagePage = intValue(IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePageKey as CFString)),
		      let usage = intValue(IOHIDDeviceGetProperty(device, kIOHIDDeviceUsageKey as CFString)) else {
			return hasIgnoredPrimaryUsage(device)
		}
		return isIgnoredTopLevelUsage(usagePage: usagePage, usage: usage)
	}

	private static func topLevelUsagePairs(for device: IOHIDDevice) -> [(usagePage: Int, usage: Int)] {
		guard let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] else {
			return []
		}
		return pairs.compactMap { pair in
			guard let usagePage = intValue(pair[kIOHIDDeviceUsagePageKey as String]),
			      let usage = intValue(pair[kIOHIDDeviceUsageKey as String]) else {
				return nil
			}
			return (usagePage: usagePage, usage: usage)
		}
	}

	private static func hasIgnoredPrimaryUsage(_ device: IOHIDDevice) -> Bool {
		guard let usagePage = intValue(IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString)),
		      let usage = intValue(IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString)) else {
			return false
		}
		return isIgnoredTopLevelUsage(usagePage: usagePage, usage: usage)
	}

	private static func isControllerTopLevelUsage(usagePage: Int, usage: Int) -> Bool {
		usagePage == kHIDPage_GenericDesktop && controllerTopLevelUsages.contains(usage)
	}

	private static func isIgnoredTopLevelUsage(usagePage: Int, usage: Int) -> Bool {
		usagePage == kHIDPage_GenericDesktop && ignoredTopLevelUsages.contains(usage)
	}

	private static func intValue(_ value: Any?) -> Int? {
		if let value = value as? Int {
			return value
		}
		if let value = value as? NSNumber {
			return value.intValue
		}
		return nil
	}
}
