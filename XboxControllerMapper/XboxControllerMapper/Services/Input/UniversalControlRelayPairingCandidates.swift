import Foundation

/// Discovery can reach several Macs (and several addresses for each Mac).
/// Keep every response until the user chooses a Mac by its displayed code.
struct UniversalControlRelayPairingCandidates<ID: Hashable, Value> {
	enum Selection {
		case notWaiting
		case wrongCode
		case ambiguous
		case matched(Value)
	}

	private struct Entry {
		let code: String
		let keyData: Data
		let value: Value
	}

	private var searchID: String?
	private var expiresAt = Date.distantPast
	private var entries: [ID: Entry] = [:]

	var hasCandidates: Bool { !entries.isEmpty }

	mutating func start(searchID: String, now: Date = Date()) {
		reset()
		self.searchID = searchID
		expiresAt = now.addingTimeInterval(60)
	}

	func isActive(searchID: String, now: Date = Date()) -> Bool {
		self.searchID == searchID && now < expiresAt
	}

	func ownsSearch(searchID: String) -> Bool {
		self.searchID == searchID
	}

	/// Returns nil for a stale response, true for the first response, false thereafter.
	mutating func add(
		id: ID, searchID: String, code: String, keyData: Data,
		value: Value, now: Date = Date()
	) -> Bool? {
		guard isActive(searchID: searchID, now: now) else { return nil }
		let isFirst = entries.isEmpty
		entries[id] = Entry(code: code, keyData: keyData, value: value)
		return isFirst
	}

	mutating func remove(id: ID) {
		entries.removeValue(forKey: id)
	}

	func select(code: String, now: Date = Date()) -> Selection {
		guard now < expiresAt, !entries.isEmpty else { return .notWaiting }
		let matches = entries.values.filter { $0.code == code }
		guard let first = matches.first else { return .wrongCode }
		// Aliases of one handshake share a key. A six-digit collision between
		// different handshakes must never silently choose an arbitrary Mac.
		guard matches.allSatisfy({ $0.keyData == first.keyData }) else { return .ambiguous }
		return .matched(first.value)
	}

	mutating func reset() {
		searchID = nil
		expiresAt = .distantPast
		entries.removeAll()
	}
}
