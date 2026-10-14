import Carbon.HIToolbox
import CoreGraphics
import Foundation
import XCTest
@testable import ControllerKeys

final class HeldModifierPointerEventBridgePolicyTests: XCTestCase {
	func testKeyboardPointerAndTabletEventsAreSubscribed() {
		let expected: Set<CGEventType> = [
			.keyDown,
			.keyUp,
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

		XCTAssertEqual(Set(HeldModifierPointerEventPolicy.eventTypes), expected)
		for type in expected {
			XCTAssertTrue(HeldModifierPointerEventPolicy.shouldAugment(type))
		}
	}

	func testModifierTransitionsAndUnrelatedEventsAreNotAugmented() {
		for type in [CGEventType.flagsChanged, .null, .tapDisabledByTimeout] {
			XCTAssertFalse(HeldModifierPointerEventPolicy.shouldAugment(type))
		}
	}

	func testHeldShiftIsAddedToWacomLikePointerEvent() {
		let flags = HeldModifierPointerEventPolicy.augmentedFlags(
			eventFlags: [],
			heldModifiers: [.maskShift]
		)

		XCTAssertTrue(flags.contains(.maskShift))
	}

	func testExistingPhysicalModifiersArePreserved() {
		let flags = HeldModifierPointerEventPolicy.augmentedFlags(
			eventFlags: [.maskCommand, .maskNonCoalesced],
			heldModifiers: [.maskShift]
		)

		XCTAssertTrue(flags.contains(.maskCommand))
		XCTAssertTrue(flags.contains(.maskShift))
		XCTAssertTrue(flags.contains(.maskNonCoalesced))
	}

	// Exercise the production event handler without posting input or starting a tap.
	private func keyboardEvent(
		type: CGEventType,
		keyCode: Int = kVK_ANSI_W,
		flags: CGEventFlags = [],
		sourceProcessID: Int64 = 0
	) throws -> CGEvent {
		let event = try XCTUnwrap(CGEvent(
			keyboardEventSource: nil,
			virtualKey: CGKeyCode(keyCode),
			keyDown: type == .keyDown
		))
		event.type = type
		event.flags = flags
		event.setIntegerValueField(.eventSourceUnixProcessID, value: sourceProcessID)
		return event
	}

	func testControllerCommandReachesPhysicalWDownAndUpWithoutChangingKey() throws {
		let bridge = HeldModifierPointerEventBridge(
			heldModifiers: { [.maskCommand] }, isSecureInputEnabled: { false }
		)
		for type in [CGEventType.keyDown, .keyUp] {
			let event = try keyboardEvent(type: type, flags: [.maskShift, .maskNonCoalesced])
			bridge.process(type: type, event: event)
			XCTAssertEqual(event.flags, [.maskCommand, .maskShift, .maskNonCoalesced])
			XCTAssertEqual(event.type, type)
			XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), Int64(kVK_ANSI_W))
			XCTAssertEqual(event.getIntegerValueField(.eventSourceUnixProcessID), 0)
		}
	}

	func testKeyboardRepeatAndSeveralHeldModifiersArePreserved() throws {
		let bridge = HeldModifierPointerEventBridge(
			heldModifiers: { [.maskCommand, .maskAlternate, .maskControl] },
			isSecureInputEnabled: { false }
		)
		let event = try keyboardEvent(type: .keyDown, flags: .maskShift)
		event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
		bridge.process(type: .keyDown, event: event)
		XCTAssertEqual(event.flags, [.maskCommand, .maskAlternate, .maskControl, .maskShift])
		XCTAssertEqual(event.getIntegerValueField(.keyboardEventAutorepeat), 1)
	}

	func testOwnGeneratedKeyboardEventsRetainExplicitFlags() throws {
		let bridge = HeldModifierPointerEventBridge(
			heldModifiers: { [.maskCommand] }, isSecureInputEnabled: { false }
		)
		for type in [CGEventType.keyDown, .keyUp] {
			let event = try keyboardEvent(
				type: type, flags: .maskShift,
				sourceProcessID: Int64(ProcessInfo.processInfo.processIdentifier)
			)
			bridge.process(type: type, event: event)
			XCTAssertEqual(event.flags, .maskShift)
		}
	}

	func testModifierKeysAndReleasesAreNotRewritten() throws {
		let bridge = HeldModifierPointerEventBridge(
			heldModifiers: { [.maskCommand] }, isSecureInputEnabled: { false }
		)
		let keys = [
			kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
			kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
			kVK_CapsLock, kVK_Function
		]
		for key in keys {
			for type in [CGEventType.keyDown, .keyUp, .flagsChanged] {
				let event = try keyboardEvent(type: type, keyCode: key)
				bridge.process(type: type, event: event)
				XCTAssertEqual(event.flags, [], "Modifier \(key), type \(type)")
			}
		}
	}

	func testSecureInputLeavesKeyboardFlagsUntouched() throws {
		let bridge = HeldModifierPointerEventBridge(
			heldModifiers: { [.maskCommand] }, isSecureInputEnabled: { true }
		)
		for type in [CGEventType.keyDown, .keyUp] {
			let event = try keyboardEvent(type: type, flags: .maskShift)
			bridge.process(type: type, event: event)
			XCTAssertEqual(event.flags, .maskShift)
		}
	}

	func testReleasedControllerModifierDoesNotStickOnKeyboardEvents() throws {
		let state = BridgeTestModifierState()
		let bridge = HeldModifierPointerEventBridge(
			heldModifiers: { state.flags }, isSecureInputEnabled: { false }
		)
		state.flags = [.maskCommand, .maskAlternate]
		let down = try keyboardEvent(type: .keyDown)
		bridge.process(type: .keyDown, event: down)
		XCTAssertEqual(down.flags, [.maskCommand, .maskAlternate])
		state.flags = [.maskAlternate]
		let up = try keyboardEvent(type: .keyUp)
		bridge.process(type: .keyUp, event: up)
		XCTAssertEqual(up.flags, .maskAlternate)
		state.flags = []
		let next = try keyboardEvent(type: .keyDown, flags: .maskShift)
		bridge.process(type: .keyDown, event: next)
		XCTAssertEqual(next.flags, .maskShift)
	}
}

nonisolated private final class BridgeTestModifierState: @unchecked Sendable {
	private let lock = NSLock()
	private var storedFlags: CGEventFlags = []
	var flags: CGEventFlags {
		get { lock.withLock { storedFlags } }
		set { lock.withLock { storedFlags = newValue } }
	}
}
