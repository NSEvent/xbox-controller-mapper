import CoreGraphics

/// Remembers whether each held key and modifier was delivered to this Mac or
/// to the Universal Control peer, so its release takes the same route even
/// when the cursor crosses a screen edge while it is held. Deciding the route
/// again at release time sends a local key-up to the peer (leaving the key
/// stuck down here) or a peer key-up to this Mac.
///
/// Not thread-safe; the owner guards it with its own lock.
struct HeldOutputRoutes {
	enum Route: Equatable {
		case local
		case remote
	}

	private var keyRoutes: [CGKeyCode: Route] = [:]
	private var remoteModifierCounts: [UInt64: Int] = [:]

	mutating func keyPressed(_ keyCode: CGKeyCode, route: Route) {
		keyRoutes[keyCode] = route
	}

	/// The route the key was pressed on, or nil if its press was never seen.
	mutating func keyReleased(_ keyCode: CGKeyCode) -> Route? {
		keyRoutes.removeValue(forKey: keyCode)
	}

	mutating func modifierPressedRemotely(mask: UInt64) {
		remoteModifierCounts[mask, default: 0] += 1
	}

	func remoteModifierCount(mask: UInt64) -> Int {
		remoteModifierCounts[mask] ?? 0
	}

	/// Picks the route for releasing one hold of `mask`. `totalCount` is the
	/// owner's combined local and remote reference count for the mask. Counts
	/// are per mask, not per press, so when both routes hold the same mask the
	/// release follows where output is currently going.
	mutating func modifierReleaseRoute(mask: UInt64, totalCount: Int, relaying: Bool) -> Route {
		let remote = remoteModifierCounts[mask] ?? 0
		let local = max(0, totalCount - remote)
		if remote > 0, relaying || local == 0 {
			remoteModifierCounts[mask] = remote - 1
			return .remote
		}
		if local > 0 { return .local }
		return relaying ? .remote : .local
	}

	/// Forgets every remote hold, returning what was outstanding so the owner
	/// can release it on the peer and drop it from its own counts.
	mutating func takeRemoteHolds() -> (keys: [CGKeyCode], modifierCounts: [UInt64: Int]) {
		let keys = keyRoutes.filter { $0.value == .remote }.map(\.key).sorted()
		for key in keys { keyRoutes.removeValue(forKey: key) }
		let modifiers = remoteModifierCounts.filter { $0.value > 0 }
		remoteModifierCounts.removeAll()
		return (keys, modifiers)
	}

	/// Forgets remote modifier holds only; used after a peer-wide modifier release.
	mutating func clearRemoteModifiers() -> [UInt64: Int] {
		defer { remoteModifierCounts.removeAll() }
		return remoteModifierCounts.filter { $0.value > 0 }
	}
}
