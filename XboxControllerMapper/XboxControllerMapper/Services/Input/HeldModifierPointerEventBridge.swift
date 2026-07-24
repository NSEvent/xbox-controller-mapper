import ApplicationServices
import CoreGraphics
import Foundation

/// Ensures pointer and tablet events carry modifiers held by ControllerKeys.
///
/// A synthesized modifier `flagsChanged` event updates the global modifier state,
/// but some device drivers create pointer events with their own explicit flags.
/// Apps that inspect each Wacom/mouse event can then miss a controller-held Shift.
/// This session event tap adds only ControllerKeys' held modifiers to those events.
final class HeldModifierPointerEventBridge: @unchecked Sendable {
	private enum StartState {
		case idle
		case starting
		case running
		case failed
		case stopped
	}

	private let heldModifiers: @Sendable () -> CGEventFlags
	private let lock = NSLock()
	private var state: StartState = .idle
	private var eventTap: CFMachPort?
	private var runLoop: CFRunLoop?

	init(heldModifiers: @escaping @Sendable () -> CGEventFlags) {
		self.heldModifiers = heldModifiers
	}

	func startIfNeeded() {
		lock.lock()
		guard state == .idle else {
			lock.unlock()
			return
		}
		state = .starting
		lock.unlock()

		let ready = DispatchSemaphore(value: 0)
		let thread = Thread { [self] in
			runEventTap(ready: ready)
		}
		thread.name = "ControllerKeys held-modifier pointer bridge"
		thread.qualityOfService = .userInteractive
		thread.start()

		_ = ready.wait(timeout: .now() + 0.25)
	}

	func stop() {
		let runLoopToStop: CFRunLoop?

		lock.lock()
		state = .stopped
		runLoopToStop = runLoop
		lock.unlock()

		if let runLoopToStop {
			CFRunLoopStop(runLoopToStop)
		}
	}

	private func runEventTap(ready: DispatchSemaphore) {
		let eventMask = HeldModifierPointerEventPolicy.eventTypes.reduce(CGEventMask(0)) {
			$0 | CGEventMask(1) << CGEventMask($1.rawValue)
		}
		let context = Unmanaged.passUnretained(self).toOpaque()

		guard let tap = CGEvent.tapCreate(
			tap: .cgSessionEventTap,
			place: .headInsertEventTap,
			options: .defaultTap,
			eventsOfInterest: eventMask,
			callback: heldModifierPointerEventTapCallback,
			userInfo: context
		) else {
			lock.lock()
			if state != .stopped {
				state = .failed
			}
			lock.unlock()
			ready.signal()
			NSLog("[InputSimulator] Could not create held-modifier pointer event tap")
			return
		}

		let currentRunLoop = CFRunLoopGetCurrent()
		let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

		lock.lock()
		guard state != .stopped else {
			lock.unlock()
			ready.signal()
			CGEvent.tapEnable(tap: tap, enable: false)
			return
		}
		eventTap = tap
		runLoop = currentRunLoop
		state = .running
		lock.unlock()

		CFRunLoopAddSource(currentRunLoop, source, .commonModes)
		CGEvent.tapEnable(tap: tap, enable: true)
		ready.signal()
		CFRunLoopRun()

		CGEvent.tapEnable(tap: tap, enable: false)
		CFRunLoopRemoveSource(currentRunLoop, source, .commonModes)

		lock.lock()
		eventTap = nil
		runLoop = nil
		if state != .stopped {
			state = .idle
		}
		lock.unlock()
	}

	fileprivate func process(type: CGEventType, event: CGEvent) {
		guard HeldModifierPointerEventPolicy.shouldAugment(type) else { return }
		let controllerModifiers = heldModifiers()
		guard !controllerModifiers.isEmpty else { return }
		event.flags = HeldModifierPointerEventPolicy.augmentedFlags(
			eventFlags: event.flags,
			heldModifiers: controllerModifiers
		)
	}

	fileprivate func reenableAfterDisable() {
		lock.lock()
		let tap = eventTap
		lock.unlock()

		if let tap {
			CGEvent.tapEnable(tap: tap, enable: true)
		}
	}
}

enum HeldModifierPointerEventPolicy {
	static let eventTypes: [CGEventType] = [
		.leftMouseDown,
		.leftMouseUp,
		.rightMouseDown,
		.rightMouseUp,
		.mouseMoved,
		.leftMouseDragged,
		.rightMouseDragged,
		.scrollWheel,
		.tabletPointer,
		.otherMouseDown,
		.otherMouseUp,
		.otherMouseDragged
	]

	static func shouldAugment(_ type: CGEventType) -> Bool {
		eventTypes.contains(type)
	}

	static func augmentedFlags(
		eventFlags: CGEventFlags,
		heldModifiers: CGEventFlags
	) -> CGEventFlags {
		eventFlags.union(heldModifiers)
	}
}

private func heldModifierPointerEventTapCallback(
	proxy: CGEventTapProxy,
	type: CGEventType,
	event: CGEvent,
	userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
	guard let userInfo else {
		return Unmanaged.passUnretained(event)
	}

	let bridge = Unmanaged<HeldModifierPointerEventBridge>
		.fromOpaque(userInfo)
		.takeUnretainedValue()

	if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
		bridge.reenableAfterDisable()
		return Unmanaged.passUnretained(event)
	}

	bridge.process(type: type, event: event)
	return Unmanaged.passUnretained(event)
}
