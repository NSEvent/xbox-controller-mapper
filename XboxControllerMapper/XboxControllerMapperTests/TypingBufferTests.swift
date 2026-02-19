import XCTest
import Carbon.HIToolbox
@testable import ControllerKeys

@MainActor
final class TypingBufferTests: XCTestCase {
    private var manager: OnScreenKeyboardManager!
    private var mockSimulator: MockInputSimulator!

    override func setUp() {
        super.setUp()
        manager = OnScreenKeyboardManager.shared
        mockSimulator = MockInputSimulator()
        manager.setInputSimulator(mockSimulator)
        resetManager()
    }

    override func tearDown() {
        resetManager()
        manager = nil
        mockSimulator = nil
        super.tearDown()
    }

    // MARK: - Basic Typing

    func testTypingLetterAppendsToBuffer() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_A))
        XCTAssertEqual(manager.typingBuffer, "a")
    }

    func testTypingMultipleLettersAppendsAll() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_H))
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_I))
        XCTAssertEqual(manager.typingBuffer, "hi")
    }

    func testBackspaceRemovesLastCharacter() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_A))
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_B))
        simulateKeyPress(keyCode: KeyCodeMapping.delete)
        XCTAssertEqual(manager.typingBuffer, "a")
    }

    func testBackspaceOnEmptyBufferDoesNothing() {
        manager.show()
        simulateKeyPress(keyCode: KeyCodeMapping.delete)
        XCTAssertEqual(manager.typingBuffer, "")
    }

    func testNonTypableKeysIgnored() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_A))
        simulateKeyPress(keyCode: KeyCodeMapping.leftArrow)
        simulateKeyPress(keyCode: KeyCodeMapping.f1)
        simulateKeyPress(keyCode: KeyCodeMapping.escape)
        simulateKeyPress(keyCode: KeyCodeMapping.`return`)
        XCTAssertEqual(manager.typingBuffer, "a")
    }

    func testSpaceAppendsToBuffer() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_H))
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_I))
        simulateKeyPress(keyCode: KeyCodeMapping.space)
        XCTAssertEqual(manager.typingBuffer, "hi ")
    }

    // MARK: - Shift via On-Screen Keyboard

    func testShiftModifierProducesUppercase() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_A), modifiers: ModifierFlags(shift: true))
        XCTAssertEqual(manager.typingBuffer, "A")
    }

    func testShiftModifierProducesShiftedSymbols() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_1), modifiers: ModifierFlags(shift: true))
        XCTAssertEqual(manager.typingBuffer, "!")
    }

    // MARK: - Controller-Held Shift (Fix #2)

    func testControllerHeldShiftProducesUppercase() {
        manager.show()
        // Simulate controller holding shift via InputSimulator
        mockSimulator.holdModifier(.maskShift)
        // Press 'a' on the on-screen keyboard with no on-screen shift active
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_A))
        XCTAssertEqual(manager.typingBuffer, "A")
        mockSimulator.releaseModifier(.maskShift)
    }

    func testControllerHeldShiftProducesShiftedNumber() {
        manager.show()
        mockSimulator.holdModifier(.maskShift)
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_2))
        XCTAssertEqual(manager.typingBuffer, "@")
        mockSimulator.releaseModifier(.maskShift)
    }

    func testControllerHeldShiftProducesShiftedSymbol() {
        manager.show()
        mockSimulator.holdModifier(.maskShift)
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_Semicolon))
        XCTAssertEqual(manager.typingBuffer, ":")
        mockSimulator.releaseModifier(.maskShift)
    }

    func testNoShiftProducesLowercase() {
        manager.show()
        // No held modifiers, no on-screen shift
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_A))
        XCTAssertEqual(manager.typingBuffer, "a")
    }

    // MARK: - Controller-Mapped Typable Keys (Fix #3)

    func testControllerMappedSpaceUpdatesBuffer() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_H))
        // Simulate a controller button mapped to space via notifyControllerKeyPress
        manager.notifyControllerKeyPress(keyCode: KeyCodeMapping.space, modifiers: [])
        // notifyControllerKeyPress dispatches async, so drain the run loop
        drainMainQueue()
        XCTAssertEqual(manager.typingBuffer, "h ")
    }

    func testControllerMappedLetterUpdatesBuffer() {
        manager.show()
        manager.notifyControllerKeyPress(keyCode: CGKeyCode(kVK_ANSI_X), modifiers: [])
        drainMainQueue()
        XCTAssertEqual(manager.typingBuffer, "x")
    }

    func testControllerMappedKeyWithShiftModifierUpdatesBuffer() {
        manager.show()
        manager.notifyControllerKeyPress(keyCode: CGKeyCode(kVK_ANSI_A), modifiers: .maskShift)
        drainMainQueue()
        XCTAssertEqual(manager.typingBuffer, "A")
    }

    func testControllerMappedBackspaceUpdatesBuffer() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_A))
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_B))
        manager.notifyControllerKeyPress(keyCode: KeyCodeMapping.delete, modifiers: [])
        drainMainQueue()
        XCTAssertEqual(manager.typingBuffer, "a")
    }

    func testControllerMappedKeyIgnoredWhenKeyboardHidden() {
        // Keyboard is not visible
        manager.hide()
        manager.notifyControllerKeyPress(keyCode: CGKeyCode(kVK_ANSI_A), modifiers: [])
        drainMainQueue()
        XCTAssertEqual(manager.typingBuffer, "")
    }

    func testControllerMappedKeyWithHeldShiftUpdatesBuffer() {
        manager.show()
        // Controller holds shift via one button, another button mapped to 'a'
        mockSimulator.holdModifier(.maskShift)
        manager.notifyControllerKeyPress(keyCode: CGKeyCode(kVK_ANSI_A), modifiers: [])
        drainMainQueue()
        XCTAssertEqual(manager.typingBuffer, "A")
        mockSimulator.releaseModifier(.maskShift)
    }

    // MARK: - Controller-Mapped Delete Keys (Fix: repeat/hold paths)

    func testControllerMappedForwardDeleteUpdatesBuffer() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_A))
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_B))
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_C))
        manager.notifyControllerKeyPress(keyCode: KeyCodeMapping.forwardDelete, modifiers: [])
        drainMainQueue()
        XCTAssertEqual(manager.typingBuffer, "ab")
    }

    func testOnScreenKeyboardForwardDeleteUpdatesBuffer() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_X))
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_Y))
        simulateKeyPress(keyCode: KeyCodeMapping.forwardDelete)
        XCTAssertEqual(manager.typingBuffer, "x")
    }

    func testRepeatedControllerBackspaceRemovesMultipleChars() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_A))
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_B))
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_C))
        // Simulate repeated backspace (as from repeat timer)
        manager.notifyControllerKeyPress(keyCode: KeyCodeMapping.delete, modifiers: [])
        manager.notifyControllerKeyPress(keyCode: KeyCodeMapping.delete, modifiers: [])
        drainMainQueue()
        XCTAssertEqual(manager.typingBuffer, "a")
    }

    func testRepeatedControllerForwardDeleteRemovesMultipleChars() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_A))
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_B))
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_C))
        manager.notifyControllerKeyPress(keyCode: KeyCodeMapping.forwardDelete, modifiers: [])
        manager.notifyControllerKeyPress(keyCode: KeyCodeMapping.forwardDelete, modifiers: [])
        drainMainQueue()
        XCTAssertEqual(manager.typingBuffer, "a")
    }

    func testControllerDeleteOnEmptyBufferDoesNothing() {
        manager.show()
        manager.notifyControllerKeyPress(keyCode: KeyCodeMapping.delete, modifiers: [])
        drainMainQueue()
        XCTAssertEqual(manager.typingBuffer, "")
    }

    func testControllerForwardDeleteOnEmptyBufferDoesNothing() {
        manager.show()
        manager.notifyControllerKeyPress(keyCode: KeyCodeMapping.forwardDelete, modifiers: [])
        drainMainQueue()
        XCTAssertEqual(manager.typingBuffer, "")
    }

    // MARK: - Hide Clears Buffer

    func testHideClearsBuffer() {
        manager.show()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_A))
        XCTAssertEqual(manager.typingBuffer, "a")
        manager.hide()
        XCTAssertEqual(manager.typingBuffer, "")
    }

    // MARK: - Helpers

    /// Simulates an on-screen keyboard key press (calls the internal handleKeyPress path
    /// via activateHighlightedItem with a positioned key, or directly via the onKeyPress callback).
    /// Since handleKeyPress is private, we use the public keyboard activation path.
    private func simulateKeyPress(keyCode: CGKeyCode, modifiers: ModifierFlags = ModifierFlags()) {
        // Use the test-accessible method that mirrors on-screen keyboard press
        manager.testHandleKeyPress(keyCode: keyCode, modifiers: modifiers)
    }

    /// Drain the main dispatch queue to process async dispatches
    private func drainMainQueue() {
        let expectation = expectation(description: "main queue drained")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)
    }

    private func resetManager() {
        manager.exitNavigationMode()
        manager.hide()
        manager.highlightedItem = nil
        manager.lastMouseHoveredItem = nil
        manager.setQuickTexts(
            [],
            defaultTerminal: "Terminal",
            typingDelay: 0.03,
            appBarItems: [],
            websiteLinks: [],
            showExtendedFunctionKeys: false,
            activateAllWindows: true
        )
    }
}
