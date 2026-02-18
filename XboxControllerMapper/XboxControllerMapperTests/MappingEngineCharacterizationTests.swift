import XCTest
import CoreGraphics
@testable import ControllerKeys

final class MappingEngineCharacterizationTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-characterization-\(UUID().uuidString)", isDirectory: true)

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

    func testCharacterization_ChordTakesPrecedenceOverIndividualButtons() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "ChordCharacterization",
                buttonMappings: [
                    .a: .key(1),
                    .b: .key(2)
                ],
                chordMappings: [
                    ChordMapping(buttons: [.a, .b], keyCode: 3)
                ]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonPressed(.b)
        }
        await waitForTasks()
        await MainActor.run {
            controllerService.buttonReleased(.a)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks(0.2)

        let events = mockInputSimulator.events
        let chordCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 3 }
            return false
        }.count
        let aCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 1 }
            return false
        }.count
        let bCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 2 }
            return false
        }.count

        XCTAssertEqual(chordCount, 1, "Chord mapping should fire exactly once")
        XCTAssertEqual(aCount, 0, "Individual A mapping should not fire when chord matches")
        XCTAssertEqual(bCount, 0, "Individual B mapping should not fire when chord matches")
    }

    func testCharacterization_DoubleTapCancelsSingleTapFallback() async throws {
        await MainActor.run {
            let mapping = KeyMapping(
                keyCode: 1,
                doubleTapMapping: DoubleTapMapping(keyCode: 2, threshold: 0.2)
            )
            let profile = Profile(name: "DoubleTapCharacterization", buttonMappings: [.a: mapping])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.04)
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.35)

        let events = mockInputSimulator.events
        let singleTapCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 1 }
            return false
        }.count
        let doubleTapCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 2 }
            return false
        }.count

        XCTAssertEqual(doubleTapCount, 1, "Double-tap mapping should execute once")
        XCTAssertEqual(singleTapCount, 0, "Single-tap fallback should be cancelled after double-tap")
    }

    func testCharacterization_LongHoldSuppressesRegularTapAction() async throws {
        await MainActor.run {
            let mapping = KeyMapping(
                keyCode: 1,
                longHoldMapping: LongHoldMapping(keyCode: 4, threshold: 0.1)
            )
            let profile = Profile(name: "LongHoldCharacterization", buttonMappings: [.a: mapping])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.3)

        let events = mockInputSimulator.events
        let tapCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 1 }
            return false
        }.count
        let longHoldCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 4 }
            return false
        }.count

        XCTAssertEqual(longHoldCount, 1, "Long-hold action should execute once when threshold is exceeded")
        XCTAssertEqual(tapCount, 0, "Regular tap action should not fire after long-hold trigger")
    }

    func testCharacterization_HoldModifierWrapsButtonActionOrdering() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "ModifierOrderCharacterization",
                buttonMappings: [
                    .leftBumper: .holdModifier(.command),
                    .a: .key(9)
                ]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks(0.2)

        let events = mockInputSimulator.events

        let holdIndex = events.firstIndex {
            if case .holdModifier(let flags) = $0 { return flags.contains(.maskCommand) }
            return false
        }
        let pressIndex = events.firstIndex {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 9 }
            return false
        }
        let releaseIndex = events.lastIndex {
            if case .releaseModifier(let flags) = $0 { return flags.contains(.maskCommand) }
            return false
        }

        XCTAssertNotNil(holdIndex, "Expected command modifier hold event")
        XCTAssertNotNil(pressIndex, "Expected mapped key press event")
        XCTAssertNotNil(releaseIndex, "Expected command modifier release event")
        if let holdIndex, let pressIndex, let releaseIndex {
            XCTAssertLessThan(holdIndex, pressIndex, "Modifier must be held before mapped key action")
            XCTAssertGreaterThan(releaseIndex, pressIndex, "Modifier release should happen after mapped key action")
        }
    }
}
