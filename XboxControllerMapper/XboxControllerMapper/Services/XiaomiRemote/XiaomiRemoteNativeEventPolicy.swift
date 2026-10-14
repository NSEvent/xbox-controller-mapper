import Foundation

/// Suppress only native edges correlated to this remote's timestamped HID
/// reports. Ordinary typing, synthetic mapped output, and unrelated media
/// events pass through. An unrelated down edge cancels autorepeat ownership.
nonisolated struct XiaomiRemoteNativeEventPolicy {
	enum Control: Hashable { case key(Int64), media(Int) }
	private struct Edge { let pressed: Bool; let time: TimeInterval }
	private var edges: [Control: [Edge]] = [:]
	private var repeatOwners: [Control: Int64] = [:]
	private var held: Set<Control> = []
	static let correlationWindow: TimeInterval = 0.005

	static func control(for button: ControllerButton) -> Control? {
		switch button {
		case .dpadUp: return .key(126)
		case .dpadDown: return .key(125)
		case .dpadLeft: return .key(123)
		case .dpadRight: return .key(124)
		case .xiaomiOK: return .key(36)
		case .xiaomiHome: return .key(115)
		case .xiaomiMenu: return .key(110)
		case .xiaomiTV: return .key(50)
		case .xiaomiMicrophone: return .key(96)
		case .xiaomiVolumeUp: return .media(0)
		case .xiaomiVolumeDown: return .media(1)
		case .xiaomiPower: return .media(6)
		default: return nil
		}
	}

	mutating func record(_ events: [XiaomiRemoteButtonEvent], heldButtons: Set<ControllerButton>, at time: TimeInterval) {
		// Both report and event callbacks can be queued during a busy UI frame.
		// Retain each edge so a release cannot overwrite its pending native down.
		edges = edges.mapValues { $0.filter { time - $0.time <= 2 } }.filter { !$0.value.isEmpty }
		held = Set(heldButtons.compactMap(Self.control))
		for event in events {
			guard let control = Self.control(for: event.button) else { continue }
			var history = edges[control, default: []]
			history.append(Edge(pressed: event.pressed, time: time))
			edges[control] = Array(history.suffix(64))
			if !event.pressed { repeatOwners.removeValue(forKey: control) }
		}
	}

	mutating func shouldSuppress(
		_ control: Control, pressed: Bool, at time: TimeInterval,
		keyboardType: Int64 = 0, isRepeat: Bool = false, sourcePID: Int64 = 0,
		synthetic: Bool = false
	) -> Bool {
		guard sourcePID == 0, !synthetic else { return false }
		if isRepeat {
			return pressed && held.contains(control) && repeatOwners[control] == keyboardType
		}
		if var history = edges[control], let index = history.firstIndex(where: {
			$0.pressed == pressed && abs(time - $0.time) <= Self.correlationWindow
		}) {
			history.remove(at: index)
			edges[control] = history.isEmpty ? nil : history
			if pressed { repeatOwners[control] = keyboardType }
			else { repeatOwners.removeValue(forKey: control) }
			return true
		}
		// A real keyboard/media key with this code now owns its own repetition.
		repeatOwners.removeValue(forKey: control)
		return false
	}
}
