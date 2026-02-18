import XCTest
@testable import ControllerKeys

@MainActor
final class SystemCommandExecutorBranchTests: XCTestCase {
    private var profileManager: ProfileManager!
    private var testConfigDirectory: URL!

    private var openedURLs: [URL] = []
    private var resolvedBundleIds: [String] = []
    private var openedAppURLs: [URL] = []
    private var executedScripts: [String] = []
    private var newWindowShortcutCount = 0
    private var appURLToReturn: URL?
    private var appOpenError: Error?

    private var executor: SystemCommandExecutor!

    override func setUp() async throws {
        try await super.setUp()
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-tests-\(UUID().uuidString)", isDirectory: true)
        profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)

        openedURLs = []
        resolvedBundleIds = []
        openedAppURLs = []
        executedScripts = []
        newWindowShortcutCount = 0
        appURLToReturn = nil
        appOpenError = nil

        executor = SystemCommandExecutor(
            profileManager: profileManager,
            appURLResolver: { [weak self] bundleIdentifier in
                self?.resolvedBundleIds.append(bundleIdentifier)
                return self?.appURLToReturn
            },
            appOpener: { [weak self] url, _, completion in
                self?.openedAppURLs.append(url)
                completion(nil, self?.appOpenError)
            },
            urlOpener: { [weak self] url in
                self?.openedURLs.append(url)
            },
            appleScriptRunner: { [weak self] script in
                self?.executedScripts.append(script)
                return nil
            },
            newWindowShortcutSender: { [weak self] in
                self?.newWindowShortcutCount += 1
            }
        )
    }

    override func tearDown() async throws {
        executor = nil
        profileManager = nil
        testConfigDirectory = nil
        try await super.tearDown()
    }

    func testOpenLinkWithoutSchemeUsesHTTPSAndInjectedOpener() async {
        executor.execute(.openLink(url: "example.com/path"))

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertEqual(openedURLs.first?.absoluteString, "https://example.com/path")
    }

    func testOpenLinkInvalidURLDoesNotCallOpener() async {
        executor.execute(.openLink(url: "http://[::1"))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(openedURLs.isEmpty)
    }

    func testLaunchAppMissingBundleDoesNotOpen() async {
        appURLToReturn = nil

        executor.execute(.launchApp(bundleIdentifier: "com.example.missing", newWindow: false))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(resolvedBundleIds, ["com.example.missing"])
        XCTAssertTrue(openedAppURLs.isEmpty)
        XCTAssertEqual(newWindowShortcutCount, 0)
    }

    func testLaunchAppNewWindowTriggersShortcutOnSuccess() async {
        appURLToReturn = URL(fileURLWithPath: "/Applications/Fake.app")
        appOpenError = nil

        executor.execute(.launchApp(bundleIdentifier: "com.example.fake", newWindow: true))
        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertEqual(resolvedBundleIds, ["com.example.fake"])
        XCTAssertEqual(openedAppURLs, [URL(fileURLWithPath: "/Applications/Fake.app")])
        XCTAssertEqual(newWindowShortcutCount, 1)
    }

    func testLaunchAppOpenErrorSkipsShortcut() async {
        appURLToReturn = URL(fileURLWithPath: "/Applications/Fake.app")
        appOpenError = NSError(domain: "SystemCommandExecutorTests", code: 1)

        executor.execute(.launchApp(bundleIdentifier: "com.example.fake", newWindow: true))
        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertEqual(openedAppURLs.count, 1)
        XCTAssertEqual(newWindowShortcutCount, 0)
    }

    func testShellCommandSilentBranchRuns() async {
        executor.execute(.shellCommand(command: "/usr/bin/true", inTerminal: false))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(true)
    }

    func testShellCommandTerminalBranchBuildsScriptsForSupportedApps() async {
        func executeInTerminal(app: String) async {
            profileManager.setDefaultTerminalApp(app)
            executor.execute(.shellCommand(command: "echo hi", inTerminal: true))
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        await executeInTerminal(app: "iTerm")
        await executeInTerminal(app: "Warp")
        await executeInTerminal(app: "Alacritty")
        await executeInTerminal(app: "Rio")

        XCTAssertEqual(executedScripts.count, 4)
        XCTAssertTrue(executedScripts.contains { $0.contains("tell application \"iTerm\"") })
        XCTAssertTrue(executedScripts.contains { $0.contains("tell application \"Warp\"") })
        XCTAssertTrue(executedScripts.contains { $0.contains("tell application \"Alacritty\"") })
        XCTAssertTrue(executedScripts.contains { $0.contains("tell application \"Terminal\"") })
    }
}
