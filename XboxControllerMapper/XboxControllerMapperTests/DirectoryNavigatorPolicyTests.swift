import XCTest
@testable import ControllerKeys

final class DirectoryNavigatorPolicyTests: XCTestCase {

    // MARK: - D-pad interception when navigator visible

    func testDpadUp_WhenNavigatorVisible_InterceptsNavigation() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadUp,
            mapping: .key(1),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryNavigation)
    }

    func testDpadDown_WhenNavigatorVisible_InterceptsNavigation() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadDown,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryNavigation)
    }

    func testDpadLeft_WhenNavigatorVisible_InterceptsNavigation() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadLeft,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryNavigation)
    }

    func testDpadRight_WhenNavigatorVisible_InterceptsNavigation() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadRight,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryNavigation)
    }

    // MARK: - A and X confirm (cd here)

    func testAButton_WhenNavigatorVisible_InterceptsConfirm() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryConfirm)
    }

    func testXButton_WhenNavigatorVisible_InterceptsConfirm() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .x,
            mapping: KeyMapping(keyCode: 0),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryConfirm)
    }

    // MARK: - B confirms (cd here)

    func testBButton_WhenNavigatorVisible_InterceptsConfirm() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .b,
            mapping: KeyMapping(keyCode: 0),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryConfirm)
    }

    // MARK: - Y dismisses (close without terminal)

    func testYButton_WhenNavigatorVisible_InterceptsDismiss() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .y,
            mapping: KeyMapping(keyCode: 0),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryDismiss)
    }

    // MARK: - Other buttons pass through when navigator visible

    func testLeftBumper_WhenNavigatorVisible_NotIntercepted() {
        let mapping = KeyMapping(keyCode: 0)
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .leftBumper,
            mapping: mapping,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertNotEqual(outcome, .interceptDirectoryNavigation)
        XCTAssertNotEqual(outcome, .interceptDirectoryConfirm)
        XCTAssertNotEqual(outcome, .interceptDirectoryDismiss)
    }

    // MARK: - Navigator hidden: no interception

    func testDpadUp_WhenNavigatorHidden_NotInterceptedForNavigator() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadUp,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertNotEqual(outcome, .interceptDirectoryNavigation)
    }

    func testAButton_WhenNavigatorHidden_NotInterceptedForNavigator() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertNotEqual(outcome, .interceptDirectoryConfirm)
    }

    func testBButton_WhenNavigatorHidden_NotInterceptedForNavigator() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .b,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertNotEqual(outcome, .interceptDirectoryConfirm)
    }

    func testYButton_WhenNavigatorHidden_NotInterceptedForNavigator() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .y,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertNotEqual(outcome, .interceptDirectoryDismiss)
    }

    // MARK: - Navigator takes priority over keyboard

    func testDpadUp_WhenBothNavigatorAndKeyboardVisible_NavigatorWins() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .dpadUp,
            mapping: .key(1),
            keyboardVisible: true,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        // Directory navigator interception is checked before keyboard
        XCTAssertEqual(outcome, .interceptDirectoryNavigation)
    }

    func testAButton_WhenBothNavigatorAndKeyboardVisible_NavigatorWins() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick),
            keyboardVisible: true,
            navigationModeActive: true,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        // Directory navigator confirm takes priority over keyboard activation
        XCTAssertEqual(outcome, .interceptDirectoryConfirm)
    }

    // MARK: - Directory Navigator special key code mapping

    func testDirectoryNavigatorMapping_InterceptsAsNavigator() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.showDirectoryNavigator, isHoldModifier: false),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryNavigator(holdMode: false))
    }

    func testDirectoryNavigatorMapping_HoldMode() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.showDirectoryNavigator, isHoldModifier: true),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryNavigator(holdMode: true))
    }

    // MARK: - A unmapped when navigator visible still confirms

    func testAButton_WhenNavigatorVisible_ConfirmsEvenWithoutMapping() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryConfirm)
    }

    func testBButton_WhenNavigatorVisible_ConfirmsEvenWithoutMapping() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .b,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryConfirm)
    }

    func testXButton_WhenNavigatorVisible_ConfirmsEvenWithoutMapping() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .x,
            mapping: nil,
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )
        XCTAssertEqual(outcome, .interceptDirectoryConfirm)
    }
}

// MARK: - DirectoryNavigatorManager Mouse & Position Tests

@MainActor
final class DirectoryNavigatorManagerTests: XCTestCase {

    private var tempDir: URL!
    private var manager: DirectoryNavigatorManager!

    override func setUp() {
        super.setUp()
        manager = DirectoryNavigatorManager.shared

        // Create a temp directory with known structure
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectoryNavigatorTests-\(UUID().uuidString)")
        let fm = FileManager.default
        try? fm.createDirectory(at: tempDir.appendingPathComponent("Alpha"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: tempDir.appendingPathComponent("Beta"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: tempDir.appendingPathComponent("Gamma"), withIntermediateDirectories: true)
        fm.createFile(atPath: tempDir.appendingPathComponent("file1.txt").path, contents: nil)
        fm.createFile(atPath: tempDir.appendingPathComponent("file2.txt").path, contents: nil)

        // Subdirectories inside Alpha
        try? fm.createDirectory(at: tempDir.appendingPathComponent("Alpha/Sub1"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: tempDir.appendingPathComponent("Alpha/Sub2"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        manager.hide()
        manager.navigateTo(FileManager.default.homeDirectoryForCurrentUser)
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func navigateToTempDir() {
        manager.navigateTo(tempDir)
    }

    // MARK: - Mouse: selectEntry(at:)

    func testSelectEntry_UpdatesSelectedIndex() {
        navigateToTempDir()
        // Entries are sorted: directories first (Alpha, Beta, Gamma), then files (file1.txt, file2.txt)
        XCTAssertEqual(manager.selectedIndex, 0)

        manager.selectEntry(at: 2)
        XCTAssertEqual(manager.selectedIndex, 2)
        XCTAssertEqual(manager.currentEntries[2].name, "Gamma")
    }

    func testSelectEntry_UpdatesPreview() {
        navigateToTempDir()
        manager.selectEntry(at: 0) // Alpha
        // Alpha has Sub1 and Sub2
        XCTAssertEqual(manager.previewEntries.count, 2)
        XCTAssertTrue(manager.previewEntries.contains(where: { $0.name == "Sub1" }))
    }

    func testSelectEntry_OutOfBounds_DoesNotCrash() {
        navigateToTempDir()
        let originalIndex = manager.selectedIndex
        manager.selectEntry(at: -1)
        XCTAssertEqual(manager.selectedIndex, originalIndex)
        manager.selectEntry(at: 999)
        XCTAssertEqual(manager.selectedIndex, originalIndex)
    }

    func testSelectEntry_ClearsPreviewForFile() {
        navigateToTempDir()
        // Select Alpha first (has preview)
        manager.selectEntry(at: 0)
        XCTAssertFalse(manager.previewEntries.isEmpty)

        // Select file1.txt (index 3, after 3 directories)
        manager.selectEntry(at: 3)
        XCTAssertTrue(manager.previewEntries.isEmpty)
    }

    // MARK: - Mouse: activateEntry(at:)

    func testActivateEntry_EntersDirectory() {
        navigateToTempDir()
        manager.activateEntry(at: 0) // Alpha
        XCTAssertEqual(manager.currentDirectory.lastPathComponent, "Alpha")
        // Should now show Sub1, Sub2
        XCTAssertEqual(manager.currentEntries.count, 2)
    }

    func testActivateEntry_DoesNotEnterFile() {
        navigateToTempDir()
        let originalDir = manager.currentDirectory
        // file1.txt is at index 3 (after Alpha, Beta, Gamma)
        manager.activateEntry(at: 3)
        XCTAssertEqual(manager.currentDirectory, originalDir)
    }

    func testActivateEntry_OutOfBounds_DoesNotCrash() {
        navigateToTempDir()
        let originalDir = manager.currentDirectory
        manager.activateEntry(at: -1)
        XCTAssertEqual(manager.currentDirectory, originalDir)
        manager.activateEntry(at: 999)
        XCTAssertEqual(manager.currentDirectory, originalDir)
    }

    func testActivateEntry_SetsSelectedIndexBeforeEntering() {
        navigateToTempDir()
        // Activate Beta (index 1) — should select it then enter
        manager.activateEntry(at: 1)
        // After entering Beta (which is empty), selectedIndex resets to 0
        XCTAssertEqual(manager.selectedIndex, 0)
        XCTAssertEqual(manager.currentDirectory.lastPathComponent, "Beta")
    }

    // MARK: - Position Memory

    func testShow_PreservesSelectedIndex() {
        manager.navigateTo(tempDir)
        manager.show()
        manager.selectEntry(at: 2) // Gamma
        XCTAssertEqual(manager.selectedIndex, 2)

        manager.hide()
        manager.show()

        // Should still be at index 2 (Gamma)
        XCTAssertEqual(manager.selectedIndex, 2)
        XCTAssertEqual(manager.currentEntries[2].name, "Gamma")
    }

    func testShow_PreservesDirectory() {
        manager.navigateTo(tempDir)
        manager.show()
        manager.activateEntry(at: 0) // Enter Alpha
        XCTAssertEqual(manager.currentDirectory.lastPathComponent, "Alpha")

        manager.hide()
        manager.show()

        XCTAssertEqual(manager.currentDirectory.lastPathComponent, "Alpha")
    }

    func testShow_ClampsIndexWhenEntryRemoved() {
        manager.navigateTo(tempDir)
        manager.show()
        // Select last entry (file2.txt, index 4)
        manager.selectEntry(at: manager.currentEntries.count - 1)

        manager.hide()

        // Remove file2.txt
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("file2.txt"))

        manager.show()

        // Index should be clamped, not crash
        XCTAssertLessThan(manager.selectedIndex, manager.currentEntries.count)
        XCTAssertGreaterThanOrEqual(manager.selectedIndex, 0)
    }

    func testShow_RestoresSelectionByName() {
        manager.navigateTo(tempDir)
        manager.show()
        manager.selectEntry(at: 2) // Gamma
        XCTAssertEqual(manager.currentEntries[manager.selectedIndex].name, "Gamma")

        manager.hide()

        // Add a new directory that sorts before Gamma, shifting indices
        try? FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("Delta"),
            withIntermediateDirectories: true
        )

        manager.show()

        // Should find Gamma by name even though index shifted
        XCTAssertEqual(manager.currentEntries[manager.selectedIndex].name, "Gamma")
    }
}

// MARK: - KeyCodeMapping Directory Navigator Tests

final class KeyCodeMappingDirectoryNavigatorTests: XCTestCase {

    func testDirectoryNavigatorKeyCode_HasDisplayName() {
        XCTAssertEqual(
            KeyCodeMapping.displayName(for: KeyCodeMapping.showDirectoryNavigator),
            "Directory Navigator"
        )
    }

    func testDirectoryNavigatorKeyCode_IsSpecialAction() {
        XCTAssertTrue(KeyCodeMapping.isSpecialAction(KeyCodeMapping.showDirectoryNavigator))
    }

    func testDirectoryNavigatorKeyCode_IsSpecialMarker() {
        XCTAssertTrue(KeyCodeMapping.isSpecialMarker(KeyCodeMapping.showDirectoryNavigator))
    }

    func testDirectoryNavigatorKeyCode_IsNotMouseButton() {
        XCTAssertFalse(KeyCodeMapping.isMouseButton(KeyCodeMapping.showDirectoryNavigator))
    }

    func testDirectoryNavigatorKeyCode_IsNotMediaKey() {
        XCTAssertFalse(KeyCodeMapping.isMediaKey(KeyCodeMapping.showDirectoryNavigator))
    }

    func testDirectoryNavigatorKeyCode_InAllKeyOptions() {
        let options = KeyCodeMapping.allKeyOptions
        XCTAssertTrue(options.contains(where: { $0.name == "Directory Navigator" }))
    }
}
