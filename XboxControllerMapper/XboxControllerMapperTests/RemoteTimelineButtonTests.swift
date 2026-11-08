import XCTest
@testable import ControllerKeys

/// A Xiaomi key that runs its Apple TV remote counterpart's binding (TV runs
/// the saved `.xbox` mapping) must still show as the Xiaomi key in the timeline.
@MainActor
final class RemoteTimelineButtonTests: MappingEngineTestCase {
	private var logService: InputLogService!

	override func setUp() async throws {
		try await super.setUp()
		logService = InputLogService()
		mappingEngine.disable()
		mappingEngine = MappingEngine(
			controllerService: controllerService, profileManager: profileManager, appMonitor: appMonitor,
			inputSimulator: mockInputSimulator, inputLogService: logService, midiService: mockMIDIService
		)
		mappingEngine.enable()
	}

	private func tap(_ button: ControllerButton) async -> [ControllerButton]? {
		controllerService.handleButton(button, pressed: true)
		controllerService.handleButton(button, pressed: false)
		_ = await waitForCondition { [self] in !logService.entries.isEmpty }
		defer { logService.entries.removeAll() }
		return logService.entries.first?.buttons
	}

	func testXiaomiTVUsingSharedXboxBindingLogsAsTV() async {
		profileManager.setActiveProfile(Profile(name: "Shared TV", buttonMappings: [.xbox: .key(40)]))
		await waitForTasks(0.05)
		let logged = await tap(.xiaomiTV)
		XCTAssertTrue(mockInputSimulator.events.contains(.pressKey(40, [])), "TV should run the saved TV binding")
		XCTAssertEqual(logged, [.xiaomiTV])
	}

	func testRealXboxButtonStillLogsAsXboxAfterXiaomiTV() async {
		profileManager.setActiveProfile(Profile(name: "Shared TV", buttonMappings: [.xbox: .key(40)]))
		await waitForTasks(0.05)
		_ = await tap(.xiaomiTV)
		let logged = await tap(.xbox)
		XCTAssertEqual(logged, [.xbox])
	}
}
