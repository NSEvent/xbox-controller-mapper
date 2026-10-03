import Foundation

/// Old callbacks remain cancelled even after mapping resumes.
nonisolated final class ScriptOutputGate: @unchecked Sendable {
	private let lock = NSLock()
	private var enabled = true
	private var generation = 0
	func setEnabled(_ value: Bool) {
		lock.withLock {
			if !value { generation += 1 }
			enabled = value
		}
	}
	var currentGeneration: Int { lock.withLock { generation } }
	func permits(_ generation: Int) -> Bool { lock.withLock { enabled && self.generation == generation } }
}
