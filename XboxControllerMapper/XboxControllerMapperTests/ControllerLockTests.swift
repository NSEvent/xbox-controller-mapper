import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

// MARK: - Controller Lock Tests

@MainActor
final class ControllerLockTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-lock-tests-\(UUID().uuidString)", isDirectory: true)

        await MainActor.run {
            controllerService = ControllerService(enableHardwareMonitoring: false)
            controllerService.chordWindow = 0.05
            profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
            appMonitor = AppMonitor()
            mockInputSimulator = MockInputSimulator()

            mappingEngine = MappingEngine(
                controllerService: controllerService,
                profileManager: profileManager,
                appMonitor: appMonitor,
                inputSimulator: mockInputSimulator
            )

            mappingEngine.enable()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            mappingEngine?.disable()
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await MainActor.run {
            mockInputSimulator?.releaseAllModifiers()
            controllerService?.onButtonPressed = nil
            controllerService?.onButtonReleased = nil
            controllerService?.onChordDetected = nil
            controllerService?.cleanup()
            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func waitForTasks(_ delay: TimeInterval = 0.4) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    // MARK: 1. Lock via single button — blocks subsequent presses

    func testLockViaSingleButton_BlocksSubsequentPresses() async throws {
        await MainActor.run {
            let lockMapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock)
            let aMapping = KeyMapping(keyCode: 0) // 'A' key
            profileManager.installTestProfile(Profile(
                name: "LockTest",
                buttonMappings: [.x: lockMapping, .a: aMapping]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press X to lock
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.1)

        // Verify locked
        await MainActor.run {
            XCTAssertTrue(mappingEngine.isLocked, "Engine should be locked after pressing lock button")
        }

        // Clear events from lock action
        await MainActor.run { mockInputSimulator.clearEvents() }

        // Press A — should be blocked
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let keyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                if case .executeMapping = event { return true }
                return false
            }
            XCTAssertEqual(keyPresses.count, 0, "Button presses should be blocked while locked")
        }
    }

    // MARK: 2. Unlock via single button — resumes normal mapping

    func testUnlockViaSingleButton_ResumesMapping() async throws {
        await MainActor.run {
            let lockMapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock)
            let aMapping = KeyMapping(keyCode: 0)
            profileManager.installTestProfile(Profile(
                name: "UnlockTest",
                buttonMappings: [.x: lockMapping, .a: aMapping]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Lock
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.1)

        // Unlock
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            XCTAssertFalse(mappingEngine.isLocked, "Engine should be unlocked after toggling lock button again")
        }

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Press A — should work now
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let hasKeyAction = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                if case .executeMapping = event { return true }
                return false
            }
            XCTAssertTrue(hasKeyAction, "Button presses should work after unlocking")
        }
    }

    // MARK: 3. Lock via sequence (L3×3) — blocks actions

    func testLockViaSequence_BlocksActions() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                keyCode: KeyCodeMapping.controllerLock
            )
            let aMapping = KeyMapping(keyCode: 0)
            profileManager.installTestProfile(Profile(
                name: "SeqLock",
                buttonMappings: [.a: aMapping],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press L3 three times to trigger sequence lock
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.onButtonPressed?(.leftThumbstick)
                controllerService.onButtonReleased?(.leftThumbstick, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mappingEngine.isLocked, "Engine should be locked after sequence")
        }

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Press A — should be blocked
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let keyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                if case .executeMapping = event { return true }
                return false
            }
            XCTAssertEqual(keyPresses.count, 0, "Actions should be blocked after sequence lock")
        }
    }

    // MARK: 4. Unlock via sequence — resumes actions

    func testUnlockViaSequence_ResumesActions() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                keyCode: KeyCodeMapping.controllerLock
            )
            let aMapping = KeyMapping(keyCode: 0)
            profileManager.installTestProfile(Profile(
                name: "SeqUnlock",
                buttonMappings: [.a: aMapping],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Lock via sequence
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.onButtonPressed?(.leftThumbstick)
                controllerService.onButtonReleased?(.leftThumbstick, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.2)

        // Unlock via sequence
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.onButtonPressed?(.leftThumbstick)
                controllerService.onButtonReleased?(.leftThumbstick, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertFalse(mappingEngine.isLocked, "Engine should be unlocked after second sequence")
        }

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Press A — should work
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let hasKeyAction = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                if case .executeMapping = event { return true }
                return false
            }
            XCTAssertTrue(hasKeyAction, "Actions should resume after sequence unlock")
        }
    }

    // MARK: 5. Lock via chord (LB+RB) — blocks actions

    func testLockViaChord_BlocksActions() async throws {
        await MainActor.run {
            let chord = ChordMapping(
                buttons: [.leftBumper, .rightBumper],
                keyCode: KeyCodeMapping.controllerLock
            )
            let aMapping = KeyMapping(keyCode: 0)
            profileManager.installTestProfile(Profile(
                name: "ChordLock",
                buttonMappings: [.a: aMapping],
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press chord LB+RB
        await MainActor.run {
            controllerService.onChordDetected?([.leftBumper, .rightBumper])
        }
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mappingEngine.isLocked, "Engine should be locked after chord")
        }

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Press A — should be blocked
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let keyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                if case .executeMapping = event { return true }
                return false
            }
            XCTAssertEqual(keyPresses.count, 0, "Actions should be blocked after chord lock")
        }
    }

    // MARK: 6. Unlock via chord — resumes actions

    func testUnlockViaChord_ResumesActions() async throws {
        await MainActor.run {
            let chord = ChordMapping(
                buttons: [.leftBumper, .rightBumper],
                keyCode: KeyCodeMapping.controllerLock
            )
            let aMapping = KeyMapping(keyCode: 0)
            profileManager.installTestProfile(Profile(
                name: "ChordUnlock",
                buttonMappings: [.a: aMapping],
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Lock
        await MainActor.run {
            controllerService.onChordDetected?([.leftBumper, .rightBumper])
        }
        await waitForTasks(0.2)

        // Release chord buttons
        await MainActor.run {
            controllerService.onButtonReleased?(.leftBumper, 0.1)
            controllerService.onButtonReleased?(.rightBumper, 0.1)
        }
        await waitForTasks(0.1)

        // Unlock
        await MainActor.run {
            controllerService.onChordDetected?([.leftBumper, .rightBumper])
        }
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertFalse(mappingEngine.isLocked, "Engine should be unlocked after second chord")
        }

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Press A — should work
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let hasKeyAction = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                if case .executeMapping = event { return true }
                return false
            }
            XCTAssertTrue(hasKeyAction, "Actions should resume after chord unlock")
        }
    }

    // MARK: 7. Lock releases held modifiers

    func testLockReleasesHeldModifiers() async throws {
        await MainActor.run {
            let lockMapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock)
            let holdMapping = KeyMapping.holdModifier(.command)
            profileManager.installTestProfile(Profile(
                name: "LockModifiers",
                buttonMappings: [.x: lockMapping, .leftBumper: holdMapping]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Hold LB (command modifier)
        await MainActor.run {
            controllerService.onButtonPressed?(.leftBumper)
        }
        await waitForTasks(0.1)

        // Verify modifier is held
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand),
                "Command modifier should be held")
        }

        // Lock — should release modifiers
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mappingEngine.isLocked, "Engine should be locked")
            let hasReleaseAll = mockInputSimulator.events.contains { event in
                if case .releaseAllModifiers = event { return true }
                return false
            }
            XCTAssertTrue(hasReleaseAll, "Lock should release all held modifiers")
        }
    }

    // MARK: 8. Lock persists across isEnabled toggle

    func testLockPersistsAcrossEnableToggle() async throws {
        await MainActor.run {
            let lockMapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock)
            profileManager.installTestProfile(Profile(
                name: "LockPersist",
                buttonMappings: [.x: lockMapping]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Lock
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            XCTAssertTrue(mappingEngine.isLocked, "Engine should be locked")
        }

        // Disable and re-enable
        await MainActor.run {
            mappingEngine.isEnabled = false
        }
        await waitForTasks(0.1)
        await MainActor.run {
            mappingEngine.isEnabled = true
        }
        await waitForTasks(0.1)

        // Lock should still be active
        await MainActor.run {
            XCTAssertTrue(mappingEngine.isLocked, "Lock should persist across enable/disable toggle")
        }
    }

    // MARK: 9. Non-lock sequence blocked while locked

    func testNonLockSequenceBlockedWhileLocked() async throws {
        await MainActor.run {
            let lockMapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock)
            let otherSeq = SequenceMapping(
                steps: [.a, .b],
                keyCode: 99  // F16
            )
            profileManager.installTestProfile(Profile(
                name: "SeqBlocked",
                buttonMappings: [.x: lockMapping],
                sequenceMappings: [otherSeq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Lock
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Try sequence A → B while locked
        for button: ControllerButton in [.a, .b] {
            await MainActor.run {
                controllerService.onButtonPressed?(button)
                controllerService.onButtonReleased?(button, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 0, "Non-lock sequences should be blocked while locked")
        }
    }

    // MARK: 10. Non-lock chord blocked while locked

    func testNonLockChordBlockedWhileLocked() async throws {
        await MainActor.run {
            let lockMapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock)
            let otherChord = ChordMapping(
                buttons: [.a, .b],
                keyCode: 99
            )
            profileManager.installTestProfile(Profile(
                name: "ChordBlocked",
                buttonMappings: [.x: lockMapping],
                chordMappings: [otherChord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Lock
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Try chord A+B while locked
        await MainActor.run {
            controllerService.onChordDetected?([.a, .b])
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let chordActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(chordActions.count, 0, "Non-lock chords should be blocked while locked")
        }
    }
}
