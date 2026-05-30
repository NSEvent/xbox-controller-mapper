import XCTest
@testable import ControllerKeys

@MainActor
final class SteamGyroAimingPipelineTests: XCTestCase {
	private var controllerService: ControllerService!
	private var profileManager: ProfileManager!
	private var appMonitor: AppMonitor!
	private var mockInputSimulator: MockInputSimulator!
	private var mappingEngine: MappingEngine!
	private var testConfigDirectory: URL!

	override func setUp() async throws {
		testConfigDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("controllerkeys-steam-gyro-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(
			at: testConfigDirectory,
			withIntermediateDirectories: true
		)

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
	}

	override func tearDown() async throws {
		mappingEngine?.disable()
		controllerService?.cleanup()
		mappingEngine = nil
		controllerService = nil
		profileManager = nil
		appMonitor = nil
		mockInputSimulator = nil
		testConfigDirectory = nil
	}

	func testSteamGyroAimingDoesNotApplyGenericRollBoost() {
		let settings = lowLatencyGyroSettings()

		processGyroTick(pitch: 0, roll: 1, settings: settings, now: 100, isSteamController: true)
		let steamMove = lastMouseMove()

		mockInputSimulator.clearEvents()
		processGyroTick(pitch: 0, roll: 1, settings: settings, now: 100, isSteamController: false)
		let genericMove = lastMouseMove()

		XCTAssertEqual(steamMove?.dx ?? 0, -1.0, accuracy: 0.001)
		XCTAssertEqual(genericMove?.dx ?? 0, -Config.gyroAimingRollBoost, accuracy: 0.001)
	}

	func testSteamGyroAimingFollowsDirectionReversalWithoutFilterLag() {
		let settings = lowLatencyGyroSettings()

		processGyroTick(pitch: 0, roll: 1, settings: settings, now: 100, isSteamController: true)
		mockInputSimulator.clearEvents()

		processGyroTick(
			pitch: 0,
			roll: -1,
			settings: settings,
			now: 100 + Config.joystickPollInterval,
			isSteamController: true
		)

		XCTAssertGreaterThan(lastMouseMove()?.dx ?? 0, 0)
	}

	private func lowLatencyGyroSettings() -> JoystickSettings {
		var settings = JoystickSettings()
		settings.gyroAimingEnabled = true
		settings.gyroAimingSensitivity = 0
		settings.gyroAimingDeadzone = 0
		return settings
	}

	private func processGyroTick(
		pitch: Double,
		roll: Double,
		settings: JoystickSettings,
		now: CFAbsoluteTime,
		isSteamController: Bool
	) {
		controllerService.storage.lock.withLock {
			controllerService.storage.motionPitchAccum = pitch
			controllerService.storage.motionRollAccum = roll
			controllerService.storage.motionSampleCount = 1
		}

		mappingEngine.state.lock.lock()
		mappingEngine.processGyroAiming(
			settings: settings,
			now: now,
			isFocusActive: true,
			hasMotion: true,
			isSteamController: isSteamController
		)
		mappingEngine.state.lock.unlock()
	}

	private func lastMouseMove() -> (dx: Double, dy: Double)? {
		mockInputSimulator.events.compactMap { event -> (Double, Double)? in
			guard case let .moveMouse(dx, dy) = event else { return nil }
			return (dx: Double(dx), dy: Double(dy))
		}.last
	}
}
