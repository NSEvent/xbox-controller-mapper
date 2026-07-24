import Foundation
@testable import ControllerKeys

final class MockMIDIService: MIDIControlChangeSending, @unchecked Sendable {
	enum Event: Equatable {
		case press(MIDIControlChange)
		case release(MIDIControlChange)
		case pulse(MIDIControlChange)
	}

	private let lock = NSLock()
	private var storedEvents: [Event] = []

	var events: [Event] {
		lock.withLock { storedEvents }
	}

	func sendPress(_ message: MIDIControlChange) {
		lock.withLock { storedEvents.append(.press(message)) }
	}

	func sendRelease(_ message: MIDIControlChange) {
		lock.withLock { storedEvents.append(.release(message)) }
	}

	func pulse(_ message: MIDIControlChange) {
		lock.withLock { storedEvents.append(.pulse(message)) }
	}

	func clear() {
		lock.withLock { storedEvents.removeAll() }
	}
}
