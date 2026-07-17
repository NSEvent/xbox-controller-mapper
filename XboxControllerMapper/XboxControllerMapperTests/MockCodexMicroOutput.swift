import Foundation
@testable import ControllerKeys

final class MockCodexMicroOutput: CodexMicroOutputProtocol, @unchecked Sendable {
	enum Event: Equatable {
		case tap(CodexMicroControl)
		case press(CodexMicroControl)
		case release(CodexMicroControl)
	}

	private let lock = NSLock()
	private var recordedEvents: [Event] = []

	var events: [Event] {
		lock.withLock { recordedEvents }
	}

	func tap(_ control: CodexMicroControl) {
		lock.withLock { recordedEvents.append(.tap(control)) }
	}

	func press(_ control: CodexMicroControl) {
		lock.withLock { recordedEvents.append(.press(control)) }
	}

	func release(_ control: CodexMicroControl) {
		lock.withLock { recordedEvents.append(.release(control)) }
	}
}
