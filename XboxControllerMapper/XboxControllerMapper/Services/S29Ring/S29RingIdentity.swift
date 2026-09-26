import Foundation
import IOKit.hid

/// Identity check for the S29 Bluetooth button ring.
///
/// The ring's firmware spoofs Apple's vendor ID and the product ID of a real
/// Apple aluminum keyboard, so VID/PID alone would match (and seize!) a user's
/// keyboard. All four facts — VID, PID, product name "S29", and a Bluetooth LE
/// transport — must match before ControllerKeys opens the device exclusively.
nonisolated enum S29RingIdentity {
	static let vendorID = 0x05AC
	static let productID = 0x0220
	static let productName = "S29"
	static let bluetoothLowEnergyTransports = ["Bluetooth Low Energy", "BluetoothLowEnergy"]

	static let displayName = "S29 Ring"

	static func matches(vendorID: Int?, productID: Int?, productName: String?, transport: String?) -> Bool {
		guard vendorID == Self.vendorID, productID == Self.productID else { return false }
		guard let productName,
			  productName.trimmingCharacters(in: .whitespacesAndNewlines)
				.caseInsensitiveCompare(Self.productName) == .orderedSame else { return false }
		guard let transport else { return false }
		return bluetoothLowEnergyTransports.contains {
			$0.caseInsensitiveCompare(transport) == .orderedSame
		}
	}

	static func matches(device: IOHIDDevice) -> Bool {
		matches(
			vendorID: IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
			productID: IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
			productName: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String,
			transport: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
		)
	}
}
