import AppKit
import Carbon.HIToolbox
import XCTest
import TriggerKitCore
@testable import TriggerKitRuntime

final class InputEventMapperTests: XCTestCase {
	func testModifierKeyCodeMappingPreservesOrderAndSides() {
		let modifiers = ModifierSet(command: .left, option: .right, control: .any, shift: .right, function: true)

		XCTAssertEqual(InputEventMapper.modifierKeyCodes(for: modifiers), [
			CGKeyCode(kVK_Command),
			CGKeyCode(kVK_RightOption),
			CGKeyCode(kVK_Control),
			CGKeyCode(kVK_RightShift),
			CGKeyCode(kVK_Function)
		])
	}

	func testEventFlagsRepresentAllLogicalModifiers() {
		let flags = InputEventMapper.eventFlags(for: ModifierSet(command: .right, option: .left, control: .any, shift: .right, function: true))

		XCTAssertTrue(flags.contains(.maskCommand))
		XCTAssertTrue(flags.contains(.maskAlternate))
		XCTAssertTrue(flags.contains(.maskControl))
		XCTAssertTrue(flags.contains(.maskShift))
		XCTAssertTrue(flags.contains(.maskSecondaryFn))
	}

	func testKeyStrokeFlagsIncludeSpecialKeyFlags() {
		let flags = InputEventMapper.eventFlags(for: KeyStroke(key: .help, modifiers: ModifierSet(shift: .left)))

		XCTAssertTrue(flags.contains(.maskShift))
		XCTAssertTrue(flags.contains(.maskNumericPad))
		XCTAssertTrue(flags.contains(.maskSecondaryFn))
	}

	func testSpecialFlagsForNavigationFunctionAndKeypadKeys() throws {
		let leftArrow = try XCTUnwrap(TriggerKey.catalogKey(keyCode: UInt16(kVK_LeftArrow)))
		let f12 = try XCTUnwrap(TriggerKey.catalogKey(keyCode: UInt16(kVK_F12)))
		let keypadEnter = try XCTUnwrap(TriggerKey.allCatalogKeys.first { $0.id == "keypad-enter" })

		let leftArrowFlags = InputEventMapper.specialKeyFlags(for: leftArrow)
		XCTAssertTrue(leftArrowFlags.contains(.maskNumericPad))
		XCTAssertTrue(leftArrowFlags.contains(.maskSecondaryFn))

		let functionFlags = InputEventMapper.specialKeyFlags(for: f12)
		XCTAssertFalse(functionFlags.contains(.maskNumericPad))
		XCTAssertTrue(functionFlags.contains(.maskSecondaryFn))

		let keypadFlags = InputEventMapper.specialKeyFlags(for: keypadEnter)
		XCTAssertTrue(keypadFlags.contains(.maskNumericPad))
		XCTAssertFalse(keypadFlags.contains(.maskSecondaryFn))
	}

	func testMediaAndSystemKeysMapToNXTypes() {
		XCTAssertEqual(InputEventMapper.nxKeyType(for: .mediaPlayPause), .play)
		XCTAssertEqual(InputEventMapper.nxKeyType(for: .mediaNext), .next)
		XCTAssertEqual(InputEventMapper.nxKeyType(for: .mediaPrevious), .previous)
		XCTAssertEqual(InputEventMapper.nxKeyType(for: .mediaFastForward), .fast)
		XCTAssertEqual(InputEventMapper.nxKeyType(for: .mediaRewind), .rewind)
		XCTAssertEqual(InputEventMapper.nxKeyType(for: .volumeUp), .soundUp)
		XCTAssertEqual(InputEventMapper.nxKeyType(for: .volumeDown), .soundDown)
		XCTAssertEqual(InputEventMapper.nxKeyType(for: .volumeMute), .mute)
		XCTAssertEqual(InputEventMapper.nxKeyType(for: .brightnessUp), .brightnessUp)
		XCTAssertEqual(InputEventMapper.nxKeyType(for: .brightnessDown), .brightnessDown)
		XCTAssertNil(InputEventMapper.nxKeyType(for: .return))
	}

	func testMouseButtonMappingMatchesCoreGraphicsEvents() {
		XCTAssertEqual(InputEventMapper.cgButton(.left), .left)
		XCTAssertEqual(InputEventMapper.cgButton(.right), .right)
		XCTAssertEqual(InputEventMapper.cgButton(.middle), .center)
		XCTAssertEqual(InputEventMapper.cgButton(.back), CGMouseButton(rawValue: 3))
		XCTAssertEqual(InputEventMapper.cgButton(.forward), CGMouseButton(rawValue: 4))

		XCTAssertEqual(InputEventMapper.mouseEventType(.left, mouseDown: true), .leftMouseDown)
		XCTAssertEqual(InputEventMapper.mouseEventType(.left, mouseDown: false), .leftMouseUp)
		XCTAssertEqual(InputEventMapper.mouseEventType(.right, mouseDown: true), .rightMouseDown)
		XCTAssertEqual(InputEventMapper.mouseEventType(.right, mouseDown: false), .rightMouseUp)
		XCTAssertEqual(InputEventMapper.mouseEventType(.middle, mouseDown: true), .otherMouseDown)
		XCTAssertEqual(InputEventMapper.mouseEventType(.forward, mouseDown: false), .otherMouseUp)
	}
}
