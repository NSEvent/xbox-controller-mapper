import Foundation
import IOKit.hid

/// Declarative HID matching criteria for raw-controller backends. Kept pure so
/// adding a future HID controller can be covered by unit tests before touching
/// IOHIDManager callback wiring.
enum HIDMatchingCriterion: Hashable {
	case vendorProduct(vendorID: Int, productID: Int)
	case usage(page: Int, usage: Int)
	case transport(String)

	var dictionary: [String: Any] {
		switch self {
		case let .vendorProduct(vendorID, productID):
			return [
				kIOHIDVendorIDKey as String: vendorID,
				kIOHIDProductIDKey as String: productID,
			]
		case let .usage(page, usage):
			return [
				kIOHIDDeviceUsagePageKey as String: page,
				kIOHIDDeviceUsageKey as String: usage,
			]
		case let .transport(name):
			return [
				kIOHIDTransportKey as String: name,
			]
		}
	}
}

protocol HIDControllerDriverDescriptor {
	var displayName: String { get }
	var matchingCriteria: [HIDMatchingCriterion] { get }
}

extension HIDControllerDriverDescriptor {
	var matchingCFArray: CFArray {
		matchingCriteria.map(\.dictionary) as CFArray
	}
}

struct NintendoHIDDriverDescriptor: HIDControllerDriverDescriptor {
	static let vendorID = 0x057E
	static let proControllerProductID = 0x2009

	let displayName = "Nintendo Switch Pro Controller"

	var matchingCriteria: [HIDMatchingCriterion] {
		[
			.vendorProduct(
				vendorID: Self.vendorID,
				productID: Self.proControllerProductID
			)
		]
	}
}

struct EightBitDoDInputHIDDriverDescriptor: HIDControllerDriverDescriptor {
	static let vendorID = 0x2DC8
	static let microProductID = 0x9020
	static let zero2ProductID = 0x3230
	static let lite2ProductID = 0x5112

	let displayName = "8BitDo D-input pads"

	var matchingCriteria: [HIDMatchingCriterion] {
		Self.productIDs.map {
			.vendorProduct(vendorID: Self.vendorID, productID: $0)
		}
	}

	static var productIDs: [Int] {
		[microProductID, zero2ProductID, lite2ProductID]
	}
}

struct GenericHIDDriverDescriptor: HIDControllerDriverDescriptor {
	static let excludedVendorIDs: Set<Int> = [
		0x045E, // Xbox raw Guide/Elite path
		0x054C, // PlayStation raw PS button path
		0x057E, // Nintendo raw Home button path
		SteamControllerHIDParser.valveVendorID,
	]

	let knownVendorProductPairs: [(vendorID: Int, productID: Int)]
	let displayName = "Generic HID Controller"

	var matchingCriteria: [HIDMatchingCriterion] {
		knownVendorProductPairs.map {
			.vendorProduct(vendorID: $0.vendorID, productID: $0.productID)
		} + Self.standardControllerCriteria + Self.bluetoothLECriteria
	}

	static let standardControllerCriteria: [HIDMatchingCriterion] = [
		.usage(page: Int(kHIDPage_GenericDesktop), usage: Int(kHIDUsage_GD_Joystick)),
		.usage(page: Int(kHIDPage_GenericDesktop), usage: Int(kHIDUsage_GD_GamePad)),
		.usage(page: Int(kHIDPage_GenericDesktop), usage: Int(kHIDUsage_GD_MultiAxisController)),
	]

	static let bluetoothLECriteria: [HIDMatchingCriterion] = [
		.transport("BluetoothLowEnergy"),
		.transport("Bluetooth Low Energy"),
	]
}
