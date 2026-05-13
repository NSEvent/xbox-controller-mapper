import XCTest
import CoreGraphics
@testable import ControllerKeys

final class JoystickCustomDirectionMappingTests: XCTestCase {
    private var controllerService: ControllerService!
    private var profileManager: ProfileManager!
    private var appMonitor: AppMonitor!
    private var mockInputSimulator: MockInputSimulator!
    private var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-custom-joystick-\(UUID().uuidString)", isDirectory: true)

        await MainActor.run {
            controllerService = ControllerService(enableHardwareMonitoring: false)
            controllerService.chordWindow = 0.03
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
        await waitForTasks(0.1)

        await MainActor.run {
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
    }

    func testResolver_fourWayDiagonalChoosesDominantAxis() {
        let directions = JoystickDirectionResolver.activeDirections(
            stick: CGPoint(x: 0.45, y: 0.9),
            deadzone: 0.1,
            horizontalSliceSize: 13.0 / 15.0,
            verticalSliceSize: 13.0 / 15.0,
            invertY: false
        )

        XCTAssertEqual(directions, [.up], "4-way custom mode should pick one dominant cardinal direction")
    }

    func testResolver_betweenSliceGapSuppressesDiagonalInput() {
        let directions = JoystickDirectionResolver.activeDirections(
            stick: CGPoint(x: 0.8, y: 0.8),
            deadzone: 0.1,
            horizontalSliceSize: 0.6,
            verticalSliceSize: 0.6,
            invertY: false
        )

        XCTAssertEqual(directions, [], "Between-slice deadzones should leave diagonal input neutral in 4-way custom mode")
    }

    func testResolver_smallHorizontalAndLargeVerticalSlicesCanSelectUpAtDiagonalEdge() {
        let directions = JoystickDirectionResolver.activeDirections(
            stick: CGPoint(x: 0.8, y: 0.8),
            deadzone: 0.1,
            horizontalSliceSize: 0.2,
            verticalSliceSize: 1.0,
            invertY: false
        )

        XCTAssertEqual(directions, [.up], "Vertical slices should be able to be larger than horizontal slices")
    }

    func testResolver_largeHorizontalAndSmallVerticalSlicesCanSelectRightAtDiagonalEdge() {
        let directions = JoystickDirectionResolver.activeDirections(
            stick: CGPoint(x: 0.8, y: 0.8),
            deadzone: 0.1,
            horizontalSliceSize: 1.0,
            verticalSliceSize: 0.2,
            invertY: false
        )

        XCTAssertEqual(directions, [.right], "Horizontal slices should be able to be larger than vertical slices")
    }

    func testResolver_wideSliceSizesStillAllowClearCardinalInput() {
        let directions = JoystickDirectionResolver.activeDirections(
            stick: CGPoint(x: 0.1, y: 0.9),
            deadzone: 0.1,
            horizontalSliceSize: 0.2,
            verticalSliceSize: 0.2,
            invertY: false
        )

        XCTAssertEqual(directions, [.up], "Small slices should still allow clear cardinal input near the stick axis")
    }

    func testAxisResolverAllowsIndependentWasdStyleDirections() {
        let directions = JoystickDirectionResolver.activeAxisDirections(
            stick: CGPoint(x: 0.9, y: 0.9),
            deadzone: 0.1,
            invertY: false
        )

        XCTAssertEqual(directions, [.up, .right], "WASD/arrows should expose one direction per active axis")
    }

    func testAxisResolverHonorsInvertY() {
        let directions = JoystickDirectionResolver.activeAxisDirections(
            stick: CGPoint(x: 0, y: 0.9),
            deadzone: 0.1,
            invertY: true
        )

        XCTAssertEqual(directions, [.down], "Invert Y should flip the virtual direction just like the emitted key")
    }

    func testChordSequenceDirectionButtonsAreAvailableOnlyForCustomWasdAndArrows() {
        for mode in [StickMode.custom, .wasdKeys, .arrowKeys] {
            var settings = JoystickSettings.default
            settings.leftStickMode = mode
            settings.rightStickMode = mode

            XCTAssertEqual(
                settings.chordSequenceJoystickDirectionButtons(side: .left),
                [.leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight],
                "\(mode.displayName) left stick should be selectable in chord/sequence editors"
            )
            XCTAssertEqual(
                settings.chordSequenceJoystickDirectionButtons(side: .right),
                [.rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight],
                "\(mode.displayName) right stick should be selectable in chord/sequence editors"
            )
        }

        for mode in [StickMode.none, .mouse, .scroll] {
            var settings = JoystickSettings.default
            settings.leftStickMode = mode
            settings.rightStickMode = mode

            XCTAssertTrue(settings.chordSequenceJoystickDirectionButtons(side: .left).isEmpty)
            XCTAssertTrue(settings.chordSequenceJoystickDirectionButtons(side: .right).isEmpty)
        }
    }

    func testCustomLeftStickDirectionStartsAndStopsHoldMapping() async throws {
        await MainActor.run {
            var profile = Profile(name: "Custom Left Stick", buttonMappings: [
                .leftStickUp: holdMapping(10)
            ])
            profile.joystickSettings.leftStickMode = .custom
            profile.joystickSettings.mouseDeadzone = 0.1
            installActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.12)

        await MainActor.run {
            controllerService.setLeftStickForTesting(CGPoint(x: 0, y: 0.9))
        }
        await waitForTasks(0.2)

        XCTAssertEqual(startHoldCount(for: 10), 1, "Entering Left Stick Up should press the mapped virtual button once")
        let upIsActive = await isActiveButton(.leftStickUp)
        XCTAssertTrue(upIsActive, "Virtual direction should appear active for UI highlighting")

        await MainActor.run {
            controllerService.setLeftStickForTesting(.zero)
        }
        await waitForTasks(0.2)

        XCTAssertEqual(stopHoldCount(for: 10), 1, "Returning to center should release the mapped virtual button")
        let upCleared = await isActiveButton(.leftStickUp)
        XCTAssertFalse(upCleared, "Virtual direction should clear when centered")
    }

    func testCustomLeftStickDirectionCanCompleteChord() async throws {
        await MainActor.run {
            controllerService.chordWindow = 0.2
            var profile = Profile(
                name: "Custom Direction Chord",
                chordMappings: [
                    ChordMapping(buttons: [.leftStickUp, .a], keyCode: 42)
                ]
            )
            profile.joystickSettings.leftStickMode = .custom
            profile.joystickSettings.mouseDeadzone = 0.1
            installActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.12)

        await MainActor.run {
            controllerService.setLeftStickForTesting(CGPoint(x: 0, y: 0.9))
        }
        await waitForTasks(0.05)
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.3)

        XCTAssertEqual(pressKeyCount(for: 42), 1, "Custom stick direction should participate in chords")
    }

    func testWasdLeftStickDirectionCanCompleteChordWhileStillPressingW() async throws {
        await MainActor.run {
            controllerService.chordWindow = 0.2
            var profile = Profile(
                name: "WASD Direction Chord",
                chordMappings: [
                    ChordMapping(buttons: [.leftStickUp, .a], keyCode: 43)
                ]
            )
            profile.joystickSettings.leftStickMode = .wasdKeys
            profile.joystickSettings.mouseDeadzone = 0.1
            installActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.12)

        await MainActor.run {
            controllerService.setLeftStickForTesting(CGPoint(x: 0, y: 0.9))
        }
        await waitForTasks(0.05)

        let upIsActive = await isActiveButton(.leftStickUp)
        XCTAssertTrue(upIsActive, "WASD mode should expose the left-stick up virtual button")
        XCTAssertGreaterThanOrEqual(keyDownCount(for: 13), 1, "WASD mode should keep its existing W key behavior")

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.3)

        XCTAssertEqual(pressKeyCount(for: 43), 1, "WASD stick direction should participate in chords")
    }

    func testArrowRightStickDirectionCanCompleteSequenceWhileStillPressingArrowKey() async throws {
        await MainActor.run {
            var profile = Profile(
                name: "Arrow Direction Sequence",
                sequenceMappings: [
                    SequenceMapping(steps: [.rightStickLeft, .b], keyCode: 44)
                ]
            )
            profile.joystickSettings.rightStickMode = .arrowKeys
            profile.joystickSettings.scrollDeadzone = 0.1
            installActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.12)

        await MainActor.run {
            controllerService.setRightStickForTesting(CGPoint(x: -0.9, y: 0))
        }
        await waitForTasks(0.14)

        let leftIsActive = await isActiveButton(.rightStickLeft)
        XCTAssertTrue(leftIsActive, "Arrow mode should expose the right-stick left virtual button")
        XCTAssertGreaterThanOrEqual(keyDownCount(for: 123), 1, "Arrow mode should keep its existing Left Arrow behavior")

        await MainActor.run {
            controllerService.setRightStickForTesting(.zero)
        }
        await waitForTasks(0.12)
        await MainActor.run {
            controllerService.buttonPressed(.b)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks(0.25)

        XCTAssertEqual(pressKeyCount(for: 44), 1, "Arrow stick direction should participate in sequences")
    }

    func testMouseModeDoesNotEmitJoystickDirectionButtonsForChords() async throws {
        await MainActor.run {
            var profile = Profile(
                name: "Mouse Direction Ignored",
                chordMappings: [
                    ChordMapping(buttons: [.leftStickUp, .a], keyCode: 45)
                ]
            )
            profile.joystickSettings.leftStickMode = .mouse
            profile.joystickSettings.mouseDeadzone = 0.1
            installActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.12)

        await MainActor.run {
            controllerService.setLeftStickForTesting(CGPoint(x: 0, y: 0.9))
        }
        await waitForTasks(0.14)
        let upIsActive = await isActiveButton(.leftStickUp)
        XCTAssertFalse(upIsActive, "Mouse mode should not expose joystick direction virtual buttons")

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.25)

        XCTAssertEqual(pressKeyCount(for: 45), 0, "Mouse stick movement should not complete joystick direction chords")
    }

    func testCustomSliceSizesSuppressBetweenSliceInput() async throws {
        await MainActor.run {
            var profile = Profile(name: "Custom Gap", buttonMappings: [
                .leftStickUp: holdMapping(10),
                .leftStickRight: holdMapping(11)
            ])
            profile.joystickSettings.leftStickMode = .custom
            profile.joystickSettings.leftStickCustomHorizontalSliceSize = 0.6
            profile.joystickSettings.leftStickCustomVerticalSliceSize = 0.6
            profile.joystickSettings.mouseDeadzone = 0.1
            installActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.12)

        await MainActor.run {
            controllerService.setLeftStickForTesting(CGPoint(x: 0.9, y: 0.9))
        }
        await waitForTasks(0.2)

        XCTAssertEqual(startHoldCount(for: 10), 0, "Diagonal input should not leak into Up when the gap is wide")
        XCTAssertEqual(startHoldCount(for: 11), 0, "Diagonal input should not leak into Right when the gap is wide")
        let upIsActive = await isActiveButton(.leftStickUp)
        let rightIsActive = await isActiveButton(.leftStickRight)
        XCTAssertFalse(upIsActive)
        XCTAssertFalse(rightIsActive)
    }

    func testCustomVerticalSliceCanBeLargerThanHorizontalSlice() async throws {
        await MainActor.run {
            var profile = Profile(name: "Custom Vertical Slice", buttonMappings: [
                .leftStickUp: holdMapping(10),
                .leftStickRight: holdMapping(11)
            ])
            profile.joystickSettings.leftStickMode = .custom
            profile.joystickSettings.leftStickCustomHorizontalSliceSize = 0.2
            profile.joystickSettings.leftStickCustomVerticalSliceSize = 1.0
            profile.joystickSettings.mouseDeadzone = 0.1
            installActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.12)

        await MainActor.run {
            controllerService.setLeftStickForTesting(CGPoint(x: 0.9, y: 0.9))
        }
        await waitForTasks(0.2)

        XCTAssertEqual(startHoldCount(for: 10), 1, "A larger vertical slice should capture the diagonal edge as Up")
        XCTAssertEqual(startHoldCount(for: 11), 0, "A small horizontal slice should not leak into Right")
        let upIsActive = await isActiveButton(.leftStickUp)
        let rightIsActive = await isActiveButton(.leftStickRight)
        XCTAssertTrue(upIsActive)
        XCTAssertFalse(rightIsActive)
    }

    func testCustomDirectionTransitionsReleaseOldDirectionBeforePressingNewOne() async throws {
        await MainActor.run {
            var profile = Profile(name: "Custom Transition", buttonMappings: [
                .leftStickUp: holdMapping(10),
                .leftStickRight: holdMapping(11)
            ])
            profile.joystickSettings.leftStickMode = .custom
            profile.joystickSettings.mouseDeadzone = 0.1
            installActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.12)

        await MainActor.run {
            controllerService.setLeftStickForTesting(CGPoint(x: 0, y: 0.9))
        }
        await waitForTasks(0.18)
        await MainActor.run {
            controllerService.setLeftStickForTesting(CGPoint(x: 0.9, y: 0))
        }
        await waitForTasks(0.22)

        let events = mockInputSimulator.events
        let upStopIndex = firstStopHoldIndex(for: 10, in: events)
        let rightStartIndex = firstStartHoldIndex(for: 11, in: events)

        XCTAssertNotNil(upStopIndex, "Leaving Up should stop the old hold mapping")
        XCTAssertNotNil(rightStartIndex, "Entering Right should start the new hold mapping")
        XCTAssertLessThan(upStopIndex!, rightStartIndex!, "Old direction must release before the new direction presses")
        let upIsStillActive = await isActiveButton(.leftStickUp)
        let rightIsActive = await isActiveButton(.leftStickRight)
        XCTAssertFalse(upIsStillActive)
        XCTAssertTrue(rightIsActive)
    }

    func testCustomDirectionMappingUsesActiveLayerOverride() async throws {
        await MainActor.run {
            let layer = Layer(
                name: "Layer",
                activatorButton: .leftBumper,
                buttonMappings: [.leftStickUp: holdMapping(21)]
            )
            var profile = Profile(
                name: "Layer Override",
                buttonMappings: [.leftStickUp: holdMapping(20)],
                layers: [layer]
            )
            profile.joystickSettings.leftStickMode = .custom
            profile.joystickSettings.mouseDeadzone = 0.1
            installActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.12)

        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.12)
        await MainActor.run {
            controllerService.setLeftStickForTesting(CGPoint(x: 0, y: 0.9))
        }
        await waitForTasks(0.2)

        XCTAssertEqual(startHoldCount(for: 21), 1, "Active layer should override the base custom direction mapping")
        XCTAssertEqual(startHoldCount(for: 20), 0, "Base custom direction mapping should not fire while layer override exists")
    }

    func testJoystickDirectionCanActAsLayerActivator() async throws {
        await MainActor.run {
            let layer = Layer(
                name: "Stick Layer",
                activatorButton: .leftStickUp,
                buttonMappings: [.a: .key(30)]
            )
            var profile = Profile(
                name: "Direction Activator",
                buttonMappings: [.a: .key(31)],
                layers: [layer]
            )
            profile.joystickSettings.leftStickMode = .custom
            profile.joystickSettings.mouseDeadzone = 0.1
            installActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.12)

        await MainActor.run {
            controllerService.setLeftStickForTesting(CGPoint(x: 0, y: 0.9))
        }
        await waitForTasks(0.18)
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.2)

        XCTAssertEqual(pressKeyCount(for: 30), 1, "Holding a custom stick direction should activate its layer")
        XCTAssertEqual(pressKeyCount(for: 31), 0, "Base mapping should not fire while the direction-activated layer is active")

        await MainActor.run {
            mockInputSimulator.clearEvents()
            controllerService.setLeftStickForTesting(.zero)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.2)

        XCTAssertEqual(pressKeyCount(for: 31), 1, "Centering the stick should deactivate the direction-activated layer")
    }

    private func waitForTasks(_ delay: TimeInterval = 0.25) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    @MainActor
    private func installActiveProfile(_ profile: Profile) {
        profileManager.profiles = [profile]
        profileManager.setActiveProfile(profile)
    }

    private func isActiveButton(_ button: ControllerButton) async -> Bool {
        await MainActor.run {
            controllerService.activeButtons.contains(button)
        }
    }

    private func holdMapping(_ keyCode: CGKeyCode) -> KeyMapping {
        KeyMapping(keyCode: keyCode, isHoldModifier: true)
    }

    private func startHoldCount(for keyCode: CGKeyCode) -> Int {
        mockInputSimulator.events.filter {
            if case .startHoldMapping(let mapping) = $0 {
                return mapping.keyCode == keyCode
            }
            return false
        }.count
    }

    private func stopHoldCount(for keyCode: CGKeyCode) -> Int {
        mockInputSimulator.events.filter {
            if case .stopHoldMapping(let mapping) = $0 {
                return mapping.keyCode == keyCode
            }
            return false
        }.count
    }

    private func pressKeyCount(for keyCode: CGKeyCode) -> Int {
        mockInputSimulator.events.filter {
            if case .pressKey(let code, _) = $0 {
                return code == keyCode
            }
            return false
        }.count
    }

    private func keyDownCount(for keyCode: CGKeyCode) -> Int {
        mockInputSimulator.events.filter {
            if case .keyDown(let code) = $0 {
                return code == keyCode
            }
            return false
        }.count
    }

    private func firstStartHoldIndex(for keyCode: CGKeyCode, in events: [MockInputSimulator.Event]) -> Int? {
        events.firstIndex {
            if case .startHoldMapping(let mapping) = $0 {
                return mapping.keyCode == keyCode
            }
            return false
        }
    }

    private func firstStopHoldIndex(for keyCode: CGKeyCode, in events: [MockInputSimulator.Event]) -> Int? {
        events.firstIndex {
            if case .stopHoldMapping(let mapping) = $0 {
                return mapping.keyCode == keyCode
            }
            return false
        }
    }
}
