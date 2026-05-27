import Foundation
import GameController
import IOKit
import IOKit.hid

enum ControllerIdentityResolver {
    static func identity(for controller: GCController, preferredDevice: IOHIDDevice? = nil) -> ControllerIdentity {
        let fallbackName = controller.vendorName ?? controller.productCategory
        if let preferredDevice {
            return identity(for: preferredDevice, fallbackName: fallbackName)
        }

        let candidates = matchingHIDIdentities(
            vendorName: controller.vendorName,
            productCategory: controller.productCategory
        )
        return resolvedIdentity(candidates: candidates, fallbackName: fallbackName)
    }

    static func resolvedIdentity(
        candidates: [ControllerIdentity],
        fallbackName: String?
    ) -> ControllerIdentity {
        let uniqueCandidates = uniquePhysicalIdentities(candidates)
        if uniqueCandidates.count == 1 {
            return uniqueCandidates[0]
        }

        if let ambiguousFallback = ambiguousFallbackIdentity(
            from: uniqueCandidates.isEmpty ? candidates : uniqueCandidates,
            fallbackName: fallbackName
        ) {
            return ambiguousFallback
        }

        return fallbackIdentity(
            vendorId: nil,
            productId: nil,
            productName: fallbackName,
            transport: nil
        )
    }

    static func hasSinglePhysicalIdentity(_ candidates: [ControllerIdentity]) -> Bool {
        let uniqueCandidates = uniquePhysicalIdentities(candidates)
        guard uniqueCandidates.count == 1 else { return false }
        return uniqueCandidates[0].hasStableId || candidates.count == 1
    }

    static func devicesForSinglePhysicalIdentity<Device>(
        devices: [Device],
        identities: [ControllerIdentity]
    ) -> [Device] {
        guard devices.count == identities.count,
              hasSinglePhysicalIdentity(identities) else {
            return []
        }
        return devices
    }

    static func identity(for device: IOHIDDevice, fallbackName: String? = nil) -> ControllerIdentity {
        let vendorId = intProperty(device, kIOHIDVendorIDKey)
        let productId = intProperty(device, kIOHIDProductIDKey)
        let productName = stringProperty(device, kIOHIDProductKey) ?? fallbackName
        let transport = stringProperty(device, kIOHIDTransportKey)
        let serialNumber = normalizedSerial(stringProperty(device, kIOHIDSerialNumberKey))
        let deviceAddress = normalizedDeviceAddress(
            stringProperty(device, "DeviceAddress")
            ?? stringProperty(device, "BluetoothDeviceAddress")
            ?? registryStringProperty(device, "DeviceAddress")
        )

        let stableId: String?
        if let serialNumber {
            stableId = "serial:\(serialNumber)"
        } else if let deviceAddress {
            stableId = "deviceAddress:\(deviceAddress)"
        } else {
            stableId = nil
        }

        return ControllerIdentity(
            stableId: stableId,
            fallbackId: fallbackId(
                vendorId: vendorId,
                productId: productId,
                productName: productName,
                transport: transport
            ),
            vendorId: vendorId,
            productId: productId,
            productName: productName,
            transport: transport,
            serialNumber: serialNumber,
            deviceAddress: deviceAddress
        )
    }

    private static func matchingHIDIdentities(
        vendorName: String?,
        productCategory: String
    ) -> [ControllerIdentity] {
        allControllerDevices()
            .map { identity(for: $0, fallbackName: vendorName ?? productCategory) }
            .filter { identity in
                let haystack = [
                    identity.productName,
                    identity.fallbackId
                ]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")

                let needles = [vendorName, productCategory]
                    .compactMap { $0?.lowercased() }
                    .filter { !$0.isEmpty }

                let productName = identity.productName?.lowercased()
                return needles.contains { needle in
                    haystack.contains(needle)
                        || productName.map { !$0.isEmpty && needle.contains($0) } == true
                }
            }
    }

    private static func allControllerDevices() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let gamepad = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad
        ] as CFDictionary
        let joystick = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick
        ] as CFDictionary
        IOHIDManagerSetDeviceMatchingMultiple(manager, [gamepad, joystick] as CFArray)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        return (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>).map(Array.init) ?? []
    }

    private static func uniquePhysicalIdentities(_ candidates: [ControllerIdentity]) -> [ControllerIdentity] {
        var seenKeys = Set<String>()
        var uniqueCandidates: [ControllerIdentity] = []

        for candidate in candidates {
            let key = candidate.stableId.map { "stable:\($0)" } ?? "fallback:\(candidate.fallbackId)"
            if seenKeys.insert(key).inserted {
                uniqueCandidates.append(candidate)
            }
        }

        return uniqueCandidates
    }

    private static func ambiguousFallbackIdentity(
        from candidates: [ControllerIdentity],
        fallbackName: String?
    ) -> ControllerIdentity? {
        guard let first = candidates.first,
              candidates.allSatisfy({ $0.fallbackId == first.fallbackId }) else {
            return nil
        }

        return ControllerIdentity(
            stableId: nil,
            fallbackId: first.fallbackId,
            vendorId: first.vendorId,
            productId: first.productId,
            productName: first.productName ?? fallbackName,
            transport: first.transport,
            serialNumber: nil,
            deviceAddress: nil
        )
    }

    private static func fallbackIdentity(
        vendorId: Int?,
        productId: Int?,
        productName: String?,
        transport: String?
    ) -> ControllerIdentity {
        ControllerIdentity(
            stableId: nil,
            fallbackId: fallbackId(
                vendorId: vendorId,
                productId: productId,
                productName: productName,
                transport: transport
            ),
            vendorId: vendorId,
            productId: productId,
            productName: productName,
            transport: transport,
            serialNumber: nil,
            deviceAddress: nil
        )
    }

    private static func fallbackId(
        vendorId: Int?,
        productId: Int?,
        productName: String?,
        transport: String?
    ) -> String {
        let vendor = vendorId.map { String(format: "%04x", $0) } ?? "unknown"
        let product = productId.map { String(format: "%04x", $0) } ?? "unknown"
        let name = (productName ?? "controller")
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let transport = transport?.lowercased() ?? "unknown"
        return "hid:\(vendor):\(product):\(name):\(transport)"
    }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        IOHIDDeviceGetProperty(device, key as CFString) as? Int
    }

    private static func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private static func normalizedSerial(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func normalizedDeviceAddress(_ value: String?) -> String? {
        let cleaned = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: ":")
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    private static func registryStringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
        let service = IOHIDDeviceGetService(device)
        guard service != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
}
