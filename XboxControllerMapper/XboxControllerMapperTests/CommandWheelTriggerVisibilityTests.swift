import XCTest
import CoreGraphics
@testable import ControllerKeys

/// Regression tests for the rule that the on-screen keyboard's command wheel
/// must NOT appear until the right stick crosses the deadzone, while the
/// standalone command wheel trigger must show its wheel immediately.
final class CommandWheelTriggerVisibilityTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-wheel-vis-\(UUID().uuidString)", isDirectory: true)

        await MainActor.run {
            controllerService = ControllerService(enableHardwareMonitoring: false)
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

            CommandWheelManager.shared.hide()
            OnScreenKeyboardManager.shared.hide()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            CommandWheelManager.shared.hide()
            OnScreenKeyboardManager.shared.hide()
            mappingEngine?.disable()
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await MainActor.run {
            controllerService?.cleanup()
            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
    }

    private func waitForTasks(_ delay: TimeInterval = 0.15) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    /// Holding the on-screen keyboard button must not reveal the command wheel
    /// immediately. The wheel is opt-in: it only appears after the right stick
    /// crosses the deadzone. Regression guard for an earlier eager `show()` call.
    func testOnScreenKeyboardHold_DoesNotImmediatelyShowCommandWheel() async throws {
        await MainActor.run {
            guard var profile = profileManager.activeProfile else {
                XCTFail("ProfileManager should bootstrap a default profile")
                return
            }
            profile.onScreenKeyboardSettings = OnScreenKeyboardSettings(
                appBarItems: [AppBarItem(bundleIdentifier: "com.apple.finder", displayName: "Finder")]
            )
            profileManager.updateProfile(profile)
            mappingEngine.handleOnScreenKeyboardPressed(.menu, holdMode: true)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(OnScreenKeyboardManager.shared.isVisible,
                "OSK should be visible while held")
            XCTAssertFalse(CommandWheelManager.shared.isVisible,
                "Command wheel must NOT show until the right stick crosses the deadzone")
            XCTAssertEqual(CommandWheelManager.shared.items.count, 1,
                "Wheel items should be prepared so it can auto-show on stick movement")
        }

        await MainActor.run {
            CommandWheelManager.shared.updateSelection(stickX: 0.6, stickY: 0)
            XCTAssertTrue(CommandWheelManager.shared.isVisible,
                "Wheel should auto-show once the right stick crosses the deadzone")
        }

        await MainActor.run {
            mappingEngine.handleOnScreenKeyboardReleased(.menu)
        }
        await waitForTasks(0.1)
    }

    /// The standalone command wheel trigger must show the wheel immediately,
    /// regardless of joystick state — the user explicitly asked for the wheel,
    /// so there is nothing else to gate it on.
    func testStandaloneCommandWheelTrigger_ShowsWheelImmediately() async throws {
        await MainActor.run {
            guard var profile = profileManager.activeProfile else {
                XCTFail("ProfileManager should bootstrap a default profile")
                return
            }
            profile.commandWheelActions = [CommandWheelAction(displayName: "Test", keyCode: 0x00)]
            profileManager.updateProfile(profile)
            mappingEngine.handleCommandWheelPressed(.menu, holdMode: true)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(CommandWheelManager.shared.isVisible,
                "Standalone command wheel should appear immediately on trigger, no joystick required")
            XCTAssertEqual(CommandWheelManager.shared.items.count, 1,
                "Wheel should be populated with the configured action")
        }

        await MainActor.run {
            mappingEngine.handleCommandWheelReleased(.menu)
        }
        await waitForTasks(0.1)
    }
}
