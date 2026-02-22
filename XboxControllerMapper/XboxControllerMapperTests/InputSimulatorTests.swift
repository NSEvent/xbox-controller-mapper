import XCTest
import CoreGraphics
@testable import ControllerKeys

// MARK: - InputSimulator Unit Tests
//
// InputSimulator posts CGEvents which requires Accessibility permissions not available in CI.
// These tests focus on:
//   1. Pure logic that never posts events (KeyCodeMapping helpers, ModifierFlags conversion)
//   2. Static helpers that don't require event posting (consumeMovementDelta, resetMovementDelta, getZoomLevel)
//   3. Initial/observable state that doesn't depend on event posting
//   4. Protocol conformance (compilation-level tests)
//
// Tests that mutate heldModifiers via holdModifier/releaseModifier are NOT included here
// because those methods gate on AXIsProcessTrusted() and are no-ops in CI.
// Modifier reference-counting logic is tested indirectly via MockInputSimulator
// in MappingEngineCharacterizationTests and MouseClickDragTests.

final class InputSimulatorTests: XCTestCase {

    var simulator: InputSimulator!

    override func setUp() {
        super.setUp()
        simulator = InputSimulator()
    }

    override func tearDown() {
        simulator = nil
        super.tearDown()
    }

    // MARK: - Protocol Conformance

    func testConformsToInputSimulatorProtocol() {
        // Compilation is the assertion — InputSimulator must satisfy InputSimulatorProtocol
        let _: InputSimulatorProtocol = simulator
    }

    func testConformsToSendable() {
        // Compilation is the assertion — InputSimulator is marked @unchecked Sendable
        let _: Sendable = simulator
    }

    // MARK: - Mouse Button Initial State

    func testIsLeftMouseButtonHeld_initiallyFalse() {
        XCTAssertFalse(simulator.isLeftMouseButtonHeld,
            "Left mouse button should not be held on a freshly created simulator")
    }

    func testGetHeldModifiers_initiallyEmpty() {
        // Without Accessibility permissions the modifier state is never mutated,
        // so the initial value is always the empty set.
        XCTAssertEqual(simulator.getHeldModifiers(), [],
            "No modifiers should be held on a freshly created simulator")
    }

    func testIsHoldingModifiers_emptyFlags_returnsFalse() {
        // isHoldingModifiers short-circuits when the query is empty — no accessibility needed.
        XCTAssertFalse(simulator.isHoldingModifiers([]),
            "Empty flag query must always return false")
    }

    // MARK: - Static Movement Delta

    func testResetMovementDelta_clearsAccumulated() {
        InputSimulator.resetMovementDelta()
        let delta = InputSimulator.consumeMovementDelta()
        XCTAssertEqual(delta.x, 0, "X delta should be 0 after reset")
        XCTAssertEqual(delta.y, 0, "Y delta should be 0 after reset")
    }

    func testConsumeMovementDelta_isIdempotentAfterFirstConsume() {
        InputSimulator.resetMovementDelta()
        _ = InputSimulator.consumeMovementDelta()
        let second = InputSimulator.consumeMovementDelta()
        XCTAssertEqual(second.x, 0, "Second consume should return 0 X")
        XCTAssertEqual(second.y, 0, "Second consume should return 0 Y")
    }

    func testConsumeMovementDelta_resetsAfterConsume() {
        InputSimulator.resetMovementDelta()
        let first = InputSimulator.consumeMovementDelta()
        let second = InputSimulator.consumeMovementDelta()
        XCTAssertEqual(first.x, second.x, "Both consumes post-reset should return zero X")
        XCTAssertEqual(first.y, second.y, "Both consumes post-reset should return zero Y")
    }

    // MARK: - Static Zoom Level

    func testGetZoomLevel_returnsAtLeastOne() {
        // Zoom level is always >= 1.0 by definition; when not zoomed it is 1.0.
        let level = InputSimulator.getZoomLevel()
        XCTAssertGreaterThanOrEqual(level, 1.0,
            "Zoom level should never be less than 1.0")
    }
}

// MARK: - KeyCodeMapping Special Key Flag Tests
// (isMouseButton, isMediaKey, isSpecialMarker, displayName, allKeyOptions, and keyInfo
//  are covered by KeyCodeMappingDisplayTests.swift — only uncovered helpers are tested here.)

final class KeyCodeMappingSpecialFlagTests: XCTestCase {

    // MARK: - specialKeyFlags

    func testSpecialKeyFlags_arrowKey_hasNumericPadAndSecondaryFn() {
        let flags = KeyCodeMapping.specialKeyFlags(for: KeyCodeMapping.leftArrow)
        XCTAssertTrue(flags.contains(.maskNumericPad),
            "Arrow keys require NumericPad flag")
        XCTAssertTrue(flags.contains(.maskSecondaryFn),
            "Arrow keys require SecondaryFn flag")
    }

    func testSpecialKeyFlags_functionKey_hasSecondaryFn() {
        let flags = KeyCodeMapping.specialKeyFlags(for: KeyCodeMapping.f1)
        XCTAssertTrue(flags.contains(.maskSecondaryFn),
            "Function keys require SecondaryFn flag")
    }

    func testSpecialKeyFlags_regularKey_isEmpty() {
        let flags = KeyCodeMapping.specialKeyFlags(for: KeyCodeMapping.keyA)
        XCTAssertEqual(flags, [],
            "Letter keys should not have any special flags")
    }

    func testSpecialKeyFlags_space_isEmpty() {
        let flags = KeyCodeMapping.specialKeyFlags(for: KeyCodeMapping.space)
        XCTAssertEqual(flags, [],
            "Space key should not have any special flags")
    }

    // MARK: - requiresFnFlag / requiresNumPadFlag

    func testRequiresFnFlag_f12_returnsTrue() {
        XCTAssertTrue(KeyCodeMapping.requiresFnFlag(KeyCodeMapping.f12))
    }

    func testRequiresFnFlag_regularKey_returnsFalse() {
        XCTAssertFalse(KeyCodeMapping.requiresFnFlag(KeyCodeMapping.keyZ))
    }

    func testRequiresNumPadFlag_upArrow_returnsTrue() {
        XCTAssertTrue(KeyCodeMapping.requiresNumPadFlag(KeyCodeMapping.upArrow))
    }

    func testRequiresNumPadFlag_letterKey_returnsFalse() {
        XCTAssertFalse(KeyCodeMapping.requiresNumPadFlag(KeyCodeMapping.keyB))
    }
}

// MARK: - ModifierFlags Conversion Tests

final class ModifierFlagsTests: XCTestCase {

    func testCGEventFlags_allFalse_isEmpty() {
        let flags = ModifierFlags(command: false, option: false, shift: false, control: false)
        XCTAssertEqual(flags.cgEventFlags, [],
            "Empty ModifierFlags should produce empty CGEventFlags")
    }

    func testCGEventFlags_commandOnly() {
        let flags = ModifierFlags(command: true)
        XCTAssertTrue(flags.cgEventFlags.contains(.maskCommand))
        XCTAssertFalse(flags.cgEventFlags.contains(.maskAlternate))
        XCTAssertFalse(flags.cgEventFlags.contains(.maskShift))
        XCTAssertFalse(flags.cgEventFlags.contains(.maskControl))
    }

    func testCGEventFlags_allModifiers() {
        let flags = ModifierFlags(command: true, option: true, shift: true, control: true)
        let cgFlags = flags.cgEventFlags
        XCTAssertTrue(cgFlags.contains(.maskCommand))
        XCTAssertTrue(cgFlags.contains(.maskAlternate))
        XCTAssertTrue(cgFlags.contains(.maskShift))
        XCTAssertTrue(cgFlags.contains(.maskControl))
    }

    func testHasAny_whenAllFalse_returnsFalse() {
        let flags = ModifierFlags()
        XCTAssertFalse(flags.hasAny)
    }

    func testHasAny_whenOneSet_returnsTrue() {
        let flags = ModifierFlags(shift: true)
        XCTAssertTrue(flags.hasAny)
    }

    func testStaticCommand_setsCommandOnly() {
        let flags = ModifierFlags.command
        XCTAssertTrue(flags.command)
        XCTAssertFalse(flags.option)
        XCTAssertFalse(flags.shift)
        XCTAssertFalse(flags.control)
    }
}

// MARK: - KeyMapping Construction Tests

final class KeyMappingConstructionTests: XCTestCase {

    func testKey_setsKeyCodeOnly() {
        let mapping = KeyMapping.key(49) // spacebar
        XCTAssertEqual(mapping.keyCode, 49)
        XCTAssertFalse(mapping.modifiers.hasAny)
        XCTAssertFalse(mapping.isHoldModifier)
    }

    func testHoldModifier_setsIsHoldModifierTrue() {
        let mapping = KeyMapping.holdModifier(.command)
        XCTAssertNil(mapping.keyCode)
        XCTAssertTrue(mapping.modifiers.command)
        XCTAssertTrue(mapping.isHoldModifier)
    }

    func testCombo_setsKeyCodeAndModifiers() {
        let mapping = KeyMapping.combo(KeyCodeMapping.keyC, modifiers: .command)
        XCTAssertEqual(mapping.keyCode, KeyCodeMapping.keyC)
        XCTAssertTrue(mapping.modifiers.command)
    }

    func testIsEmpty_noKeyCodeNoModifiers_returnsTrue() {
        let mapping = KeyMapping()
        XCTAssertTrue(mapping.isEmpty)
    }

    func testIsEmpty_withKeyCode_returnsFalse() {
        let mapping = KeyMapping(keyCode: 49)
        XCTAssertFalse(mapping.isEmpty)
    }

    func testIsEmpty_withModifierOnly_returnsFalse() {
        let mapping = KeyMapping(modifiers: .command)
        XCTAssertFalse(mapping.isEmpty)
    }

    func testDisplayString_modifierOnlyMapping() {
        let mapping = KeyMapping(modifiers: ModifierFlags(command: true))
        XCTAssertTrue(mapping.displayString.contains("⌘"),
            "Command-only mapping display string should contain ⌘")
    }

    func testDisplayString_emptyMapping_returnsNone() {
        let mapping = KeyMapping()
        XCTAssertEqual(mapping.displayString, "None")
    }
}
