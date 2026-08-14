import AppKit
import Foundation
import IOKit
import IOKit.hid
import UniformTypeIdentifiers

struct ControllerSupportDumpDeviceIdentity: Equatable {
	let productName: String
	let manufacturer: String
	let vendorID: Int
	let productID: Int
	let version: Int
	let transport: String
	let locationID: Int
	let interfaceNumber: Int?
	let primaryUsagePage: Int
	let primaryUsage: Int
	let registryEntryID: UInt64

	var displayName: String {
		let name = productName.isEmpty ? "Unknown HID Device" : productName
		let maker = manufacturer.isEmpty ? nil : manufacturer
		let vendorProduct = "\(Self.hex(vendorID)):\(Self.hex(productID))"
		let interface = interfaceNumber.map { "Interface \($0)" }
			?? "Usage \(Self.hex(primaryUsagePage)):\(Self.hex(primaryUsage))"
		return [maker, name, transport.isEmpty ? nil : transport, vendorProduct, interface]
			.compactMap { $0 }
			.joined(separator: " - ")
	}

	var stableKey: String {
		"\(vendorID):\(productID):\(version):\(transport):\(locationID):\(productName):\(interfaceNumber ?? -1):\(primaryUsagePage):\(primaryUsage):\(registryEntryID)"
	}

	var jsonObject: [String: Any] {
		[
			"displayName": displayName,
			"productName": productName,
			"manufacturer": manufacturer,
			"vendorID": vendorID,
			"vendorIDHex": Self.hex(vendorID),
			"productID": productID,
			"productIDHex": Self.hex(productID),
			"version": version,
			"versionHex": Self.hex(version),
			"transport": transport,
			"interfaceNumber": interfaceNumber.map { $0 as Any } ?? NSNull(),
			"primaryUsagePage": primaryUsagePage,
			"primaryUsage": primaryUsage,
			"registryEntryID": NSNumber(value: registryEntryID),
		]
	}

	static func removingDuplicates(from identities: [Self]) -> [Self] {
		var seen = Set<String>()
		return identities.filter { insertIfNew($0, into: &seen) }
	}

	static func insertIfNew(_ identity: Self, into seen: inout Set<String>) -> Bool {
		seen.insert(identity.stableKey).inserted
	}

	private static func hex(_ value: Int) -> String {
		String(format: "0x%04X", value)
	}
}

@MainActor
enum ControllerSupportDumpService {
	private struct DeviceCandidate {
		let device: IOHIDDevice
		let identity: ControllerSupportDumpDeviceIdentity

		init(device: IOHIDDevice) {
			self.device = device
			self.identity = ControllerSupportDumpDeviceIdentity(
				productName: ControllerSupportDumpService.stringProperty(device, kIOHIDProductKey as CFString),
				manufacturer: ControllerSupportDumpService.stringProperty(device, kIOHIDManufacturerKey as CFString),
				vendorID: ControllerSupportDumpService.intProperty(device, kIOHIDVendorIDKey as CFString) ?? 0,
				productID: ControllerSupportDumpService.intProperty(device, kIOHIDProductIDKey as CFString) ?? 0,
				version: ControllerSupportDumpService.intProperty(device, kIOHIDVersionNumberKey as CFString) ?? 0,
				transport: ControllerSupportDumpService.stringProperty(device, kIOHIDTransportKey as CFString),
				locationID: ControllerSupportDumpService.intProperty(device, kIOHIDLocationIDKey as CFString) ?? 0,
				interfaceNumber: ControllerSupportDumpService.interfaceNumber(for: device),
				primaryUsagePage: ControllerSupportDumpService.intProperty(device, kIOHIDPrimaryUsagePageKey as CFString) ?? 0,
				primaryUsage: ControllerSupportDumpService.intProperty(device, kIOHIDPrimaryUsageKey as CFString) ?? 0,
				registryEntryID: ControllerSupportDumpService.registryEntryID(for: device)
			)
		}

		var productName: String { identity.productName }
		var vendorID: Int { identity.vendorID }
		var productID: Int { identity.productID }
		var version: Int { identity.version }
		var transport: String { identity.transport }
		var displayName: String { identity.displayName }
	}

	static func runInteractiveDump() {
		let devices = connectedDevices()
		guard !devices.isEmpty else {
			showAlert(
				title: "No HID Controllers Found",
				message: "Connect the controller over Bluetooth or USB, then run Controller Support Dump again."
			)
			return
		}
		guard let selectedDevice = selectDevice(from: devices),
			  let outputURL = chooseOutputURL(for: selectedDevice) else {
			return
		}

		do {
			let package = try makeDumpPackage(for: selectedDevice)
			let jsonURL = outputURL.deletingPathExtension().appendingPathExtension("json")
			try package.markdown.write(to: outputURL, atomically: true, encoding: .utf8)
			try package.jsonData.write(to: jsonURL, options: [.atomic])
			NSWorkspace.shared.activateFileViewerSelecting([outputURL, jsonURL])
			showAlert(
				title: "Controller Support Dump Saved",
				message: "Saved the AI prompt and raw JSON dump:\n\n\(outputURL.path)\n\(jsonURL.path)"
			)
		} catch {
			showAlert(
				title: "Controller Support Dump Failed",
				message: error.localizedDescription
			)
		}
	}

	private static func connectedDevices() -> [DeviceCandidate] {
		let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
		let steamControllerCriteria = SteamControllerHIDParser.productIDs.map { productID in
			[
				kIOHIDVendorIDKey as String: SteamControllerHIDParser.valveVendorID,
				kIOHIDProductIDKey as String: productID,
			] as CFDictionary
		}
		let knownMappingCriteria = GameControllerDatabase.shared
			.knownVendorProductPairs()
			.map { pair in
				[
					kIOHIDVendorIDKey as String: pair.vendorID,
					kIOHIDProductIDKey as String: pair.productID,
				] as CFDictionary
			}
		let standardControllerCriteria = [
			[
				kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
				kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Joystick,
			],
			[
				kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
				kIOHIDDeviceUsageKey as String: kHIDUsage_GD_GamePad,
			],
			[
				kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
				kIOHIDDeviceUsageKey as String: kHIDUsage_GD_MultiAxisController,
			],
		].map { $0 as CFDictionary }
		let bluetoothLECriteria = [
			[
				kIOHIDTransportKey as String: "BluetoothLowEnergy",
			],
			[
				kIOHIDTransportKey as String: "Bluetooth Low Energy",
			],
		].map { $0 as CFDictionary }

		IOHIDManagerSetDeviceMatchingMultiple(
			manager,
			(steamControllerCriteria + knownMappingCriteria + standardControllerCriteria + bluetoothLECriteria) as CFArray
		)
		IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
		defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

		let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>).map(Array.init) ?? []
		var seen = Set<String>()
		return devices
			.map(DeviceCandidate.init(device:))
			.filter(isDumpCandidate)
			.filter { ControllerSupportDumpDeviceIdentity.insertIfNew($0.identity, into: &seen) }
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
	}

	private static func selectDevice(from devices: [DeviceCandidate]) -> DeviceCandidate? {
		let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 460, height: 28), pullsDown: false)
		devices.forEach { popup.addItem(withTitle: $0.displayName) }

		let alert = NSAlert()
		alert.messageText = "Select Controller"
		alert.informativeText = "Choose the Bluetooth or USB controller to dump."
		alert.accessoryView = popup
		alert.alertStyle = .informational
		alert.addButton(withTitle: "Create Dump")
		alert.addButton(withTitle: "Cancel")

		guard alert.runModal() == .alertFirstButtonReturn else { return nil }
		return devices[popup.indexOfSelectedItem]
	}

	private static func isDumpCandidate(_ candidate: DeviceCandidate) -> Bool {
		let isSteamController = candidate.vendorID == SteamControllerHIDParser.valveVendorID
			&& SteamControllerHIDParser.productIDs.contains(candidate.productID)
		let hasKnownMapping = GameControllerDatabase.shared.hasKnownVendorProduct(
			vendorID: candidate.vendorID,
			productID: candidate.productID
		)
		return isSteamController
			|| (hasKnownMapping && GenericHIDController.canUseKnownMapping(from: candidate.device))
			|| GenericHIDController.canInferMapping(from: candidate.device)
	}

	private static func chooseOutputURL(for device: DeviceCandidate) -> URL? {
		let panel = NSSavePanel()
		panel.title = "Save Controller Support Dump"
		panel.nameFieldStringValue = defaultFilename(for: device)
		panel.allowedContentTypes = [UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText]
		panel.canCreateDirectories = true
		panel.isExtensionHidden = false
		return panel.runModal() == .OK ? panel.url : nil
	}

	private static func makeDumpPackage(for device: DeviceCandidate) throws -> (jsonData: Data, markdown: String) {
		let enumeration = HIDElementLayout.enumeration(for: device.device)
		let layout = enumeration?.layout
		let guid = GameControllerDatabase.constructGUID(
			vendorID: device.vendorID,
			productID: device.productID,
			version: device.version,
			transport: device.transport
		)
		let compatibleMapping = GameControllerDatabase.shared.lookup(
			vendorID: device.vendorID,
			productID: device.productID,
			version: device.version,
			transport: device.transport,
			compatibleWith: layout
		)

		let dump: [String: Any] = [
			"schemaVersion": 1,
			"generatedAt": ISO8601DateFormatter().string(from: Date()),
			"app": [
				"name": Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "ControllerKeys",
				"version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
				"build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
			],
			"system": [
				"operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
			],
			"device": deviceInfo(for: device),
			"sdl": [
				"constructedMacGUID": guid,
				"knownVendorProduct": GameControllerDatabase.shared.hasKnownVendorProduct(
					vendorID: device.vendorID,
					productID: device.productID
				),
				"compatibleMapping": mappingInfo(compatibleMapping),
			],
			"hidLayout": layoutInfo(enumeration),
			"privacy": [
				"serialNumberIncluded": false,
				"locationIDIncluded": false,
			],
		]

		let jsonData = try JSONSerialization.data(
			withJSONObject: dump,
			options: [.prettyPrinted, .sortedKeys]
		)
		guard let jsonText = String(data: jsonData, encoding: .utf8) else {
			throw DumpError.invalidJSON
		}

		return (jsonData, markdownPrompt(device: device, jsonText: jsonText))
	}

	private static func deviceInfo(for device: DeviceCandidate) -> [String: Any] {
		var info = device.identity.jsonObject
		info["usagePairs"] = usagePairs(for: device.device)
		info["maxInputReportSize"] = jsonValue(
			intProperty(device.device, kIOHIDMaxInputReportSizeKey as CFString)
		)
		return info
	}

	private static func layoutInfo(_ enumeration: HIDElementEnumeration?) -> [String: Any] {
		guard let enumeration else {
			return [
				"available": false,
				"buttonCount": 0,
				"axisCount": 0,
				"hasHat": false,
				"buttons": [],
				"axes": [],
			]
		}

		var info: [String: Any] = [
			"available": true,
			"buttonCount": enumeration.layout.buttonCount,
			"axisCount": enumeration.layout.axisCount,
			"hasHat": enumeration.layout.hasHat,
			"buttons": enumeration.buttonElements.enumerated().map { index, element in
				elementInfo(element, sdlRef: "b\(index)")
			},
			"axes": enumeration.axisElements.enumerated().map { index, element in
				elementInfo(element, sdlRef: "a\(index)")
			},
		]

		if let hatElement = enumeration.hatElement {
			info["hat"] = elementInfo(hatElement, sdlRef: "h0")
		}
		return info
	}

	private static func mappingInfo(_ mapping: SDLControllerMapping?) -> Any {
		guard let mapping else { return NSNull() }
		return [
			"guid": mapping.guid,
			"name": mapping.name,
			"platform": mapping.platform,
			"buttons": mapping.buttonMap.mapValues(sdlRefDescription),
			"axes": mapping.axisMap.mapValues(sdlRefDescription),
		]
	}

	private static func usagePairs(for device: IOHIDDevice) -> [[String: Any]] {
		guard let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] else {
			return []
		}
		return pairs.compactMap { pair in
			guard let usagePage = intValue(pair[kIOHIDDeviceUsagePageKey as String]),
				  let usage = intValue(pair[kIOHIDDeviceUsageKey as String]) else {
				return nil
			}
			return [
				"usagePage": usagePage,
				"usagePageHex": hex(usagePage),
				"usage": usage,
				"usageHex": hex(usage),
			]
		}
	}

	private static func elementInfo(_ element: IOHIDElement, sdlRef: String) -> [String: Any] {
		let usagePage = Int(IOHIDElementGetUsagePage(element))
		let usage = Int(IOHIDElementGetUsage(element))
		return [
			"sdlRef": sdlRef,
			"cookie": Int(IOHIDElementGetCookie(element)),
			"type": elementTypeName(IOHIDElementGetType(element)),
			"usagePage": usagePage,
			"usagePageHex": hex(usagePage),
			"usage": usage,
			"usageHex": hex(usage),
			"logicalMin": Int(IOHIDElementGetLogicalMin(element)),
			"logicalMax": Int(IOHIDElementGetLogicalMax(element)),
			"physicalMin": Int(IOHIDElementGetPhysicalMin(element)),
			"physicalMax": Int(IOHIDElementGetPhysicalMax(element)),
			"reportID": Int(IOHIDElementGetReportID(element)),
			"reportSize": Int(IOHIDElementGetReportSize(element)),
			"reportCount": Int(IOHIDElementGetReportCount(element)),
		]
	}

	private static func markdownPrompt(device: DeviceCandidate, jsonText: String) -> String {
		"""
		# ControllerKeys Controller Support Dump

		Device: \(device.displayName)

		## AI prompt

		```text
		You are helping add macOS controller support to ControllerKeys, a macOS app that uses SDL gamecontrollerdb rows for generic HID controllers.

		Use the JSON dump below to propose a safe `platform:Mac OS X` SDL mapping row. Only reference SDL elements that exist in `hidLayout`: buttons as `b0...`, axes as `a0...`, and hat as `h0.<direction>`. If adapting a non-macOS row, reject or rewrite any reference that is not present in the macOS HID layout. Do not invent missing buttons or axes.

		Return:
		1. A candidate `gamecontrollerdb.txt` row.
		2. A short explanation of which refs are supported by the dump.
		3. Any buttons that still need manual press testing.

		JSON dump:
		\(jsonText)
		```

		## Raw JSON

		```json
		\(jsonText)
		```
		"""
	}

	private static func defaultFilename(for device: DeviceCandidate) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyyMMdd-HHmmss"
		let name = sanitizedFilenameComponent(device.productName.isEmpty ? "controller" : device.productName)
		return "controller-support-dump-\(name)-\(formatter.string(from: Date())).md"
	}

	private static func sanitizedFilenameComponent(_ value: String) -> String {
		let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
		let scalars = value.unicodeScalars.map { scalar in
			allowed.contains(scalar) ? Character(scalar) : "-"
		}
		let collapsed = String(scalars).split(separator: "-").joined(separator: "-")
		return collapsed.isEmpty ? "controller" : collapsed
	}

	private static func sdlRefDescription(_ ref: SDLElementRef) -> String {
		switch ref {
		case let .button(index):
			return "b\(index)"
		case let .axis(index, inverted, polarity):
			let prefix: String
			switch polarity {
			case .full:
				prefix = ""
			case .positive:
				prefix = "+"
			case .negative:
				prefix = "-"
			}
			return "\(prefix)a\(index)\(inverted ? "~" : "")"
		case let .hat(index, direction):
			return "h\(index).\(direction.rawValue)"
		}
	}

	private static func elementTypeName(_ type: IOHIDElementType) -> String {
		switch type {
		case kIOHIDElementTypeInput_Misc:
			return "inputMisc"
		case kIOHIDElementTypeInput_Button:
			return "inputButton"
		case kIOHIDElementTypeInput_Axis:
			return "inputAxis"
		case kIOHIDElementTypeInput_ScanCodes:
			return "inputScanCodes"
		case kIOHIDElementTypeOutput:
			return "output"
		case kIOHIDElementTypeFeature:
			return "feature"
		case kIOHIDElementTypeCollection:
			return "collection"
		default:
			return "unknown"
		}
	}

	private static func showAlert(title: String, message: String) {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.alertStyle = .informational
		alert.addButton(withTitle: "OK")
		alert.runModal()
	}

	private static func intProperty(_ device: IOHIDDevice, _ key: CFString) -> Int? {
		intValue(IOHIDDeviceGetProperty(device, key))
	}

	private static func stringProperty(_ device: IOHIDDevice, _ key: CFString) -> String {
		IOHIDDeviceGetProperty(device, key) as? String ?? ""
	}

	private static func interfaceNumber(for device: IOHIDDevice) -> Int? {
		for key in ["bInterfaceNumber", "InterfaceNumber", "USB Interface Number"] {
			if let value = intProperty(device, key as CFString) {
				return value
			}
		}
		return nil
	}

	private static func registryEntryID(for device: IOHIDDevice) -> UInt64 {
		let service = IOHIDDeviceGetService(device)
		guard service != 0 else { return 0 }
		var entryID: UInt64 = 0
		guard IORegistryEntryGetRegistryEntryID(service, &entryID) == kIOReturnSuccess else { return 0 }
		return entryID
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

	private static func jsonValue(_ value: Int?) -> Any {
		if let value {
			return value
		}
		return NSNull()
	}

	private static func hex(_ value: Int) -> String {
		String(format: "0x%04X", value)
	}

	private enum DumpError: LocalizedError {
		case invalidJSON

		var errorDescription: String? {
			switch self {
			case .invalidJSON:
				return "The controller dump could not be encoded as UTF-8 JSON."
			}
		}
	}
}
