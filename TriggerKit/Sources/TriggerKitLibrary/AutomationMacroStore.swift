import Foundation
import TriggerKitCore

public extension Notification.Name {
	static let triggerKitMacrosChanged = Notification.Name("com.kevintang.TriggerKit.macrosChanged")
}

public enum AutomationMacroImportStrategy: Sendable {
	case keepExisting
	case replaceExisting
}

public final class AutomationMacroStore {
	public static let shared = AutomationMacroStore()

	public static var defaultFileURL: URL {
		FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("TriggerKit", isDirectory: true)
			.appendingPathComponent("macros.json")
	}

	public let fileURL: URL

	private let queue = DispatchQueue(label: "com.kevintang.TriggerKit.macros", qos: .utility)
	/// Serializes JSON encodes and disk writes off the state queue, so
	/// `queue.sync` lookups from latency-sensitive consumer paths (e.g.
	/// controller button dispatch) never wait behind file I/O.
	private let ioQueue = DispatchQueue(label: "com.kevintang.TriggerKit.macros.io", qos: .utility)
	private let notificationCenter: NotificationCenter
	private let distributedNotificationCenter: DistributedNotificationCenter?
	private var macros: [UUID: AutomationMacro] = [:]
	private var pendingWrite: DispatchWorkItem?

	public convenience init() {
		self.init(fileURL: Self.defaultFileURL)
	}

	public init(
		fileURL: URL,
		notificationCenter: NotificationCenter = .default,
		distributedNotificationCenter: DistributedNotificationCenter? = .default()
	) {
		self.fileURL = fileURL
		self.notificationCenter = notificationCenter
		self.distributedNotificationCenter = distributedNotificationCenter
		try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		loadFromDisk()
	}

	public func all() -> [AutomationMacro] {
		queue.sync {
			Array(macros.values).sorted {
				$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
			}
		}
	}

	public func macro(id: UUID) -> AutomationMacro? {
		queue.sync { macros[id] }
	}

	public func resolve(_ reference: AutomationMacroReference, fallbackName: String) -> AutomationProgram? {
		let macro: AutomationMacro?
		if let macroID = reference.macroID {
			macro = self.macro(id: macroID)
		} else {
			macro = nil
		}
		return reference.resolvedProgram(macro: macro, fallbackName: fallbackName)
	}

	@discardableResult
	public func create(name: String, program: AutomationProgram) -> AutomationMacro {
		let macro = AutomationMacro(name: name, program: program)
		upsert(macro)
		return macro
	}

	@discardableResult
	public func duplicate(id: UUID) -> AutomationMacro? {
		guard let original = macro(id: id) else { return nil }
		var copy = AutomationMacro(
			name: "\(original.name) Copy",
			program: original.program,
			createdAt: Date(),
			updatedAt: Date()
		)
		copy.program.name = copy.name
		upsert(copy)
		return copy
	}

	public func upsert(_ macro: AutomationMacro) {
		let normalized = normalizedMacro(macro, updatedAt: Date())
		queue.sync {
			macros[normalized.id] = normalized
			scheduleWriteLocked()
		}
		postChanged()
	}

	@discardableResult
	public func remove(id: UUID) -> Bool {
		let removed: Bool = queue.sync {
			guard macros.removeValue(forKey: id) != nil else { return false }
			scheduleWriteLocked()
			return true
		}
		if removed { postChanged() }
		return removed
	}

	@discardableResult
	public func importMacros(
		_ incoming: [AutomationMacro],
		strategy: AutomationMacroImportStrategy = .keepExisting
	) -> Int {
		let imported: Int = queue.sync {
			var count = 0
			for macro in incoming {
				if strategy == .keepExisting, macros[macro.id] != nil {
					continue
				}
				macros[macro.id] = normalizedMacro(macro, updatedAt: macro.updatedAt)
				count += 1
			}
			if count > 0 {
				scheduleWriteLocked()
			}
			return count
		}
		if imported > 0 { postChanged() }
		return imported
	}

	@discardableResult
	public func migrateFromLegacyFile(
		at legacyURL: URL,
		strategy: AutomationMacroImportStrategy = .keepExisting
	) -> Int {
		guard FileManager.default.fileExists(atPath: legacyURL.path) else { return 0 }
		do {
			let data = try Data(contentsOf: legacyURL)
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			let decoded = try decoder.decode([AutomationMacro].self, from: data)
			return importMacros(decoded, strategy: strategy)
		} catch {
			return 0
		}
	}

	public func flush() {
		let snapshot: [AutomationMacro] = queue.sync {
			pendingWrite?.cancel()
			pendingWrite = nil
			return Array(macros.values)
		}
		ioQueue.sync {
			persist(snapshot)
		}
	}

	/// Re-reads the backing file, replacing in-memory state. Call when
	/// another process signals a change via `.triggerKitMacrosChanged` on the
	/// distributed notification center. Skipped while a local write is
	/// pending — the local state is about to land on disk and will post its
	/// own change notification.
	public func reloadFromDisk() {
		let reloaded: Bool = queue.sync {
			guard pendingWrite == nil else { return false }
			loadFromDiskLocked()
			return true
		}
		if reloaded {
			notificationCenter.post(name: .triggerKitMacrosChanged, object: self)
		}
	}

	private func loadFromDisk() {
		loadFromDiskLocked()
	}

	/// Replaces `macros` from the backing file. Callers must either own
	/// `queue` or be in single-threaded setup (init).
	private func loadFromDiskLocked() {
		guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
		do {
			let data = try Data(contentsOf: fileURL)
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			let decoded = try decoder.decode([AutomationMacro].self, from: data)
			macros = decoded.reduce(into: [:]) { result, macro in
				result[macro.id] = normalizedMacro(macro, updatedAt: macro.updatedAt)
			}
		} catch {
			let broken = fileURL.deletingLastPathComponent()
				.appendingPathComponent("macros.broken.\(Int(Date().timeIntervalSince1970)).json")
			try? FileManager.default.moveItem(at: fileURL, to: broken)
			macros = [:]
		}
	}

	private func normalizedMacro(_ macro: AutomationMacro, updatedAt: Date) -> AutomationMacro {
		AutomationMacro(
			id: macro.id,
			name: macro.name,
			program: macro.program,
			createdAt: macro.createdAt,
			updatedAt: updatedAt
		)
	}

	private func scheduleWriteLocked() {
		pendingWrite?.cancel()
		let work = DispatchWorkItem { [weak self] in
			guard let self else { return }
			// Snapshot under the state queue, then encode/write on ioQueue.
			let snapshot = Array(self.macros.values)
			self.pendingWrite = nil
			self.ioQueue.async {
				self.persist(snapshot)
			}
		}
		pendingWrite = work
		queue.asyncAfter(deadline: .now() + 0.5, execute: work)
	}

	private func persist(_ snapshot: [AutomationMacro]) {
		do {
			try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			encoder.dateEncodingStrategy = .iso8601
			let data = try encoder.encode(snapshot.sorted {
				$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
			})
			try atomicWrite(data, to: fileURL)
			// Other processes read from disk, so they are told only once the
			// file is actually current. Posting on upsert instead (as before)
			// raced the debounced write: observers re-read a stale file and
			// missed the final state, and got one notification per keystroke
			// while editing.
			distributedNotificationCenter?.postNotificationName(.triggerKitMacrosChanged, object: nil)
		} catch {
			NSLog("TriggerKit macro write failed: %@", String(describing: error))
		}
	}

	private func atomicWrite(_ data: Data, to url: URL) throws {
		let tmp = url.deletingLastPathComponent()
			.appendingPathComponent(".macros.\(UUID().uuidString).tmp")
		try data.write(to: tmp, options: .atomic)
		let fm = FileManager.default
		if fm.fileExists(atPath: url.path) {
			_ = try fm.replaceItemAt(url, withItemAt: tmp)
		} else {
			try fm.moveItem(at: tmp, to: url)
		}
	}

	/// In-process observers read the store's in-memory state, so they are
	/// notified immediately on every mutation. The distributed notification
	/// is posted from `persist` after the file lands (see there for why).
	private func postChanged() {
		notificationCenter.post(name: .triggerKitMacrosChanged, object: self)
	}
}
