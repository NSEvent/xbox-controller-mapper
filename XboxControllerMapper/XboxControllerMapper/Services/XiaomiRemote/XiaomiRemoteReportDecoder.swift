import Foundation
import IOKit.hid

/// RC003 identity from the paired physical remote. Product names can be blank.
nonisolated enum XiaomiRemoteIdentity {
	static let vendorID = 0x2717
	static let productID = 0x32B8
	static let displayName = "Xiaomi Remote 2 Pro"
	static let transports: Set<String> = ["Bluetooth Low Energy", "BluetoothLowEnergy"]

	static func matches(vendorID: Int?, productID: Int?, transport: String?) -> Bool {
		vendorID == Self.vendorID && productID == Self.productID && transports.contains(transport ?? "")
	}

	static func matches(_ device: IOHIDDevice) -> Bool {
		matches(
			vendorID: IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
			productID: IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
			transport: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
		)
	}
}

nonisolated struct XiaomiRemoteButtonEvent: Equatable, Sendable {
	let button: ControllerButton
	let pressed: Bool
}

/// Complete three-slot keyboard snapshots, captured from RC003 firmware 2671.
/// No hardware autorepeat: held controls remain down until an explicit release.
nonisolated struct XiaomiRemoteReportDecoder: Sendable {
	static let buttonsByUsage: [UInt16: ControllerButton] = [
		0x52: .dpadUp, 0x51: .dpadDown, 0x50: .dpadLeft, 0x4F: .dpadRight,
		0x28: .xiaomiOK, 0xF1: .xiaomiBack, 0x4A: .xiaomiHome, 0x65: .xiaomiMenu,
		0x80: .xiaomiVolumeUp, 0x81: .xiaomiVolumeDown, 0x35: .xiaomiTV,
		0x3E: .xiaomiMicrophone, 0x66: .xiaomiPower,
	]
	private(set) var heldUsages: Set<UInt16> = []

	/// Reject malformed/vendor/error-rollover packets without releasing a hold.
	static func usages(report: [UInt8], reportID: UInt32 = 1) -> Set<UInt16>? {
		guard reportID == 1 else { return nil }
		let payload: ArraySlice<UInt8>
		if report.count == 7, report.first == 1 { payload = report.dropFirst() }
		else if report.count == 6 { payload = report[...] }
		else { return nil }
		let bytes = Array(payload)
		let keys = stride(from: 0, to: 6, by: 2).map {
			UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8
		}
		guard keys.allSatisfy({ $0 <= 254 && !(1...3).contains($0) }) else { return nil }
		return Set(keys.filter { $0 != 0 })
	}

	mutating func process(report: [UInt8], reportID: UInt32 = 1) -> [XiaomiRemoteButtonEvent] {
		guard let next = Self.usages(report: report, reportID: reportID) else { return [] }
		let releases = events(heldUsages.subtracting(next), pressed: false)
		let presses = events(next.subtracting(heldUsages), pressed: true)
		heldUsages = next
		return releases + presses
	}

	mutating func reset() -> [XiaomiRemoteButtonEvent] {
		let result = events(heldUsages, pressed: false)
		heldUsages.removeAll()
		return result
	}

	private func events(_ usages: Set<UInt16>, pressed: Bool) -> [XiaomiRemoteButtonEvent] {
		usages.sorted().compactMap { usage in
			Self.buttonsByUsage[usage].map { XiaomiRemoteButtonEvent(button: $0, pressed: pressed) }
		}
	}
}
