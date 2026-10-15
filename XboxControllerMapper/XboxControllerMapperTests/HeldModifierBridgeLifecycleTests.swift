import CoreGraphics
import Foundation
import XCTest
@testable import ControllerKeys

final class HeldModifierBridgeLifecycleTests: XCTestCase {
	private func bridge(_ factory: BridgeTestTapFactory) -> HeldModifierPointerEventBridge {
		HeldModifierPointerEventBridge(
			heldModifiers: { [.maskCommand] },
			isSecureInputEnabled: { false },
			makeTap: { factory.make(mask: $0, context: $1) }
		)
	}

	func testFailedTapCreationRetriesOnNextControllerHold() {
		let factory = BridgeTestTapFactory(failures: 1)
		let bridge = bridge(factory)
		defer { bridge.stop(); XCTAssertTrue(factory.tap.waitForInvalidation()) }
		bridge.startIfNeeded()
		XCTAssertEqual(factory.attempts, 1)
		bridge.startIfNeeded()
		XCTAssertTrue(factory.tap.waitForEnable())
		XCTAssertEqual(factory.attempts, 2)
		XCTAssertEqual(factory.tap.enableCount, 1)
		let keyboardMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
			| (CGEventMask(1) << CGEventType.keyUp.rawValue)
		XCTAssertEqual(factory.mask & keyboardMask, keyboardMask)
	}

	func testConcurrentStartsCreateOnlyOneTap() {
		let factory = BridgeTestTapFactory()
		let bridge = bridge(factory)
		defer { bridge.stop(); XCTAssertTrue(factory.tap.waitForInvalidation()) }
		let group = DispatchGroup()
		for _ in 0..<20 {
			group.enter()
			DispatchQueue.global().async { bridge.startIfNeeded(); group.leave() }
		}
		XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
		XCTAssertTrue(factory.tap.waitForEnable())
		XCTAssertEqual(factory.attempts, 1)
		XCTAssertEqual(factory.tap.enableCount, 1)
	}

	func testStopBeforeStartPreventsTapCreationAndEventMutation() throws {
		let factory = BridgeTestTapFactory()
		let bridge = bridge(factory)
		bridge.stop()
		bridge.startIfNeeded()
		bridge.reenableAfterDisable()
		XCTAssertEqual(factory.attempts, 0)
		XCTAssertEqual(factory.tap.enableCount, 0)
		let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: true))
		event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
		event.flags = .maskShift
		bridge.process(type: .keyDown, event: event)
		XCTAssertEqual(event.flags, .maskShift)
	}

	func testStopDuringTapCreationInvalidatesWithoutEnablingIt() {
		let gate = DispatchSemaphore(value: 0)
		let factory = BridgeTestTapFactory(creationGate: gate)
		let bridge = bridge(factory)
		defer {
			gate.signal()
			bridge.stop()
			XCTAssertTrue(factory.tap.waitForInvalidation())
		}
		DispatchQueue.global().async { bridge.startIfNeeded() }
		XCTAssertEqual(factory.creationStarted.wait(timeout: .now() + 2), .success)
		bridge.stop()
		gate.signal()
		XCTAssertTrue(factory.tap.waitForInvalidation())
		XCTAssertEqual(factory.tap.enableCount, 0)
	}

	func testStopBetweenEnableAndRunLoopEntryIsNotLost() {
		let factory = BridgeTestTapFactory()
		let bridge = bridge(factory)
		defer { bridge.stop(); XCTAssertTrue(factory.tap.waitForInvalidation()) }
		factory.tap.onFirstEnable = { [weak bridge] in bridge?.stop() }
		bridge.startIfNeeded()
		XCTAssertTrue(factory.tap.waitForInvalidation(), "Startup must not strand a stopped worker")
		XCTAssertEqual(factory.tap.enableCount, 1)
	}

	func testStopBetweenPublicationAndActivationDoesNotEnableTheTap() {
		let factory = BridgeTestTapFactory()
		let bridge = bridge(factory)
		defer { bridge.stop(); XCTAssertTrue(factory.tap.waitForInvalidation()) }
		// CFRunLoopAddSource schedules the source after the bridge publishes the
		// tap/run loop, but before the worker attempts its initial enable.
		factory.tap.onSchedule = { [weak bridge] in bridge?.stop() }
		bridge.startIfNeeded()
		XCTAssertTrue(factory.tap.waitForInvalidation())
		XCTAssertEqual(factory.tap.enableCount, 0)
	}

	func testDisabledTapRecoversWhileRunningButNotAfterStop() {
		let factory = BridgeTestTapFactory()
		let bridge = bridge(factory)
		defer { bridge.stop(); XCTAssertTrue(factory.tap.waitForInvalidation()) }
		bridge.startIfNeeded()
		XCTAssertTrue(factory.tap.waitForEnable())
		bridge.reenableAfterDisable()
		XCTAssertEqual(factory.tap.enableCount, 2)
		bridge.stop()
		bridge.reenableAfterDisable()
		XCTAssertTrue(factory.tap.waitForInvalidation())
		XCTAssertEqual(factory.tap.enableCount, 2)
		bridge.startIfNeeded()
		XCTAssertEqual(factory.attempts, 1, "Stop is terminal")
	}
}

// A private source keeps a real CFRunLoop alive, without creating a system tap.
nonisolated private final class BridgeTestTap: HeldModifierEventTap, @unchecked Sendable {
	let runLoopSource: CFRunLoopSource
	private let lock = NSLock()
	private let invalidated = DispatchSemaphore(value: 0)
	private let enabled = DispatchSemaphore(value: 0)
	private var enableCalls = 0
	private var invalidationCalls = 0
	private let scheduleHook = BridgeTestScheduleHook()
	var onFirstEnable: (@Sendable () -> Void)?
	var onSchedule: (@Sendable () -> Void)? {
		get { scheduleHook.callback }
		set { scheduleHook.callback = newValue }
	}
	var enableCount: Int { lock.withLock { enableCalls } }

	init() {
		var context = CFRunLoopSourceContext()
		context.perform = { _ in }
		context.info = Unmanaged.passUnretained(scheduleHook).toOpaque()
		context.schedule = { info, _, _ in
			guard let info else { return }
			Unmanaged<BridgeTestScheduleHook>.fromOpaque(info).takeUnretainedValue().callback?()
		}
		runLoopSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)!
	}

	func setEnabled(_ enabled: Bool) {
		let first = lock.withLock {
			if enabled { enableCalls += 1 }
			return enabled && enableCalls == 1
		}
		if enabled { self.enabled.signal() }
		if first { onFirstEnable?() }
	}

	func invalidate() {
		CFRunLoopSourceInvalidate(runLoopSource)
		lock.withLock { invalidationCalls += 1 }
		invalidated.signal()
	}

	func waitForInvalidation() -> Bool {
		if lock.withLock({ invalidationCalls > 0 }) { return true }
		return invalidated.wait(timeout: .now() + 2) == .success
	}

	func waitForEnable() -> Bool {
		if enableCount > 0 { return true }
		return enabled.wait(timeout: .now() + 2) == .success
	}
}

nonisolated private final class BridgeTestScheduleHook: @unchecked Sendable {
	var callback: (@Sendable () -> Void)?
}

nonisolated private final class BridgeTestTapFactory: @unchecked Sendable {
	let tap = BridgeTestTap()
	let creationStarted = DispatchSemaphore(value: 0)
	private let lock = NSLock()
	private let failures: Int
	private let creationGate: DispatchSemaphore?
	private var count = 0
	private var recordedMask: CGEventMask = 0
	var attempts: Int { lock.withLock { count } }
	var mask: CGEventMask { lock.withLock { recordedMask } }

	init(failures: Int = 0, creationGate: DispatchSemaphore? = nil) {
		self.failures = failures
		self.creationGate = creationGate
	}

	func make(mask: CGEventMask, context: UnsafeMutableRawPointer) -> (any HeldModifierEventTap)? {
		let shouldFail = lock.withLock {
			count += 1
			recordedMask = mask
			return count <= failures
		}
		if shouldFail { return nil }
		creationStarted.signal()
		if let creationGate, creationGate.wait(timeout: .now() + 3) != .success { return nil }
		return tap
	}
}
