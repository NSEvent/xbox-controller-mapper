import Foundation
import IOKit.hid

/// Declarative HID matching criteria for raw-controller backends. Kept pure so
/// adding a future HID controller can be covered by unit tests before touching
/// IOHIDManager callback wiring.
enum HIDMatchingCriterion: Hashable {
	case vendorProduct(vendorID: Int, productID: Int)
	case usage(page: Int, usage: Int)
	case transport(String)
	/// All three must match in one dictionary (IOHIDManager ANDs the keys of a
	/// single matching dictionary and ORs separate dictionaries).
	case vendorProductTransport(vendorID: Int, productID: Int, transport: String)

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
		case let .vendorProductTransport(vendorID, productID, transport):
			return [
				kIOHIDVendorIDKey as String: vendorID,
				kIOHIDProductIDKey as String: productID,
				kIOHIDTransportKey as String: transport,
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
	static let ultimate2ProductID = EightBitDoUltimate2HIDButtonTable.productID

	let displayName = "8BitDo D-input pads"

	var matchingCriteria: [HIDMatchingCriterion] {
		Self.productIDs.map {
			.vendorProduct(vendorID: Self.vendorID, productID: $0)
		}
	}

	static var productIDs: [Int] {
		[microProductID, zero2ProductID, lite2ProductID, ultimate2ProductID]
	}
}

/// Raw HID Button-page (0x09) usages on the 8BitDo Ultimate 2 Wireless
/// (D-input / Bluetooth) that Apple's GameController framework drops: Home
/// plus the four extra back/shoulder buttons. Paddle numbering follows the
/// Xbox Elite paddle buttons so profiles carry across both pads.
///
/// HID usage N is SDL button index N-1 (the SDL row sorts Button-page usages),
/// so this table mirrors the bundled row's `guide:b12`, `paddle1:b16`,
/// `paddle2:b17`, `paddle3:b5`, `paddle4:b2`.
nonisolated enum EightBitDoUltimate2HIDButtonTable {
	static let productID = 0x6012
	static let buttonUsagePage = 0x09

	static let buttonsByUsage: [Int: ControllerButton] = [
		13: .xbox,
		17: .xboxPaddle1,
		18: .xboxPaddle2,
		6: .xboxPaddle3,
		3: .xboxPaddle4,
	]

	/// The logical control for a raw Button-page usage, or nil for usages the
	/// GameController profile already delivers (or that aren't Button page).
	static func button(usagePage: Int, usage: Int) -> ControllerButton? {
		guard usagePage == buttonUsagePage else { return nil }
		return buttonsByUsage[usage]
	}

	static var rawButtons: Set<ControllerButton> {
		Set(buttonsByUsage.values)
	}
}

/// Candidate matching for the S29 ring. Scoped to the spoofed Apple VID/PID
/// *over Bluetooth LE* so a USB Apple keyboard never even reaches the device
/// callback; `S29RingIdentity.matches` then also requires the "S29" product
/// name before anything is opened (let alone seized).
struct S29RingHIDDriverDescriptor: HIDControllerDriverDescriptor {
	let displayName = S29RingIdentity.displayName

	var matchingCriteria: [HIDMatchingCriterion] {
		S29RingIdentity.bluetoothLowEnergyTransports.map {
			.vendorProductTransport(
				vendorID: S29RingIdentity.vendorID,
				productID: S29RingIdentity.productID,
				transport: $0
			)
		}
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

/// Edge-detection latch for buttons synthesized from raw HID side channels.
/// `nonisolated` + internally locked (like `SticklessDpadCloneDetector`) so HID
/// callbacks on any thread can feed it, and a disconnect can release exactly the
/// buttons raw HID pressed.
nonisolated final class RawHIDButtonLatch: @unchecked Sendable {
	private let lock = NSLock()
	private var pressed: Set<ControllerButton> = []

	/// Records the new state; returns true only when it changed (an edge).
	func update(_ button: ControllerButton, pressed isPressed: Bool) -> Bool {
		lock.lock()
		defer { lock.unlock() }
		if isPressed {
			return pressed.insert(button).inserted
		}
		return pressed.remove(button) != nil
	}

	/// Clears the latch and returns every button that was still held.
	func releaseAll() -> Set<ControllerButton> {
		lock.lock()
		defer { lock.unlock() }
		let held = pressed
		pressed.removeAll()
		return held
	}

	var heldButtons: Set<ControllerButton> {
		lock.lock()
		defer { lock.unlock() }
		return pressed
	}
}
