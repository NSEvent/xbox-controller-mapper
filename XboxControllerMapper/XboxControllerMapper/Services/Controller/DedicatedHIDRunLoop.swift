import Foundation

/// Dedicated run-loop thread for raw HID report delivery. Reports must NOT be
/// scheduled on the main run loop: any main-thread hitch (UI animation,
/// layout) stalls delivery, and queued reports then flush in one burst
/// seconds late — a release report stuck in that queue leaves a button (and
/// any mapped mouse click) held down. Shared by the Steam and Wiimote
/// backends; one instance per backend, each owning its own thread.
final class DedicatedHIDRunLoop: @unchecked Sendable {
	private let threadName: String
	private let lock = NSLock()
	private var runLoop: CFRunLoop?

	init(threadName: String) {
		self.threadName = threadName
	}

	func perform(_ work: @escaping @Sendable () -> Void) {
		let runLoop = startIfNeeded()
		CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, work)
		CFRunLoopWakeUp(runLoop)
	}

	/// Returns false when the wait timed out — the work may still be running
	/// (or queued) on the HID run loop, so callers must not free resources it
	/// uses.
	@discardableResult
	func performAndWait(_ work: @escaping @Sendable () -> Void) -> Bool {
		let semaphore = DispatchSemaphore(value: 0)
		perform {
			work()
			semaphore.signal()
		}
		return semaphore.wait(timeout: .now() + 1.0) == .success
	}

	private func startIfNeeded() -> CFRunLoop {
		lock.lock()
		if let runLoop {
			lock.unlock()
			return runLoop
		}

		let ready = DispatchSemaphore(value: 0)
		let thread = Thread {
			let currentRunLoop = CFRunLoopGetCurrent()
			var sourceContext = CFRunLoopSourceContext()
			if let keepAliveSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &sourceContext) {
				CFRunLoopAddSource(currentRunLoop, keepAliveSource, CFRunLoopMode.defaultMode)
			}
			self.lock.lock()
			self.runLoop = currentRunLoop
			self.lock.unlock()
			ready.signal()
			CFRunLoopRun()
		}
		thread.name = threadName
		thread.qualityOfService = .userInteractive
		thread.start()
		lock.unlock()

		ready.wait()
		lock.lock()
		let currentRunLoop = runLoop!
		lock.unlock()
		return currentRunLoop
	}
}
