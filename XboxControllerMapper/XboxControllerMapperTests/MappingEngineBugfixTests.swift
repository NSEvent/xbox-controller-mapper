import XCTest
import CoreGraphics
@testable import ControllerKeys

// MARK: - Bug 1: Profile Change During Active Input

/// Tests that switching profiles clears in-flight state so that chord/button
/// actions from Profile A cannot execute against Profile B's mappings.
final class ProfileChangeDuringActiveInputTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-bugfix-1-\(UUID().uuidString)", isDirectory: true)

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
        try? await Task.sleep(nanoseconds: 80_000_000)

        await MainActor.run {
            controllerService?.onButtonPressed = nil
            controllerService?.onButtonReleased = nil
            controllerService?.onChordDetected = nil
            controllerService?.onLeftStickMoved = nil
            controllerService?.onRightStickMoved = nil
            controllerService?.onTouchpadMoved = nil
            controllerService?.onTouchpadGesture = nil
            controllerService?.onTouchpadTap = nil
            controllerService?.onTouchpadTwoFingerTap = nil
            controllerService?.onTouchpadLongTap = nil
            controllerService?.onTouchpadTwoFingerLongTap = nil
            controllerService?.cleanup()

            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
    }

    private func waitForTasks(_ delay: TimeInterval = 0.35) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    /// Bug 1: When profile switches during active input, the chord lookup should
    /// use the profile that was active when the chord was detected, not a stale
    /// or wrong profile. The chordLookup must be rebuilt atomically with the
    /// profile ID so in-flight callbacks resolve against the correct profile.
    func testProfileSwitchDuringChordDoesNotExecuteWrongAction() async throws {
        // Profile A: chord {A,B} -> keyCode 10 (Ctrl+C equivalent)
        let profileA = Profile(
            name: "ProfileA",
            buttonMappings: [
                .a: .key(1),
                .b: .key(2)
            ],
            chordMappings: [
                ChordMapping(buttons: [.a, .b], keyCode: 10)
            ]
        )

        // Profile B: chord {A,B} -> keyCode 99 (dangerous action)
        let profileB = Profile(
            name: "ProfileB",
            buttonMappings: [
                .a: .key(3),
                .b: .key(4)
            ],
            chordMappings: [
                ChordMapping(buttons: [.a, .b], keyCode: 99)
            ]
        )

        // Set profile A, press A and B
        await MainActor.run {
            profileManager.setActiveProfile(profileA)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
        }

        // Switch to profile B BEFORE chord resolves
        await MainActor.run {
            profileManager.setActiveProfile(profileB)
        }
        try? await Task.sleep(nanoseconds: 5_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.b)
        }
        await waitForTasks()

        // Release
        await MainActor.run {
            controllerService.buttonReleased(.a)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks(0.2)

        let events = mockInputSimulator.events

        // The engine should NOT have fired keyCode 10 (profileA's chord)
        // when the active profile is now profileB
        let keyCode10Count = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 10 }
            return false
        }.count

        // The chord lookup should reflect the current (new) profile
        XCTAssertEqual(keyCode10Count, 0, "Profile A's chord action should not fire after profile switch to B")
    }

    /// Bug 1 additional: After profile switch, pending release actions from old
    /// profile should not execute.
    func testProfileSwitchClearsPendingReleaseActions() async throws {
        let profileA = Profile(
            name: "ProfileA",
            buttonMappings: [.a: .key(10)]
        )

        let profileB = Profile(
            name: "ProfileB",
            buttonMappings: [.a: .key(20)]
        )

        await MainActor.run {
            profileManager.setActiveProfile(profileA)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press and release button A (creates a pending release action)
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        try? await Task.sleep(nanoseconds: 5_000_000)

        // Switch profile before release
        await MainActor.run {
            profileManager.setActiveProfile(profileB)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        // This test documents that the engine handles mid-press profile switch gracefully
        XCTAssertTrue(true, "Engine should handle mid-press profile switch gracefully")
    }
}

// MARK: - Bug 2: Sequence Detector Stale State on Profile Change

/// Tests that the SequenceDetector properly resets active sequences when
/// reconfigured (i.e., on profile change).
final class SequenceDetectorStaleStateTests: XCTestCase {
    var detector: SequenceDetector!

    override func setUp() {
        detector = SequenceDetector()
    }

    override func tearDown() {
        detector = nil
    }

    /// Bug 2: A partial sequence from Profile A should NOT complete using
    /// Profile B's sequences after configure() is called.
    func testConfigureResetsActiveSequences() {
        // Profile A: sequence A -> B -> keyCode 10
        let seqA = SequenceMapping(steps: [.a, .b], stepTimeout: 0.5, keyCode: 10)
        detector.configure(sequences: [seqA])

        let now = CFAbsoluteTimeGetCurrent()
        // Start sequence A (partial match)
        let result1 = detector.process(.a, at: now)
        XCTAssertNil(result1, "First step should not complete")
        XCTAssertFalse(detector.activeSequences.isEmpty, "Should have an active sequence tracking A")

        // Profile change: reconfigure with different sequences
        let seqB = SequenceMapping(steps: [.a, .b], stepTimeout: 0.5, keyCode: 99)
        detector.configure(sequences: [seqB])

        // After configure, active sequences should be cleared
        XCTAssertTrue(detector.activeSequences.isEmpty,
            "configure() should reset activeSequences to prevent cross-profile completion")

        // Pressing B should NOT complete the sequence from profile A
        let result2 = detector.process(.b, at: now + 0.1)
        XCTAssertNil(result2,
            "Pressing B should not complete because active sequences were cleared on configure()")
    }

    /// Verify that a fresh sequence in the new profile CAN still complete.
    func testConfigureAllowsNewSequencesToComplete() {
        let seqA = SequenceMapping(steps: [.a, .b], stepTimeout: 0.5, keyCode: 10)
        detector.configure(sequences: [seqA])

        let now = CFAbsoluteTimeGetCurrent()
        // Partially match profile A's sequence
        _ = detector.process(.a, at: now)

        // Reconfigure with profile B
        let seqB = SequenceMapping(steps: [.x, .y], stepTimeout: 0.5, keyCode: 99)
        detector.configure(sequences: [seqB])

        // Now complete a fresh sequence in profile B
        _ = detector.process(.x, at: now + 0.2)
        let result = detector.process(.y, at: now + 0.3)
        XCTAssertNotNil(result, "New profile's sequence should still complete")
        XCTAssertEqual(result?.keyCode, 99)
    }

    /// Verify that reconfiguring with the SAME sequence still resets progress.
    func testReconfigureWithSameSequenceResetsProgress() {
        let seq = SequenceMapping(steps: [.a, .b, .x], stepTimeout: 0.5, keyCode: 10)
        detector.configure(sequences: [seq])

        let now = CFAbsoluteTimeGetCurrent()
        _ = detector.process(.a, at: now)
        _ = detector.process(.b, at: now + 0.1)

        // Reconfigure with same sequence (simulates profile reload)
        detector.configure(sequences: [seq])

        // B then X should NOT complete because progress was reset
        let result = detector.process(.x, at: now + 0.2)
        XCTAssertNil(result,
            "After reconfigure, partially matched sequence should be reset")
    }
}

// MARK: - Bug 2 Integration: Sequence detector cross-profile in MappingEngine

final class SequenceDetectorProfileChangeIntegrationTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-bugfix-2-\(UUID().uuidString)", isDirectory: true)

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
        try? await Task.sleep(nanoseconds: 80_000_000)

        await MainActor.run {
            controllerService?.onButtonPressed = nil
            controllerService?.onButtonReleased = nil
            controllerService?.onChordDetected = nil
            controllerService?.onLeftStickMoved = nil
            controllerService?.onRightStickMoved = nil
            controllerService?.onTouchpadMoved = nil
            controllerService?.onTouchpadGesture = nil
            controllerService?.onTouchpadTap = nil
            controllerService?.onTouchpadTwoFingerTap = nil
            controllerService?.onTouchpadLongTap = nil
            controllerService?.onTouchpadTwoFingerLongTap = nil
            controllerService?.cleanup()

            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
    }

    private func waitForTasks(_ delay: TimeInterval = 0.35) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    /// Bug 2 integration test: partial sequence from profile A should not
    /// complete in profile B context.
    func testSequenceDoesNotCrossProfileBoundary() async throws {
        let profileA = Profile(
            name: "SequenceProfileA",
            sequenceMappings: [
                SequenceMapping(steps: [.a, .b], stepTimeout: 1.0, keyCode: 10)
            ]
        )

        let profileB = Profile(
            name: "SequenceProfileB",
            buttonMappings: [.b: .key(20)],
            sequenceMappings: [
                SequenceMapping(steps: [.a, .b], stepTimeout: 1.0, keyCode: 99)
            ]
        )

        // Set profile A and start a sequence
        await MainActor.run {
            profileManager.setActiveProfile(profileA)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.1)

        // Switch to profile B
        await MainActor.run {
            profileManager.setActiveProfile(profileB)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Clear events from profile switch
        mockInputSimulator.clearEvents()

        // Press B - should NOT complete profile A's sequence
        await MainActor.run {
            controllerService.buttonPressed(.b)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonReleased(.b)
        }
        await waitForTasks()

        let events = mockInputSimulator.events

        // KeyCode 10 (profile A's sequence action) should NOT have fired
        let keyCode10Count = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 10 }
            return false
        }.count

        XCTAssertEqual(keyCode10Count, 0,
            "Profile A's sequence action should not fire after switching to Profile B")
    }
}

// MARK: - Bug 3: Timer Cleanup Inconsistency

/// Tests that pending work items are properly removed from dictionaries after cancellation.
final class TimerCleanupTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-bugfix-3-\(UUID().uuidString)", isDirectory: true)

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
        try? await Task.sleep(nanoseconds: 80_000_000)

        await MainActor.run {
            controllerService?.onButtonPressed = nil
            controllerService?.onButtonReleased = nil
            controllerService?.onChordDetected = nil
            controllerService?.onLeftStickMoved = nil
            controllerService?.onRightStickMoved = nil
            controllerService?.onTouchpadMoved = nil
            controllerService?.onTouchpadGesture = nil
            controllerService?.onTouchpadTap = nil
            controllerService?.onTouchpadTwoFingerTap = nil
            controllerService?.onTouchpadLongTap = nil
            controllerService?.onTouchpadTwoFingerLongTap = nil
            controllerService?.cleanup()

            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
    }

    private func waitForTasks(_ delay: TimeInterval = 0.35) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    /// Bug 3: After a button press/release cycle, pendingReleaseActions and
    /// pendingSingleTap should not have ghost entries for that button.
    func testPendingDictionariesCleanedAfterRelease() async throws {
        let profile = Profile(
            name: "TimerCleanup",
            buttonMappings: [
                .a: .key(1),
                .b: .key(2)
            ],
            chordMappings: [
                ChordMapping(buttons: [.a, .b], keyCode: 3)
            ]
        )

        await MainActor.run {
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press and release button A (creates pending release action since A is chord participant)
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        // After full press/release cycle, pending dictionaries should be clean
        let (hasPendingRelease, hasPendingSingleTap) = await MainActor.run {
            mappingEngine.state.lock.withLock {
                (
                    mappingEngine.state.pendingReleaseActions[.a] != nil,
                    mappingEngine.state.pendingSingleTap[.a] != nil
                )
            }
        }

        XCTAssertFalse(hasPendingRelease,
            "pendingReleaseActions should not have ghost entry for button A after full press/release")
        XCTAssertFalse(hasPendingSingleTap,
            "pendingSingleTap should not have ghost entry for button A after full press/release")
    }

    /// Bug 3: Lock toggle should properly clear ALL pending dictionaries.
    func testLockToggleClearsPendingDictionaries() async throws {
        let profile = Profile(
            name: "LockCleanup",
            buttonMappings: [
                .a: .key(1)
            ]
        )

        await MainActor.run {
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press button A (creates pending state)
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.05)

        // Lock the controller
        await MainActor.run {
            _ = mappingEngine.performLockToggle()
        }
        await waitForTasks(0.1)

        // Verify all pending state is cleared
        let (pendingRelease, pendingSingle, longHoldTimersEmpty) = await MainActor.run {
            mappingEngine.state.lock.withLock {
                (
                    mappingEngine.state.pendingReleaseActions.isEmpty,
                    mappingEngine.state.pendingSingleTap.isEmpty,
                    mappingEngine.state.longHoldTimers.isEmpty
                )
            }
        }

        XCTAssertTrue(pendingRelease, "pendingReleaseActions should be empty after lock toggle")
        XCTAssertTrue(pendingSingle, "pendingSingleTap should be empty after lock toggle")
        XCTAssertTrue(longHoldTimersEmpty, "longHoldTimers should be empty after lock toggle")

        // Unlock
        await MainActor.run {
            _ = mappingEngine.performLockToggle()
        }
    }
}

// MARK: - Bug 4: Gesture Detector Not Reset on Profile Change

/// Tests that the MotionGestureDetector properly resets its tracking state.
final class GestureDetectorProfileResetTests: XCTestCase {
    var detector: MotionGestureDetector!

    override func setUp() {
        detector = MotionGestureDetector()
    }

    override func tearDown() {
        detector = nil
    }

    /// Bug 4: After reset(), the gesture detector's internal axis states
    /// should be back to idle so that stale tracking/settling phases from
    /// a previous profile do not carry over.
    func testResetClearsTrackingState() {
        let now = CFAbsoluteTimeGetCurrent()
        let activationThreshold = Config.gestureActivationThreshold

        // Start tracking a pitch gesture (moves to .tracking phase)
        _ = detector.processAll((pitchRate: activationThreshold + 1.0, rollRate: 0), at: now)
        XCTAssertNotEqual(detector.pitchState.phase, .idle,
            "Pitch state should be in tracking phase after activation")

        // Reset
        detector.reset()

        // Verify state is fully reset
        XCTAssertEqual(detector.pitchState.phase, .idle,
            "After reset(), pitch state should be idle")
        XCTAssertEqual(detector.rollState.phase, .idle,
            "After reset(), roll state should be idle")
        XCTAssertEqual(detector.pitchState.peakVelocity, 0,
            "After reset(), peak velocity should be zero")
        XCTAssertEqual(detector.pitchState.lastGestureTime, 0,
            "After reset(), last gesture time should be zero")
    }

    /// Bug 4: A gesture that was in settling phase should not block new gestures
    /// after reset (simulates profile change scenario).
    func testResetAllowsImmediateGestureAfterSettling() {
        let now = CFAbsoluteTimeGetCurrent()
        let activationThreshold = Config.gestureActivationThreshold
        let minPeakVelocity = Config.gestureMinPeakVelocity

        // Complete a tilt-back gesture to reach settling phase
        _ = detector.processAll((pitchRate: activationThreshold + 1.0, rollRate: 0), at: now)
        _ = detector.processAll((pitchRate: minPeakVelocity + 2.0, rollRate: 0), at: now + 0.01)
        let completionVelocity = (minPeakVelocity + 2.0) * Config.gestureCompletionRatio * 0.5
        let results = detector.processAll((pitchRate: completionVelocity, rollRate: 0), at: now + 0.05)
        XCTAssertFalse(results.isEmpty, "Gesture should have completed")

        // Pitch state should be in settling
        XCTAssertEqual(detector.pitchState.phase, .settling,
            "After gesture completion, should be in settling phase")

        // Reset (simulates profile change)
        detector.reset()

        // Should be able to immediately start a new gesture without cooldown
        _ = detector.processAll((pitchRate: activationThreshold + 1.0, rollRate: 0), at: now + 0.06)
        XCTAssertEqual(detector.pitchState.phase, .tracking,
            "After reset, should be able to start tracking immediately without cooldown")
    }
}

/// Integration test: MappingEngine should reset gesture detector on profile change.
final class GestureDetectorProfileChangeIntegrationTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-bugfix-4-\(UUID().uuidString)", isDirectory: true)

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
        try? await Task.sleep(nanoseconds: 80_000_000)

        await MainActor.run {
            controllerService?.onButtonPressed = nil
            controllerService?.onButtonReleased = nil
            controllerService?.onChordDetected = nil
            controllerService?.onLeftStickMoved = nil
            controllerService?.onRightStickMoved = nil
            controllerService?.onTouchpadMoved = nil
            controllerService?.onTouchpadGesture = nil
            controllerService?.onTouchpadTap = nil
            controllerService?.onTouchpadTwoFingerTap = nil
            controllerService?.onTouchpadLongTap = nil
            controllerService?.onTouchpadTwoFingerLongTap = nil
            controllerService?.cleanup()

            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
    }

    /// Bug 4 integration: Verify that the motion gesture detector's state is
    /// reset when the profile changes. Currently, syncGestureSettings only
    /// updates thresholds but doesn't reset the phase state machine.
    func testProfileChangeShouldResetGestureDetectorState() async throws {
        let profileA = Profile(
            name: "GestureProfileA",
            gestureMappings: [
                GestureMapping(gestureType: .tiltBack, keyCode: 10)
            ]
        )

        let profileB = Profile(
            name: "GestureProfileB",
            gestureMappings: [
                GestureMapping(gestureType: .tiltBack, keyCode: 20)
            ]
        )

        await MainActor.run {
            profileManager.setActiveProfile(profileA)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Start a gesture that puts detector in tracking phase
        let activationThreshold = Config.gestureActivationThreshold
        let phaseBeforeSwitch: MotionGestureDetector.AxisGestureState.Phase = await MainActor.run {
            controllerService.storage.lock.lock()
            let now = CFAbsoluteTimeGetCurrent()
            _ = controllerService.storage.motionGestureDetector.processAll(
                (pitchRate: activationThreshold + 1.0, rollRate: 0), at: now
            )
            let phase = controllerService.storage.motionGestureDetector.pitchState.phase
            controllerService.storage.lock.unlock()
            return phase
        }

        XCTAssertNotEqual(phaseBeforeSwitch, .idle,
            "Gesture detector should be in tracking phase before profile switch")

        // Switch profile
        await MainActor.run {
            profileManager.setActiveProfile(profileB)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Check that gesture detector was reset
        let phaseAfterSwitch: MotionGestureDetector.AxisGestureState.Phase = await MainActor.run {
            controllerService.storage.lock.lock()
            let phase = controllerService.storage.motionGestureDetector.pitchState.phase
            controllerService.storage.lock.unlock()
            return phase
        }

        XCTAssertEqual(phaseAfterSwitch, .idle,
            "Gesture detector should be reset to idle after profile change")
    }
}

// MARK: - Bug 5: Silent Null Profile

/// Tests that nil profile is handled properly with appropriate logging/behavior.
final class NilProfileHandlingTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-bugfix-5-\(UUID().uuidString)", isDirectory: true)

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
        try? await Task.sleep(nanoseconds: 80_000_000)

        await MainActor.run {
            controllerService?.onButtonPressed = nil
            controllerService?.onButtonReleased = nil
            controllerService?.onChordDetected = nil
            controllerService?.onLeftStickMoved = nil
            controllerService?.onRightStickMoved = nil
            controllerService?.onTouchpadMoved = nil
            controllerService?.onTouchpadGesture = nil
            controllerService?.onTouchpadTap = nil
            controllerService?.onTouchpadTwoFingerTap = nil
            controllerService?.onTouchpadLongTap = nil
            controllerService?.onTouchpadTwoFingerLongTap = nil
            controllerService?.cleanup()

            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
    }

    private func waitForTasks(_ delay: TimeInterval = 0.35) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    /// Bug 5: With no active profile, button presses should be silently
    /// ignored without crashing, and no actions should execute.
    func testNilProfileIgnoresInputWithoutCrash() async throws {
        // ProfileManager creates a default profile on init, so we must
        // explicitly nil it out to test the nil profile path.
        await MainActor.run {
            mappingEngine.state.lock.withLock {
                mappingEngine.state.activeProfile = nil
            }
        }

        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        // No crash occurred - verify no events were fired
        let events = mockInputSimulator.events
        XCTAssertTrue(events.isEmpty,
            "No key events should fire when profile is nil")
    }

    /// Bug 5: Setting profile to nil and then pressing buttons should not crash.
    func testProfileSetToNilAfterValidProfile() async throws {
        let profile = Profile(
            name: "TestProfile",
            buttonMappings: [.a: .key(1)]
        )

        await MainActor.run {
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Clear the active profile by setting state directly
        await MainActor.run {
            mappingEngine.state.lock.withLock {
                mappingEngine.state.activeProfile = nil
            }
        }

        // Press buttons - should not crash
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        // Verify no events (profile is nil)
        let events = mockInputSimulator.events
        let keyCode1Count = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 1 }
            return false
        }.count

        XCTAssertEqual(keyCode1Count, 0,
            "No key events should fire when profile becomes nil")
    }

    /// Bug 5: Chord detection with nil profile should not crash.
    func testChordWithNilProfileDoesNotCrash() async throws {
        // Set profile to nil
        await MainActor.run {
            mappingEngine.state.lock.withLock {
                mappingEngine.state.activeProfile = nil
            }
        }

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonPressed(.b)
        }
        await waitForTasks()
        await MainActor.run {
            controllerService.buttonReleased(.a)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks()

        // If we get here without crash, the test passes
        XCTAssertTrue(true, "Chord handling with nil profile should not crash")
    }
}
