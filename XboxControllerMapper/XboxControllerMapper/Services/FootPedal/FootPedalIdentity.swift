import Foundation
import IOKit.hid

/// Identity of the VEC Infinity USB foot pedal (IN-USB-2 / IN-USB-3, the
/// three-pedal transcription pedal sold by VEC Electronics).
///
/// It enumerates as a Consumer-page (0x0C) "Consumer Control" device with no
/// keyboard usages, so macOS ignores it unless an app reads its reports — but
/// Karabiner-Elements grabs it like a keyboard by default, which blocks the
/// exclusive open below until Karabiner's **Modify events** is off for it.
nonisolated enum FootPedalIdentity {
	static let vendorID = 0x05F3
	static let productID = 0x00FF

	static let displayName = "VEC Infinity Pedal"

	static func matches(vendorID: Int?, productID: Int?) -> Bool {
		vendorID == Self.vendorID && productID == Self.productID
	}

	static func matches(device: IOHIDDevice) -> Bool {
		matches(
			vendorID: IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
			productID: IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
		)
	}
}

/// The pedal's two-byte input report (no report ID). Byte 0 carries one bit
/// per pedal (Button page usages 1–3); the rest is padding:
///
///     05 0C 09 03 A1 01 05 09 19 01 29 03 15 00 25 01
///     95 03 75 01 81 02 95 01 75 05 81 01 95 01 75 08 81 01 C0
///
/// Each pedal is an independent switch, so pressing two at once sets both bits
/// and the decoder emits one edge per pedal — holds, chords and sequences all
/// work like any other controller button.
nonisolated struct FootPedalReportDecoder {
	struct Event: Equatable {
		let button: ControllerButton
		let pressed: Bool
	}

	/// Bit order in byte 0, matching the pedal's physical left-to-right layout.
	static let buttonsByBit: [ControllerButton] = [.footPedalLeft, .footPedalMiddle, .footPedalRight]

	private(set) var pressedMask: UInt8 = 0

	mutating func process(report: [UInt8]) -> [Event] {
		guard let first = report.first else { return [] }
		return transition(to: first & 0b111)
	}

	/// Releases every held pedal (disconnect / stop).
	mutating func reset() -> [Event] {
		transition(to: 0)
	}

	private mutating func transition(to mask: UInt8) -> [Event] {
		let changed = mask ^ pressedMask
		pressedMask = mask
		guard changed != 0 else { return [] }
		return Self.buttonsByBit.enumerated().compactMap { bit, button in
			let flag = UInt8(1) << bit
			guard changed & flag != 0 else { return nil }
			return Event(button: button, pressed: mask & flag != 0)
		}
	}
}
