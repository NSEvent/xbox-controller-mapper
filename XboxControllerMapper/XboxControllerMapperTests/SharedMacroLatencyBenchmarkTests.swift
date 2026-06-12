import XCTest
import CoreGraphics
import TriggerKitCore
import TriggerKitLibrary
@testable import ControllerKeys

/// Quantifies the latency added by the TriggerKit macro execution path and
/// the shared macro library wiring. These run on the button-dispatch
/// inputQueue in production, so the budgets below are deliberately tight
/// relative to the ~50ms key-press duration but loose enough not to flake
/// on CI hardware. Medians are logged for profiling reference.
@MainActor
final class SharedMacroLatencyBenchmarkTests: XCTestCase {

    private var store: AutomationMacroStore!
    private var storeDirectory: URL!
    private var profileManager: ProfileManager!
    private var testConfigDirectory: URL!
    private var mockInputSimulator: MockInputSimulator!
    private var factory: ActionCommandFactory!

    override func setUp() async throws {
        try await super.setUp()
        storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("triggerkit-bench-\(UUID().uuidString)", isDirectory: true)
        store = AutomationMacroStore(
            fileURL: storeDirectory.appendingPathComponent("macros.json"),
            notificationCenter: NotificationCenter(),
            distributedNotificationCenter: nil
        )
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-bench-\(UUID().uuidString)", isDirectory: true)
        profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory, sharedMacroStore: store)
        mockInputSimulator = MockInputSimulator()
        let systemCommandExecutor = SystemCommandExecutor(profileManager: profileManager)
        factory = ActionCommandFactory(
            inputSimulator: mockInputSimulator,
            inputQueue: DispatchQueue(label: "bench.input"),
            macroExecutor: MacroExecutor(
                inputSimulator: mockInputSimulator,
                systemCommandExecutor: systemCommandExecutor
            ),
            systemCommandExecutor: systemCommandExecutor,
            scriptEngine: nil,
            sharedMacroStore: store
        )
    }

    override func tearDown() async throws {
        factory = nil
        mockInputSimulator = nil
        profileManager = nil
        store = nil
        if let testConfigDirectory { try? FileManager.default.removeItem(at: testConfigDirectory) }
        if let storeDirectory { try? FileManager.default.removeItem(at: storeDirectory) }
        try await super.tearDown()
    }

    private func medianNanoseconds(iterations: Int = 200, _ body: () -> Void) -> Double {
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start))
        }
        return samples.sorted()[samples.count / 2]
    }

    private func makeMacro(steps: Int) -> Macro {
        Macro(name: "Bench", steps: (0..<steps).map { i in
            .press(KeyMapping(keyCode: CGKeyCode(i % 40), modifiers: .command))
        })
    }

    // MARK: - Conversion cost (runs on inputQueue per macro fire)

    func testBridgeConversionCostIsMicroseconds() {
        let small = makeMacro(steps: 10)
        let large = makeMacro(steps: 100)

        let smallMedian = medianNanoseconds { _ = MacroAutomationBridge.automationProgram(for: small) }
        let largeMedian = medianNanoseconds { _ = MacroAutomationBridge.automationProgram(for: large) }

        NSLog("[Bench] bridge conversion: 10 steps %.1fµs, 100 steps %.1fµs", smallMedian / 1_000, largeMedian / 1_000)
        XCTAssertLessThan(smallMedian, 1_000_000, "10-step conversion should be far under 1ms")
        XCTAssertLessThan(largeMedian, 5_000_000, "100-step conversion should be far under 5ms")
    }

    // MARK: - Command resolution cost (runs on inputQueue per button press)

    func testCommandResolutionCostByActionKind() {
        let profileMacro = makeMacro(steps: 10)
        let sharedMacro = AutomationMacro(name: "Shared", program: MacroAutomationBridge.automationProgram(for: makeMacro(steps: 10)))
        store.upsert(sharedMacro)
        var profile = Profile(name: "Bench", macros: [profileMacro])
        profile.sharedMacroSnapshots[sharedMacro.id] = sharedMacro.program

        let keyAction = KeyMapping(keyCode: 0, modifiers: .command)
        let profileMacroAction = KeyMapping(macroId: profileMacro.id)
        let sharedMacroAction = KeyMapping(macroId: sharedMacro.id)

        let keyMedian = medianNanoseconds { _ = self.factory.makeCommand(for: keyAction, profile: profile) }
        let profileMacroMedian = medianNanoseconds { _ = self.factory.makeCommand(for: profileMacroAction, profile: profile) }
        let sharedMacroMedian = medianNanoseconds { _ = self.factory.makeCommand(for: sharedMacroAction, profile: profile) }

        NSLog("[Bench] makeCommand: keyPress %.1fµs, profile macro %.1fµs, shared macro %.1fµs",
              keyMedian / 1_000, profileMacroMedian / 1_000, sharedMacroMedian / 1_000)
        XCTAssertLessThan(keyMedian, 100_000, "Plain key press resolution must stay trivial (<0.1ms)")
        XCTAssertLessThan(profileMacroMedian, 500_000)
        XCTAssertLessThan(sharedMacroMedian, 1_000_000, "Shared macro resolution (store lookup + normalize) should stay under 1ms")
    }

    // MARK: - Macro dispatch latency (execute() to first posted event)

    func testMacroDispatchLatencyToFirstEvent() async {
        let macro = Macro(name: "Latency", steps: [.press(KeyMapping(keyCode: 1))])
        let profile = Profile(name: "Bench", macros: [macro])
        var samples: [Double] = []

        for _ in 0..<30 {
            mockInputSimulator.clearEvents()
            let command = factory.makeCommand(for: KeyMapping(macroId: macro.id), profile: profile)
            let start = DispatchTime.now().uptimeNanoseconds
            _ = command.execute()
            while mockInputSimulator.events.isEmpty {
                await Task.yield()
                if DispatchTime.now().uptimeNanoseconds - start > 2_000_000_000 { break }
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start))
        }

        let median = samples.sorted()[samples.count / 2]
        NSLog("[Bench] macro dispatch latency (execute -> first event): median %.2fms, max %.2fms",
              median / 1_000_000, (samples.max() ?? 0) / 1_000_000)
        XCTAssertLessThan(median, 50_000_000, "Macro start should be well under one key-press duration (50ms)")
    }

    // MARK: - Snapshot sync cost (runs on every profile save)

    func testSnapshotSyncCostOnLargeProfile() {
        var profile = Profile(name: "Big")
        for (index, button) in ControllerButton.allCases.prefix(30).enumerated() {
            profile.buttonMappings[button] = KeyMapping(
                longHoldMapping: LongHoldMapping(macroId: index % 3 == 0 ? UUID() : nil),
                doubleTapMapping: DoubleTapMapping(keyCode: 5),
                macroId: index % 2 == 0 ? UUID() : nil
            )
        }
        profile.chordMappings = (0..<20).map { _ in ChordMapping(buttons: [.a, .b], macroId: UUID()) }
        profile.sequenceMappings = (0..<20).map { _ in SequenceMapping(steps: [.a, .b], macroId: UUID()) }
        profile.layers = (0..<4).map { i in
            Layer(name: "L\(i)", activatorButton: .leftBumper, buttonMappings: Dictionary(
                uniqueKeysWithValues: ControllerButton.allCases.prefix(20).map { ($0, KeyMapping(macroId: UUID())) }
            ))
        }
        profile.macros = (0..<10).map { _ in makeMacro(steps: 10) }

        let median = medianNanoseconds(iterations: 50) {
            _ = SharedMacroSnapshotPolicy.syncedSnapshots(for: profile, store: self.store)
        }

        NSLog("[Bench] snapshot sync on ~150-binding profile: median %.1fµs", median / 1_000)
        XCTAssertLessThan(median, 10_000_000, "Per-save snapshot sync should stay under 10ms even on huge profiles")
    }
}
