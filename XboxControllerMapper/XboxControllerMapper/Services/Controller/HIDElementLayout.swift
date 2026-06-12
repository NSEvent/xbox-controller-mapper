import Foundation
import IOKit
import IOKit.hid

/// Descriptor summary in the same element order `GenericHIDController` uses for
/// SDL refs (`b0...`, `a0...`, `h0...`).
struct HIDElementLayout: Equatable {
	let buttonUsages: [Int]
	let axisUsages: [Int]
	let hasHat: Bool

	var buttonCount: Int { buttonUsages.count }
	var axisCount: Int { axisUsages.count }

	init(buttonUsages: [Int], axisUsages: [Int], hasHat: Bool) {
		self.buttonUsages = buttonUsages
		self.axisUsages = axisUsages
		self.hasHat = hasHat
	}

	init(buttonCount: Int, axisCount: Int, hasHat: Bool) {
		self.buttonUsages = buttonCount > 0 ? Array(1...buttonCount) : []
		self.axisUsages = Array(0..<max(axisCount, 0))
		self.hasHat = hasHat
	}

	func contains(_ elementRef: SDLElementRef) -> Bool {
		switch elementRef {
		case let .button(index):
			return index >= 0 && index < buttonCount
		case let .axis(index, _, _):
			return index >= 0 && index < axisCount
		case let .hat(index, _):
			return index == 0 && hasHat
		}
	}

	static func layout(for device: IOHIDDevice) -> HIDElementLayout? {
		enumeration(for: device)?.layout
	}

	static func enumeration(for device: IOHIDDevice) -> HIDElementEnumeration? {
		guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
			return nil
		}

		let inputElements = elements.filter(Self.isSupportedInputElement)
		let hasControllerCollection = inputElements.contains(where: Self.isInControllerCollection)
		var buttons: [(usage: Int, element: IOHIDElement)] = []
		var axes: [(usage: Int, element: IOHIDElement)] = []
		var hatElement: IOHIDElement?

		for element in inputElements {
			if hasControllerCollection && !Self.isInControllerCollection(element) {
				continue
			}

			let usagePage = IOHIDElementGetUsagePage(element)
			let usage = Int(IOHIDElementGetUsage(element))

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

		buttons.sort { $0.usage < $1.usage }
		axes.sort { $0.usage < $1.usage }

		let layout = HIDElementLayout(
			buttonUsages: buttons.map { $0.usage },
			axisUsages: axes.map { $0.usage },
			hasHat: hatElement != nil
		)
		return HIDElementEnumeration(
			layout: layout,
			buttonElements: buttons.map { $0.element },
			axisElements: axes.map { $0.element },
			hatElement: hatElement
		)
	}

	nonisolated private static let controllerCollectionUsages: Set<Int> = [
		kHIDUsage_GD_Joystick,
		kHIDUsage_GD_GamePad,
		kHIDUsage_GD_MultiAxisController,
	]

	nonisolated private static func isSupportedInputElement(_ element: IOHIDElement) -> Bool {
		let type = IOHIDElementGetType(element)
		return type == kIOHIDElementTypeInput_Button ||
			   type == kIOHIDElementTypeInput_Misc ||
			   type == kIOHIDElementTypeInput_Axis
	}

	nonisolated private static func isInControllerCollection(_ element: IOHIDElement) -> Bool {
		var current = IOHIDElementGetParent(element)
		while let parent = current {
			let usagePage = IOHIDElementGetUsagePage(parent)
			let usage = Int(IOHIDElementGetUsage(parent))
			if usagePage == UInt32(kHIDPage_GenericDesktop),
			   controllerCollectionUsages.contains(usage) {
				return true
			}
			current = IOHIDElementGetParent(parent)
		}
		return false
	}
}

struct HIDElementEnumeration {
	let layout: HIDElementLayout
	let buttonElements: [IOHIDElement]
	let axisElements: [IOHIDElement]
	let hatElement: IOHIDElement?
}
