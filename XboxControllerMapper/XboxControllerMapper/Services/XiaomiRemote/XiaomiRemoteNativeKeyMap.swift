import Foundation
import IOKit.hidsystem

/// Apple's TN2450 key-mapping API, scoped to the RC003 keyboard service.
/// Raw input reports remain unchanged; native keyboard translation is disabled.
@MainActor
final class XiaomiRemoteNativeKeyMap {
	typealias Map = [[String: UInt64]]
	private struct Lease {
		let service: IOHIDServiceClient
		let id: String
		let previous: Map
		let installed: Map
	}
	private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
	private var leases: [Lease] = []
	private let defaults: UserDefaults
	private static let journalKey = "XiaomiRemoteNativeKeyMapLeases"
	static let sourceKey = "HIDKeyboardModifierMappingSrc"
	static let destinationKey = "HIDKeyboardModifierMappingDst"
	static let propertyKey = "UserKeyMapping" as CFString

	init(defaults: UserDefaults = .standard) { self.defaults = defaults }

	static func blockingMap(previous: Map) -> Map {
		let sources = Set(XiaomiRemoteReportDecoder.buttonsByUsage.keys.map { UInt64($0) | 0x700000000 })
		return previous.filter { !sources.contains($0[sourceKey] ?? 0) } + sources.sorted().map {
			[sourceKey: $0, destinationKey: 0x700000000] // Keyboard Undefined
		}
	}

	/// Undo only our entries; preserve another remapper's changes made meanwhile.
	static func restoredMap(previous: Map, installed: Map, current: Map) -> Map {
		if current == installed { return previous }
		let sources = Set(XiaomiRemoteReportDecoder.buttonsByUsage.keys.map { UInt64($0) | 0x700000000 })
		let owned = installed.filter { sources.contains($0[sourceKey] ?? 0) && $0[destinationKey] == 0x700000000 }
		let removed = Set(owned.filter { current.contains($0) }.compactMap { $0[sourceKey] })
		let remaining = current.filter { !owned.contains($0) }
		let remainingSources = Set(remaining.compactMap { $0[sourceKey] })
		return remaining + previous.filter {
			guard let source = $0[sourceKey] else { return false }
			return removed.contains(source) && !remainingSources.contains(source)
		}
	}

	func acquire() -> Bool {
		guard leases.isEmpty else { return true }
		let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
		var journal = defaults.dictionary(forKey: Self.journalKey) ?? [:]
		for service in services {
			guard Self.matches(service) else { continue }
			let id = String(describing: IOHIDServiceClientGetRegistryID(service))
			var previous = IOHIDServiceClientCopyProperty(service, Self.propertyKey) as? Map ?? []
			// Recover our prior lease after a crash without treating the suppression
			// map as the user's original configuration on the next launch.
			if let saved = journal[id] as? [String: Map],
				let original = saved["previous"], let installed = saved["installed"] {
				previous = Self.restoredMap(previous: original, installed: installed, current: previous)
			}
			let installed = Self.blockingMap(previous: previous)
			journal[id] = ["previous": previous, "installed": installed]
			defaults.set(journal, forKey: Self.journalKey)
			guard IOHIDServiceClientSetProperty(service, Self.propertyKey, installed as CFArray),
				(IOHIDServiceClientCopyProperty(service, Self.propertyKey) as? Map) == installed else {
				if IOHIDServiceClientSetProperty(service, Self.propertyKey, previous as CFArray) {
					journal.removeValue(forKey: id)
				}
				defaults.set(journal, forKey: Self.journalKey)
				release()
				return false
			}
			leases.append(Lease(service: service, id: id, previous: previous, installed: installed))
		}
		return !leases.isEmpty
	}

	func release() {
		var journal = defaults.dictionary(forKey: Self.journalKey) ?? [:]
		for lease in leases {
			if let current = IOHIDServiceClientCopyProperty(lease.service, Self.propertyKey) as? Map {
				let restored = Self.restoredMap(previous: lease.previous, installed: lease.installed, current: current)
				if !IOHIDServiceClientSetProperty(lease.service, Self.propertyKey, restored as CFArray) {
					NSLog("[ControllerKeys] Xiaomi native key map restoration failed; retaining recovery journal")
					continue
				}
			}
			journal.removeValue(forKey: lease.id)
		}
		defaults.set(journal, forKey: Self.journalKey)
		leases.removeAll()
	}

	private static func matches(_ service: IOHIDServiceClient) -> Bool {
		(IOHIDServiceClientCopyProperty(service, "VendorID" as CFString) as? Int) == XiaomiRemoteIdentity.vendorID &&
		(IOHIDServiceClientCopyProperty(service, "ProductID" as CFString) as? Int) == XiaomiRemoteIdentity.productID &&
		XiaomiRemoteIdentity.transports.contains(IOHIDServiceClientCopyProperty(service, "Transport" as CFString) as? String ?? "") &&
		IOHIDServiceClientConformsTo(service, 1, 6) != 0
	}
}
