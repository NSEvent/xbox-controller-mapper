import XCTest
import CoreGraphics
import Carbon.HIToolbox
import AppKit
@testable import ControllerKeys

final class ModifierFlagsSideTests: XCTestCase {

    func testVirtualKey_DefaultsToLeftWhenNoSideSet() {
        let flags = ModifierFlags(command: true, option: true, shift: true, control: true)
        XCTAssertEqual(flags.virtualKey(forMask: .maskCommand), CGKeyCode(kVK_Command))
        XCTAssertEqual(flags.virtualKey(forMask: .maskAlternate), CGKeyCode(kVK_Option))
        XCTAssertEqual(flags.virtualKey(forMask: .maskShift), CGKeyCode(kVK_Shift))
        XCTAssertEqual(flags.virtualKey(forMask: .maskControl), CGKeyCode(kVK_Control))
    }

    func testVirtualKey_HonorsRightSide() {
        let flags = ModifierFlags(
            command: true, option: true, shift: true, control: true,
            commandSide: .right, optionSide: .right, shiftSide: .right, controlSide: .right
        )
        XCTAssertEqual(flags.virtualKey(forMask: .maskCommand), CGKeyCode(kVK_RightCommand))
        XCTAssertEqual(flags.virtualKey(forMask: .maskAlternate), CGKeyCode(kVK_RightOption))
        XCTAssertEqual(flags.virtualKey(forMask: .maskShift), CGKeyCode(kVK_RightShift))
        XCTAssertEqual(flags.virtualKey(forMask: .maskControl), CGKeyCode(kVK_RightControl))
    }

    func testVirtualKey_HonorsExplicitLeftSide() {
        let flags = ModifierFlags(command: true, commandSide: .left)
        XCTAssertEqual(flags.virtualKey(forMask: .maskCommand), CGKeyCode(kVK_Command))
    }

    func testCgEventFlags_IgnoresSide() {
        // OS-level mask is the same regardless of side
        let leftFlags = ModifierFlags(command: true, commandSide: .left)
        let rightFlags = ModifierFlags(command: true, commandSide: .right)
        let unspecifiedFlags = ModifierFlags(command: true)
        XCTAssertEqual(leftFlags.cgEventFlags, .maskCommand)
        XCTAssertEqual(rightFlags.cgEventFlags, .maskCommand)
        XCTAssertEqual(unspecifiedFlags.cgEventFlags, .maskCommand)
    }

    func testLabel_FormatsSidePrefix() {
        XCTAssertEqual(ModifierFlags.label(for: nil), "")
        XCTAssertEqual(ModifierFlags.label(for: .left), "L")
        XCTAssertEqual(ModifierFlags.label(for: .right), "R")
    }

    // MARK: - Codable backward compatibility

    func testDecode_LegacyJsonWithoutSideFields() throws {
        // JSON shape from before this feature — no *Side keys
        let legacy = """
        {"command": true, "option": false, "shift": true, "control": false}
        """.data(using: .utf8)!

        let flags = try JSONDecoder().decode(ModifierFlags.self, from: legacy)
        XCTAssertTrue(flags.command)
        XCTAssertFalse(flags.option)
        XCTAssertTrue(flags.shift)
        XCTAssertFalse(flags.control)
        XCTAssertNil(flags.commandSide)
        XCTAssertNil(flags.optionSide)
        XCTAssertNil(flags.shiftSide)
        XCTAssertNil(flags.controlSide)
    }

    func testDecode_NewJsonWithSideFields() throws {
        let json = """
        {
            "command": true, "option": false, "shift": true, "control": false,
            "commandSide": "right", "shiftSide": "left"
        }
        """.data(using: .utf8)!

        let flags = try JSONDecoder().decode(ModifierFlags.self, from: json)
        XCTAssertEqual(flags.commandSide, .right)
        XCTAssertEqual(flags.shiftSide, .left)
        XCTAssertNil(flags.optionSide)
        XCTAssertNil(flags.controlSide)
    }

    func testRoundTrip_SidesPreserved() throws {
        let original = ModifierFlags(
            command: true, option: true, shift: false, control: false,
            commandSide: .right, optionSide: .left
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModifierFlags.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testHoldModifiers_UsesSideAwareKeyCodesInPressAndReleaseOrder() {
		let simulator = RecordingInputSimulator()
		let flags = ModifierFlags(
			command: true,
			option: true,
			commandSide: .right,
			optionSide: .left
		)

		simulator.holdModifiers(flags)
		simulator.releaseModifiers(flags)

		XCTAssertEqual(simulator.events, [
			.holdModifierKey(CGKeyCode(kVK_RightCommand)),
			.holdModifierKey(CGKeyCode(kVK_Option)),
			.releaseModifierKey(CGKeyCode(kVK_Option)),
			.releaseModifierKey(CGKeyCode(kVK_RightCommand))
		])
    }

    func testModifierTapActionCommand_PreservesRightSide() {
		let simulator = RecordingInputSimulator()
		let queue = DispatchQueue(label: "test.modifierTap.side")
		let action = KeyMapping(modifiers: ModifierFlags(command: true, commandSide: .right))
		let command = ModifierTapActionCommand(
			modifiers: action.modifiers,
			inputSimulator: simulator,
			inputQueue: queue,
			action: action
		)

		_ = command.execute()

		let releaseFinished = expectation(description: "modifier release")
		queue.asyncAfter(deadline: .now() + Config.modifierReleaseCheckDelay + 0.02) {
			releaseFinished.fulfill()
		}
		wait(for: [releaseFinished], timeout: 1)

		XCTAssertEqual(simulator.events, [
			.holdModifierKey(CGKeyCode(kVK_RightCommand)),
			.releaseModifierKey(CGKeyCode(kVK_RightCommand))
		])
    }

	@MainActor
	func testKeyCaptureModifierFlags_PreservesSidesForModifierKeyShortcut() {
		let modifiers = KeyCaptureNSView.modifierFlags(
			from: [.command, .shift],
			capturedKeyCodes: [UInt16(kVK_RightCommand), UInt16(kVK_Shift)]
		)

		XCTAssertTrue(modifiers.command)
		XCTAssertTrue(modifiers.shift)
		XCTAssertEqual(modifiers.commandSide, .right)
		XCTAssertEqual(modifiers.shiftSide, .left)
    }

	@MainActor
	func testKeyCaptureModifierFlags_UsesAnyWhenBothSidesWereCaptured() {
		let modifiers = KeyCaptureNSView.modifierFlags(
			from: [.command],
			capturedKeyCodes: [UInt16(kVK_Command), UInt16(kVK_RightCommand)]
		)

		XCTAssertTrue(modifiers.command)
		XCTAssertNil(modifiers.commandSide)
    }
}

private final class RecordingInputSimulator: InputSimulatorProtocol, @unchecked Sendable {
    enum Event: Equatable {
		case pressKey(CGKeyCode, CGEventFlags)
		case pressKeyWithModifierFlags(CGKeyCode, ModifierFlags)
		case keyDown(CGKeyCode, CGEventFlags)
		case keyUp(CGKeyCode)
		case holdModifier(CGEventFlags)
		case releaseModifier(CGEventFlags)
		case holdModifierKey(CGKeyCode)
		case releaseModifierKey(CGKeyCode)
    }

    private let lock = NSLock()
    private var recordedEvents: [Event] = []

    var events: [Event] {
		lock.lock()
		defer { lock.unlock() }
		return recordedEvents
    }

    private func record(_ event: Event) {
		lock.lock()
		defer { lock.unlock() }
		recordedEvents.append(event)
    }

    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags) {
		record(.pressKey(keyCode, modifiers))
    }

    func pressKey(_ keyCode: CGKeyCode, modifiers: ModifierFlags) {
		record(.pressKeyWithModifierFlags(keyCode, modifiers))
    }

    func keyDown(_ keyCode: CGKeyCode, modifiers: CGEventFlags) {
		record(.keyDown(keyCode, modifiers))
    }

    func keyUp(_ keyCode: CGKeyCode) {
		record(.keyUp(keyCode))
    }

    func holdModifier(_ modifier: CGEventFlags) {
		record(.holdModifier(modifier))
    }

    func releaseModifier(_ modifier: CGEventFlags) {
		record(.releaseModifier(modifier))
    }

    func holdModifierKey(_ keyCode: CGKeyCode) {
		record(.holdModifierKey(keyCode))
    }

    func releaseModifierKey(_ keyCode: CGKeyCode) {
		record(.releaseModifierKey(keyCode))
    }

    func releaseAllModifiers() {}
    func isHoldingModifiers(_ modifier: CGEventFlags) -> Bool { false }
    func getHeldModifiers() -> CGEventFlags { [] }
    func moveMouse(dx: CGFloat, dy: CGFloat) {}
    func moveMouseNative(dx: Int, dy: Int) {}
    func warpMouseTo(point: CGPoint) {}
    var isLeftMouseButtonHeld: Bool { false }
    func scroll(
		dx: CGFloat,
		dy: CGFloat,
		phase: CGScrollPhase?,
		momentumPhase: CGMomentumScrollPhase?,
		isContinuous: Bool,
		flags: CGEventFlags
    ) {}
    func executeMapping(_ mapping: KeyMapping) {}
    func startHoldMapping(_ mapping: KeyMapping) {}
    func stopHoldMapping(_ mapping: KeyMapping) {}
    func typeText(_ text: String, speed: Int, pressEnter: Bool) {}
}
