import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

// MARK: - Sequence Detection Tests

final class SequenceDetectionTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-seq-tests-\(UUID().uuidString)", isDirectory: true)

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

    /// Tests that a simple 3-step sequence (A → B → X) fires via direct callbacks
    func testSequenceDetection_ThreeDistinctButtons() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.a, .b, .x],
                keyCode: 99  // F16
            )
            profileManager.setActiveProfile(Profile(
                name: "SeqTest",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press A → B → X with release between each
        for button: ControllerButton in [.a, .b, .x] {
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
            XCTAssertEqual(sequenceActions.count, 1, "Sequence A→B→X should fire exactly once")
        }
    }

    /// Tests that pressing the SAME button 3 times fires a sequence (L3 × 3)
    func testSequenceDetection_SameButtonThreeTimes_DirectCallback() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                keyCode: 99
            )
            profileManager.setActiveProfile(Profile(
                name: "L3x3",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press L3 three times via direct callback
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.onButtonPressed?(.leftThumbstick)
                controllerService.onButtonReleased?(.leftThumbstick, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 1, "Sequence L3×3 should fire exactly once via direct callback")
        }
    }

    /// Tests that pressing the SAME button 3 times fires through the full buttonPressed path (chord window)
    func testSequenceDetection_SameButtonThreeTimes_ViaButtonPressed() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                keyCode: 99
            )
            profileManager.setActiveProfile(Profile(
                name: "L3x3",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press L3 three times through the full chord window path
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.buttonPressed(.leftThumbstick)
            }
            await waitForTasks(0.1)  // Wait for chord window (0.05) + processing
            await MainActor.run {
                controllerService.buttonReleased(.leftThumbstick)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 1, "Sequence L3×3 should fire through buttonPressed path")
        }
    }

    /// Tests that L3 × 3 works even when L3 has a regular mapping
    func testSequenceDetection_SameButtonThreeTimes_WithRegularMapping() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                keyCode: 99
            )
            let l3Mapping = KeyMapping(keyCode: 50)  // Regular key mapping for L3
            profileManager.setActiveProfile(Profile(
                name: "L3x3+mapping",
                buttonMappings: [.leftThumbstick: l3Mapping],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press L3 three times via direct callback
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.onButtonPressed?(.leftThumbstick)
                controllerService.onButtonReleased?(.leftThumbstick, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            // Individual key presses should fire (3 times)
            let individualActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 50 }
                return false
            }
            XCTAssertEqual(individualActions.count, 3, "Individual L3 mapping should fire 3 times")

            // Sequence should also fire (1 time)
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 1, "Sequence L3×3 should also fire once")
        }
    }

    /// Tests that a 2-button repeated sequence (A × 2) fires correctly
    func testSequenceDetection_SameButtonTwice() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.a, .a],
                keyCode: 99
            )
            profileManager.setActiveProfile(Profile(
                name: "Ax2",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        for _ in 0..<2 {
            await MainActor.run {
                controllerService.onButtonPressed?(.a)
                controllerService.onButtonReleased?(.a, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 1, "Sequence A×2 should fire exactly once")
        }
    }

    /// Tests L3 × 3 with realistic chord window and hold times — exposes the timing bug
    /// The chord window (150ms default) delays when advanceSequenceTracking runs,
    /// so the step timeout check measures chord-window-inflated time, not physical press time.
    func testSequenceDetection_SameButtonThreeTimes_RealisticChordWindow() async throws {
        await MainActor.run {
            // Use production-like chord window
            controllerService.chordWindow = 0.15

            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                stepTimeout: 0.4,  // Default
                keyCode: 99
            )
            profileManager.setActiveProfile(Profile(
                name: "L3x3Realistic",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Simulate realistic thumbstick clicks: press for 120ms, 200ms gap between clicks
        for i in 0..<3 {
            await MainActor.run {
                controllerService.buttonPressed(.leftThumbstick)
            }
            // Hold for 120ms (realistic stick click hold time)
            await waitForTasks(0.12)
            await MainActor.run {
                controllerService.buttonReleased(.leftThumbstick)
            }
            if i < 2 {
                // Wait 200ms between presses (realistic for rapid thumbstick clicking)
                await waitForTasks(0.2)
            }
        }
        // Wait for chord window + processing
        await waitForTasks(0.4)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 1,
                "Sequence L3×3 should fire with realistic timing (120ms holds, 200ms gaps)")
        }
    }

    /// Tests that sequence times out when presses are too slow
    func testSequenceDetection_Timeout() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.a, .a, .a],
                stepTimeout: 0.1,  // Very short timeout
                keyCode: 99
            )
            profileManager.setActiveProfile(Profile(
                name: "Timeout",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // First press
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        // Wait longer than the step timeout
        await waitForTasks(0.2)

        // Second and third press
        for _ in 0..<2 {
            await MainActor.run {
                controllerService.onButtonPressed?(.a)
                controllerService.onButtonReleased?(.a, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 0, "Sequence should NOT fire when step timeout elapses")
        }
    }

    // MARK: - Special Virtual Key Code Tests

    /// Tests that a sequence mapped to the laser pointer virtual key code toggles the laser pointer
    func testSequenceDetection_LaserPointerVirtualKeyCode() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                keyCode: KeyCodeMapping.showLaserPointer
            )
            profileManager.setActiveProfile(Profile(
                name: "LaserSeq",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Verify laser is not showing initially
        await MainActor.run {
            XCTAssertFalse(LaserPointerOverlay.shared.isShowing, "Laser should not be showing initially")
        }

        // Press L3 three times via direct callback
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.onButtonPressed?(.leftThumbstick)
                controllerService.onButtonReleased?(.leftThumbstick, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.15)

        // Laser pointer should now be showing
        await MainActor.run {
            XCTAssertTrue(LaserPointerOverlay.shared.isShowing,
                "Sequence with laser pointer key code should toggle laser ON")
        }

        // The virtual key code should NOT have been sent as an actual key press
        await MainActor.run {
            let laserKeyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.showLaserPointer }
                return false
            }
            XCTAssertEqual(laserKeyPresses.count, 0,
                "Laser pointer virtual key code should NOT be sent as an actual key press")
        }

        // Clean up: hide the laser
        await MainActor.run {
            LaserPointerOverlay.shared.hide()
        }
    }

    /// Tests that a sequence mapped to the on-screen keyboard virtual key code toggles the keyboard
    func testSequenceDetection_OnScreenKeyboardVirtualKeyCode() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.a, .b],
                keyCode: KeyCodeMapping.showOnScreenKeyboard
            )
            profileManager.setActiveProfile(Profile(
                name: "KbdSeq",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Verify keyboard is not visible initially
        await MainActor.run {
            XCTAssertFalse(OnScreenKeyboardManager.shared.isVisible, "Keyboard should not be visible initially")
        }

        // Press A then B
        for button: ControllerButton in [.a, .b] {
            await MainActor.run {
                controllerService.onButtonPressed?(button)
                controllerService.onButtonReleased?(button, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.15)

        // On-screen keyboard should now be visible
        await MainActor.run {
            XCTAssertTrue(OnScreenKeyboardManager.shared.isVisible,
                "Sequence with on-screen keyboard key code should toggle keyboard ON")
        }

        // The virtual key code should NOT have been sent as an actual key press
        await MainActor.run {
            let kbdKeyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.showOnScreenKeyboard }
                return false
            }
            XCTAssertEqual(kbdKeyPresses.count, 0,
                "On-screen keyboard virtual key code should NOT be sent as an actual key press")
        }

        // Clean up: hide the keyboard
        await MainActor.run {
            OnScreenKeyboardManager.shared.hide()
        }
    }

    /// Tests that a chord mapped to the laser pointer virtual key code toggles the laser pointer
    func testChordDetection_LaserPointerVirtualKeyCode() async throws {
        await MainActor.run {
            let chord = ChordMapping(
                buttons: [.leftBumper, .rightBumper],
                keyCode: KeyCodeMapping.showLaserPointer
            )
            profileManager.setActiveProfile(Profile(
                name: "LaserChord",
                buttonMappings: [:],
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Verify laser is not showing initially
        await MainActor.run {
            XCTAssertFalse(LaserPointerOverlay.shared.isShowing, "Laser should not be showing initially")
        }

        // Simulate chord via onChordDetected callback
        await MainActor.run {
            controllerService.onChordDetected?([.leftBumper, .rightBumper])
        }
        await waitForTasks(0.15)

        // Laser pointer should now be showing
        await MainActor.run {
            XCTAssertTrue(LaserPointerOverlay.shared.isShowing,
                "Chord with laser pointer key code should toggle laser ON")
        }

        // The virtual key code should NOT have been sent as an actual key press
        await MainActor.run {
            let laserKeyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.showLaserPointer }
                return false
            }
            XCTAssertEqual(laserKeyPresses.count, 0,
                "Laser pointer virtual key code should NOT be sent as an actual key press via chord")
        }

        // Clean up
        await MainActor.run {
            LaserPointerOverlay.shared.hide()
        }
    }
}
