import XCTest
@testable import ControllerKeys

@MainActor
final class UsageStatsServiceTests: XCTestCase {
    private var testDirectory: URL!
    private var statsFileURL: URL!
    private var backgroundQueue: DispatchQueue!
    private let timing = UsageStatsService.Timing(saveDelaySeconds: 0.05, publishDelaySeconds: 0.02)

    override func setUp() async throws {
        try await super.setUp()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-usage-stats-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        statsFileURL = testDirectory.appendingPathComponent("stats.json")
        backgroundQueue = DispatchQueue(label: "UsageStatsServiceTests.queue")
    }

    override func tearDown() async throws {
        if let testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        testDirectory = nil
        statsFileURL = nil
        backgroundQueue = nil
        try await super.tearDown()
    }

    func testRapidDistanceUpdatesPublishAsynchronouslyAndCoalesce() async {
        let service = makeService()

        for _ in 0..<200 {
            service.recordJoystickMouseDistance(dx: 3, dy: 4) // Distance = 5
        }

        // Regression guard: avoid synchronous @Published updates on hot path.
        XCTAssertEqual(service.stats.joystickMousePixels, 0, accuracy: 0.0001)

        await waitForAsyncWork(0.08)

        XCTAssertEqual(service.stats.joystickMousePixels, 1000, accuracy: 0.0001)
    }

    func testZeroDistanceInputsAreIgnored() async {
        let service = makeService()

        service.recordJoystickMouseDistance(dx: 0, dy: 0)
        service.recordTouchpadMouseDistance(dx: 0, dy: 0)
        service.recordScrollDistance(dx: 0, dy: 0)

        await waitForAsyncWork(0.05)

        XCTAssertEqual(service.stats.joystickMousePixels, 0, accuracy: 0.0001)
        XCTAssertEqual(service.stats.touchpadMousePixels, 0, accuracy: 0.0001)
        XCTAssertEqual(service.stats.scrollPixels, 0, accuracy: 0.0001)
    }

    func testCountersAndDistanceRecording() async {
        let service = makeService()

        service.record(button: .a, type: .singlePress)
        service.recordChord(buttons: [.b, .x], type: .chord)
        service.recordKeyPress()
        service.recordMouseClick()
        service.recordMacro(stepCount: 4)
        service.recordWebhook()
        service.recordAppLaunch()
        service.recordTextSnippet()
        service.recordTerminalCommand()
        service.recordLinkOpened()
        service.recordJoystickMouseDistance(dx: 3, dy: 4) // 5
        service.recordTouchpadMouseDistance(dx: 0, dy: 6) // 6
        service.recordScrollDistance(dx: 8, dy: 15) // 17

        await waitForAsyncWork(0.08)

        XCTAssertEqual(service.stats.buttonCounts[ControllerButton.a.rawValue], 1)
        XCTAssertEqual(service.stats.buttonCounts[ControllerButton.b.rawValue], 1)
        XCTAssertEqual(service.stats.buttonCounts[ControllerButton.x.rawValue], 1)
        XCTAssertEqual(service.stats.actionTypeCounts[InputEventType.singlePress.rawValue], 1)
        XCTAssertEqual(service.stats.actionTypeCounts[InputEventType.chord.rawValue], 1)
        XCTAssertEqual(service.stats.keyPresses, 1)
        XCTAssertEqual(service.stats.mouseClicks, 1)
        XCTAssertEqual(service.stats.macrosExecuted, 1)
        XCTAssertEqual(service.stats.macroStepsAutomated, 4)
        XCTAssertEqual(service.stats.webhooksFired, 1)
        XCTAssertEqual(service.stats.appsLaunched, 1)
        XCTAssertEqual(service.stats.textSnippetsRun, 1)
        XCTAssertEqual(service.stats.terminalCommandsRun, 1)
        XCTAssertEqual(service.stats.linksOpened, 1)
        XCTAssertEqual(service.stats.joystickMousePixels, 5, accuracy: 0.0001)
        XCTAssertEqual(service.stats.touchpadMousePixels, 6, accuracy: 0.0001)
        XCTAssertEqual(service.stats.scrollPixels, 17, accuracy: 0.0001)
    }

    func testEndSessionPersistsStatsForNewInstance() async {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(120)
        var callCount = 0
        let nowProvider: () -> Date = {
            defer { callCount += 1 }
            return callCount == 0 ? start : end
        }

        let service = makeService(now: nowProvider)
        service.recordKeyPress()
        service.endSession()

        await waitForAsyncWork(0.05)

        let reloaded = UsageStatsService(
            statsFileURL: statsFileURL,
            timing: timing,
            backgroundQueue: backgroundQueue
        )

        XCTAssertEqual(reloaded.stats.keyPresses, 1)
        XCTAssertEqual(reloaded.stats.totalSessionSeconds, 120, accuracy: 0.0001)
    }

    private func makeService(now: @escaping () -> Date = Date.init) -> UsageStatsService {
        UsageStatsService(
            statsFileURL: statsFileURL,
            timing: timing,
            backgroundQueue: backgroundQueue,
            now: now
        )
    }

    private func waitForAsyncWork(_ delay: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
