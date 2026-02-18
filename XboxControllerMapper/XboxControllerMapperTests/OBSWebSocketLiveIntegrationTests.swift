import XCTest
import Foundation
import CryptoKit
@testable import ControllerKeys

private enum OBSLiveTestError: Error, LocalizedError {
    case invalidURL(String)
    case unsupportedURLScheme(String)
    case invalidMessage
    case invalidHello
    case identifyFailed
    case timeout(String)
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Invalid OBS websocket URL: \(value)"
        case .unsupportedURLScheme(let value):
            return "OBS websocket URL must use ws:// or wss://, got: \(value)"
        case .invalidMessage:
            return "Received invalid OBS websocket message"
        case .invalidHello:
            return "OBS websocket hello payload was invalid"
        case .identifyFailed:
            return "OBS websocket identify step failed"
        case .timeout(let context):
            return "Timed out while waiting for OBS websocket response: \(context)"
        case .authenticationRequired:
            return "OBS websocket requires authentication, but no password was provided"
        }
    }
}

private struct OBSPluginWebSocketConfig: Decodable {
    let auth_required: Bool
    let server_enabled: Bool
    let server_password: String?
    let server_port: Int
}

private struct OBSLiveIntegrationConfig {
    let url: URL
    let password: String?
    let allowOutputMutations: Bool
    let autoManageMediaMTX: Bool

    static func load() throws -> OBSLiveIntegrationConfig {
        let env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let liveEnabledSentinel = "\(home)/.controllerkeys/obs_live_tests_enabled"
        let outputMutationSentinel = "\(home)/.controllerkeys/obs_live_tests_allow_output_mutations"
        let liveEnabled = (env["OBS_LIVE_TESTS"] == "1") || FileManager.default.fileExists(atPath: liveEnabledSentinel)
        guard liveEnabled else {
            throw XCTSkip("Enable live OBS tests with OBS_LIVE_TESTS=1 or create \(liveEnabledSentinel)")
        }

        let urlString = env["OBS_WS_URL"] ?? "ws://127.0.0.1:4455"
        guard let url = URL(string: urlString) else {
            throw OBSLiveTestError.invalidURL(urlString)
        }
        guard let scheme = url.scheme?.lowercased(), ["ws", "wss"].contains(scheme) else {
            throw OBSLiveTestError.unsupportedURLScheme(urlString)
        }

        let obsConfigURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json")

        let pluginConfig: OBSPluginWebSocketConfig? = {
            guard let data = try? Data(contentsOf: obsConfigURL) else { return nil }
            return try? JSONDecoder().decode(OBSPluginWebSocketConfig.self, from: data)
        }()

        if pluginConfig?.server_enabled == false {
            throw XCTSkip("OBS websocket server is disabled. Enable it in OBS: Tools > WebSocket Server Settings")
        }

        let password = env["OBS_WS_PASSWORD"] ?? pluginConfig?.server_password
        if pluginConfig?.auth_required == true && (password?.isEmpty ?? true) {
            throw XCTSkip("OBS websocket auth is enabled. Set OBS_WS_PASSWORD or configure OBS password")
        }

        let allowOutputMutations = (env["OBS_LIVE_ALLOW_OUTPUT_MUTATIONS"] == "1")
            || FileManager.default.fileExists(atPath: outputMutationSentinel)
        let autoManageMediaMTX = (env["OBS_LIVE_MANAGE_MEDIAMTX"] ?? "1") != "0"
        return OBSLiveIntegrationConfig(
            url: url,
            password: password,
            allowOutputMutations: allowOutputMutations,
            autoManageMediaMTX: autoManageMediaMTX
        )
    }
}

private struct OBSLiveResponse {
    let requestType: String
    let requestId: String
    let result: Bool
    let code: Int
    let comment: String?
    let responseData: [String: Any]
}

private enum OBSMediaMTXManager {
    private static let lock = NSLock()
    private static var activeUsers = 0
    private static var startedByTests = false
    private static var process: Process?
    private static var logHandle: FileHandle?
    private static let logPath = "/tmp/controllerkeys-obs-mediamtx.log"

    static func acquireIfNeeded() throws {
        lock.lock()
        activeUsers += 1
        let currentProcess = process
        lock.unlock()

        if currentProcess?.isRunning == true || isPortOpen() {
            return
        }

        let binaryPath = try resolveBinaryPath()
        try start(binaryPath: binaryPath)
    }

    static func releaseIfNeeded() {
        lock.lock()
        activeUsers = max(0, activeUsers - 1)
        let shouldStop = activeUsers == 0 && startedByTests
        let currentProcess = process
        lock.unlock()

        guard shouldStop else { return }
        stop(process: currentProcess)
    }

    static func forceRelease() {
        lock.lock()
        activeUsers = 0
        let shouldStop = startedByTests
        let currentProcess = process
        lock.unlock()

        guard shouldStop else { return }
        stop(process: currentProcess)
    }

    private static func resolveBinaryPath() throws -> String {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["MEDIAMTX_BIN"], !explicit.isEmpty, FileManager.default.isExecutableFile(atPath: explicit) {
            return explicit
        }

        let candidates = [
            "/opt/homebrew/bin/mediamtx",
            "/usr/local/bin/mediamtx"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["mediamtx"]
        let outPipe = Pipe()
        which.standardOutput = outPipe
        which.standardError = Pipe()
        try? which.run()
        which.waitUntilExit()
        if which.terminationStatus == 0 {
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        throw XCTSkip("mediamtx not found. Install with `brew install mediamtx` or set MEDIAMTX_BIN")
    }

    private static func start(binaryPath: String) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        try? handle.seekToEnd()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = []
        p.standardOutput = handle
        p.standardError = handle
        try p.run()

        for _ in 0..<50 {
            if isPortOpen() {
                lock.lock()
                process = p
                logHandle = handle
                startedByTests = true
                lock.unlock()
                return
            }
            usleep(100_000)
        }

        if p.isRunning {
            p.terminate()
            p.waitUntilExit()
        }
        try? handle.close()

        throw XCTSkip("Started mediamtx but port 1935 did not become ready. See \(logPath)")
    }

    private static func stop(process currentProcess: Process?) {
        guard let currentProcess else { return }
        if currentProcess.isRunning {
            currentProcess.terminate()
            currentProcess.waitUntilExit()
        }

        lock.lock()
        process = nil
        startedByTests = false
        let handle = logHandle
        logHandle = nil
        lock.unlock()

        try? handle?.close()
    }

    private static func isPortOpen(host: String = "127.0.0.1", port: Int = 1935) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        p.arguments = ["-z", host, "\(port)"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
        } catch {
            return false
        }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

private final class OBSLiveWebSocketConnection {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(url: URL) {
        let config = URLSessionConfiguration.ephemeral
        self.session = URLSession(configuration: config)
        self.task = session.webSocketTask(with: url)
        self.task.resume()
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }

    func identify(password: String?) async throws {
        let hello = try await receiveJSONObject()
        guard (hello["op"] as? Int) == 0 else {
            throw OBSLiveTestError.invalidHello
        }

        let helloData = hello["d"] as? [String: Any] ?? [:]
        var identifyData: [String: Any] = ["rpcVersion": 1]

        if let auth = helloData["authentication"] as? [String: Any] {
            guard let salt = auth["salt"] as? String,
                  let challenge = auth["challenge"] as? String else {
                throw OBSLiveTestError.invalidHello
            }
            guard let password = password, !password.isEmpty else {
                throw OBSLiveTestError.authenticationRequired
            }
            identifyData["authentication"] = Self.computeAuth(password: password, salt: salt, challenge: challenge)
        }

        try await sendJSONObject(["op": 1, "d": identifyData])

        for _ in 0..<25 {
            let message = try await receiveJSONObject()
            guard let op = message["op"] as? Int else { continue }
            if op == 2 {
                return
            }
        }

        throw OBSLiveTestError.identifyFailed
    }

    func request(_ requestType: String, requestData: [String: Any]? = nil) async throws -> OBSLiveResponse {
        let requestId = UUID().uuidString
        var payload: [String: Any] = [
            "requestType": requestType,
            "requestId": requestId
        ]
        if let requestData {
            payload["requestData"] = requestData
        }

        try await sendJSONObject(["op": 6, "d": payload])

        for _ in 0..<120 {
            let message = try await receiveJSONObject()
            guard let op = message["op"] as? Int else {
                throw OBSLiveTestError.invalidMessage
            }

            // Ignore non-request-response messages (events, etc.)
            guard op == 7 else {
                continue
            }

            guard let data = message["d"] as? [String: Any],
                  let responseId = data["requestId"] as? String,
                  responseId == requestId,
                  let status = data["requestStatus"] as? [String: Any],
                  let result = status["result"] as? Bool,
                  let code = status["code"] as? Int else {
                throw OBSLiveTestError.invalidMessage
            }

            let comment = status["comment"] as? String
            let responseData = data["responseData"] as? [String: Any] ?? [:]
            return OBSLiveResponse(
                requestType: requestType,
                requestId: requestId,
                result: result,
                code: code,
                comment: comment,
                responseData: responseData
            )
        }

        throw OBSLiveTestError.timeout(requestType)
    }

    private func sendJSONObject(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw OBSLiveTestError.invalidMessage
        }
        try await task.send(.string(text))
    }

    private func receiveJSONObject() async throws -> [String: Any] {
        let message = try await task.receive()
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let rawData):
            data = rawData
        @unknown default:
            throw OBSLiveTestError.invalidMessage
        }

        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let json = object as? [String: Any] else {
            throw OBSLiveTestError.invalidMessage
        }
        return json
    }

    private static func computeAuth(password: String, salt: String, challenge: String) -> String {
        let secretInput = Data((password + salt).utf8)
        let secretHash = Data(SHA256.hash(data: secretInput))
        let secret = secretHash.base64EncodedString()

        let authInput = Data((secret + challenge).utf8)
        let authHash = Data(SHA256.hash(data: authInput))
        return authHash.base64EncodedString()
    }
}

final class OBSWebSocketLiveIntegrationTests: XCTestCase {
    private let bootstrapSceneName = "ControllerKeys OBS Test Scene"
    private let bootstrapSourceName = "ControllerKeys OBS Test Source"
    private let preferredBootstrapInputKinds = [
        "color_source_v3",
        "color_source",
        "text_ft2_source_v2",
        "text_gdiplus_v2",
        "image_source",
        "browser_source"
    ]
    private static let suiteLock = NSLock()
    private static var suiteMediaMTXAcquired = false

    private var config: OBSLiveIntegrationConfig!

    override func setUpWithError() throws {
        try super.setUpWithError()
        config = try OBSLiveIntegrationConfig.load()
        if config.allowOutputMutations && config.autoManageMediaMTX {
            Self.suiteLock.lock()
            let needsAcquire = !Self.suiteMediaMTXAcquired
            Self.suiteLock.unlock()

            if needsAcquire {
                try OBSMediaMTXManager.acquireIfNeeded()
                Self.suiteLock.lock()
                Self.suiteMediaMTXAcquired = true
                Self.suiteLock.unlock()
            }
        }
    }

    override class func tearDown() {
        suiteLock.lock()
        let shouldRelease = suiteMediaMTXAcquired
        suiteMediaMTXAcquired = false
        suiteLock.unlock()

        if shouldRelease {
            OBSMediaMTXManager.forceRelease()
        }

        super.tearDown()
    }

    func testOBSWebSocketClient_GetVersion_AgainstRealOBS() async throws {
        let client = OBSWebSocketClient(url: config.url, password: config.password)
        do {
            let result = try await client.executeRequest(
                requestType: "GetVersion",
                requestDataJSON: nil,
                timeout: 8
            )
            XCTAssertEqual(result.code, 100)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            throw XCTSkip("Cannot connect to OBS websocket at \(config.url.absoluteString). Restart OBS and ensure websocket server is enabled")
        }
    }

    func testTypicalOBSReadRequests_AgainstRealOBS() async throws {
        let connection = try await openConnection()
        defer { connection.close() }

        let readRequestTypes = [
            "GetVersion",
            "GetStats",
            "GetStreamStatus",
            "GetRecordStatus",
            "GetReplayBufferStatus",
            "GetVirtualCamStatus",
            "GetStudioModeEnabled",
            "GetSceneList",
            "GetInputList",
            "GetSpecialInputs",
            "GetProfileList",
            "GetSceneCollectionList",
            "GetCurrentSceneTransition",
            "GetCurrentProgramScene"
        ]

        let allowedUnavailableCodes: [String: Set<Int>] = [
            // OBS returns 604 when replay buffer is disabled/not configured
            "GetReplayBufferStatus": [604]
        ]

        for requestType in readRequestTypes {
            let response = try await connection.request(requestType)
            if response.result {
                continue
            }

            if let allowedCodes = allowedUnavailableCodes[requestType],
               allowedCodes.contains(response.code) {
                continue
            }

            assertSuccess(response, context: requestType)
        }
    }

    func testTypicalOBSControlRequests_AgainstRealOBS() async throws {
        let connection = try await openConnection()
        defer { connection.close() }

        // Studio mode roundtrip + transition trigger
        let studioStatus = try await connection.request("GetStudioModeEnabled")
        assertSuccess(studioStatus, context: "GetStudioModeEnabled")
        let initialStudioMode = try boolValue(studioStatus.responseData, key: "studioModeEnabled")

        let sceneList = try await connection.request("GetSceneList")
        assertSuccess(sceneList, context: "GetSceneList")
        let sceneNames = parseSceneNames(sceneList.responseData)
        guard let primaryScene = sceneNames.first else {
            throw XCTSkip("No scenes found in OBS scene list")
        }

        let setStudioOn = try await connection.request("SetStudioModeEnabled", requestData: ["studioModeEnabled": true])
        assertSuccess(setStudioOn, context: "SetStudioModeEnabled(true)")
        let setPreview = try await connection.request("SetCurrentPreviewScene", requestData: ["sceneName": primaryScene])
        assertSuccess(setPreview, context: "SetCurrentPreviewScene")
        let getPreview = try await connection.request("GetCurrentPreviewScene")
        assertSuccess(getPreview, context: "GetCurrentPreviewScene")
        let transition = try await connection.request("TriggerStudioModeTransition")
        assertSuccess(transition, context: "TriggerStudioModeTransition")
        let getProgram = try await connection.request("GetCurrentProgramScene")
        assertSuccess(getProgram, context: "GetCurrentProgramScene")

        // Restore original studio mode state
        let restoreStudio = try await connection.request("SetStudioModeEnabled", requestData: ["studioModeEnabled": initialStudioMode])
        assertSuccess(restoreStudio, context: "Restore SetStudioModeEnabled")

        // Program scene set
        let setProgram = try await connection.request("SetCurrentProgramScene", requestData: ["sceneName": primaryScene])
        assertSuccess(setProgram, context: "SetCurrentProgramScene")

        // Transition set + duration set
        let transitions = try await connection.request("GetSceneTransitionList")
        assertSuccess(transitions, context: "GetSceneTransitionList")
        if let transitionName = parseTransitionNames(transitions.responseData).first {
            let setTransition = try await connection.request("SetCurrentSceneTransition", requestData: ["transitionName": transitionName])
            assertSuccess(setTransition, context: "SetCurrentSceneTransition")
        }
        let setDuration = try await connection.request("SetCurrentSceneTransitionDuration", requestData: ["transitionDuration": 300])
        assertSuccess(setDuration, context: "SetCurrentSceneTransitionDuration")

        // Profile set (idempotent: set current)
        let profiles = try await connection.request("GetProfileList")
        assertSuccess(profiles, context: "GetProfileList")
        if let currentProfileName = profiles.responseData["currentProfileName"] as? String, !currentProfileName.isEmpty {
            let setProfile = try await connection.request("SetCurrentProfile", requestData: ["profileName": currentProfileName])
            assertSuccess(setProfile, context: "SetCurrentProfile")
        }

        // Scene collection set (idempotent: set current)
        let collections = try await connection.request("GetSceneCollectionList")
        assertSuccess(collections, context: "GetSceneCollectionList")
        if let currentCollectionName = collections.responseData["currentSceneCollectionName"] as? String,
           !currentCollectionName.isEmpty {
            let setCollection = try await connection.request("SetCurrentSceneCollection", requestData: ["sceneCollectionName": currentCollectionName])
            assertSuccess(setCollection, context: "SetCurrentSceneCollection")
        }

        // Input mute toggle roundtrip on first compatible input
        try await exerciseInputMuteRoundtrip(connection: connection)
        try await exerciseInputVolumeRoundtrip(connection: connection)
        try await exerciseInputAudioMonitorRoundtrip(connection: connection)
        try await exerciseSourceFilterEnabledRoundtrip(connection: connection)

        // Scene item enabled roundtrip (auto-bootstraps a tiny test scene/source when needed)
        let sceneNamesForItems = try await ensureSceneItemTarget(
            connection: connection,
            existingSceneNames: sceneNames
        )
        try await exerciseSceneItemEnabledRoundtrip(connection: connection, sceneNames: sceneNamesForItems)
    }

    func testTypicalOBSOutputLifecycleRequests_AgainstRealOBS() async throws {
        guard config.allowOutputMutations else {
            throw XCTSkip("Set OBS_LIVE_ALLOW_OUTPUT_MUTATIONS=1 to run start/stop lifecycle tests for stream/record/replay/virtualcam")
        }

        let connection = try await openConnection()
        defer { connection.close() }

        // Point OBS to a local RTMP sink for this test and restore original settings on exit.
        let originalStreamService = try await connection.request("GetStreamServiceSettings")
        assertSuccess(originalStreamService, context: "GetStreamServiceSettings")
        let originalType = originalStreamService.responseData["streamServiceType"] as? String
        let originalSettings = originalStreamService.responseData["streamServiceSettings"] as? [String: Any]

        let setLocalService = try await connection.request(
            "SetStreamServiceSettings",
            requestData: [
                "streamServiceType": "rtmp_custom",
                "streamServiceSettings": [
                    "server": "rtmp://127.0.0.1:1935/live",
                    "key": "test",
                    "use_auth": false
                ]
            ]
        )
        guard setLocalService.result else {
            throw XCTSkip("Failed to set local RTMP stream service for lifecycle test (code: \(setLocalService.code), comment: \(setLocalService.comment ?? "none"))")
        }

        do {
            try await verifyOutputRoundtrip(
                connection: connection,
                featureName: "Recording",
                statusRequest: "GetRecordStatus",
                startRequest: "StartRecord",
                stopRequest: "StopRecord"
            )
            try await exerciseRecordSplitAndChapter(connection: connection)

            try await verifyOutputRoundtrip(
                connection: connection,
                featureName: "Streaming",
                statusRequest: "GetStreamStatus",
                startRequest: "StartStream",
                stopRequest: "StopStream"
            )

            try await verifyOutputRoundtrip(
                connection: connection,
                featureName: "Replay Buffer",
                statusRequest: "GetReplayBufferStatus",
                startRequest: "StartReplayBuffer",
                stopRequest: "StopReplayBuffer",
                unavailableCodes: [604]
            )

            // Save replay buffer snapshot while replay buffer is active
            let replayStatus = try await connection.request("GetReplayBufferStatus")
            if !replayStatus.result && replayStatus.code == 604 {
                throw XCTSkip("Replay buffer unavailable in current OBS profile/config")
            }
            assertSuccess(replayStatus, context: "GetReplayBufferStatus")
            if (replayStatus.responseData["outputActive"] as? Bool) == true {
                let saveReplay = try await connection.request("SaveReplayBuffer")
                assertSuccess(saveReplay, context: "SaveReplayBuffer")
                try await waitForLastReplayBufferPath(connection: connection)
            }

            try await verifyOutputRoundtrip(
                connection: connection,
                featureName: "Virtual Camera",
                statusRequest: "GetVirtualCamStatus",
                startRequest: "StartVirtualCam",
                stopRequest: "StopVirtualCam"
            )
            try await verifyOutputToggleRoundtrip(
                connection: connection,
                featureName: "Virtual Camera",
                statusRequest: "GetVirtualCamStatus",
                toggleRequest: "ToggleVirtualCam"
            )
        } catch {
            try? await restoreStreamServiceSettings(
                connection: connection,
                streamServiceType: originalType,
                streamServiceSettings: originalSettings
            )
            throw error
        }

        try await restoreStreamServiceSettings(
            connection: connection,
            streamServiceType: originalType,
            streamServiceSettings: originalSettings
        )
    }

    // MARK: - Helpers

    private func openConnection() async throws -> OBSLiveWebSocketConnection {
        let connection = OBSLiveWebSocketConnection(url: config.url)
        do {
            try await connection.identify(password: config.password)
            return connection
        } catch let error as URLError where error.code == .cannotConnectToHost {
            connection.close()
            throw XCTSkip("Cannot connect to OBS websocket at \(config.url.absoluteString). Restart OBS and ensure websocket server is enabled")
        } catch {
            connection.close()
            throw error
        }
    }

    private func assertSuccess(
        _ response: OBSLiveResponse,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            response.result,
            "\(context) failed (code: \(response.code), comment: \(response.comment ?? "none"))",
            file: file,
            line: line
        )
    }

    private func boolValue(_ dictionary: [String: Any], key: String) throws -> Bool {
        guard let value = dictionary[key] as? Bool else {
            throw XCTSkip("Expected boolean key '\(key)' in OBS response, got: \(dictionary)")
        }
        return value
    }

    private func parseSceneNames(_ responseData: [String: Any]) -> [String] {
        guard let scenes = responseData["scenes"] as? [[String: Any]] else { return [] }
        return scenes.compactMap { $0["sceneName"] as? String }
    }

    private func parseTransitionNames(_ responseData: [String: Any]) -> [String] {
        guard let transitions = responseData["transitions"] as? [[String: Any]] else { return [] }
        return transitions.compactMap { $0["transitionName"] as? String }
    }

    private func exerciseInputMuteRoundtrip(connection: OBSLiveWebSocketConnection) async throws {
        let inputsResponse = try await connection.request("GetInputList")
        assertSuccess(inputsResponse, context: "GetInputList")
        let inputs = ((inputsResponse.responseData["inputs"] as? [[String: Any]]) ?? [])
            .compactMap { $0["inputName"] as? String }

        for inputName in inputs {
            let getMuteResponse = try await connection.request("GetInputMute", requestData: ["inputName": inputName])
            guard getMuteResponse.result else { continue }

            let initialMuted = try boolValue(getMuteResponse.responseData, key: "inputMuted")

            let setMuted = try await connection.request(
                "SetInputMute",
                requestData: [
                    "inputName": inputName,
                    "inputMuted": !initialMuted
                ]
            )
            assertSuccess(setMuted, context: "SetInputMute(toggle) for \(inputName)")
            let restoreMuted = try await connection.request(
                "SetInputMute",
                requestData: [
                    "inputName": inputName,
                    "inputMuted": initialMuted
                ]
            )
            assertSuccess(restoreMuted, context: "SetInputMute(restore) for \(inputName)")

            let firstToggle = try await connection.request("ToggleInputMute", requestData: ["inputName": inputName])
            assertSuccess(firstToggle, context: "ToggleInputMute(1) for \(inputName)")
            let secondToggle = try await connection.request("ToggleInputMute", requestData: ["inputName": inputName])
            assertSuccess(secondToggle, context: "ToggleInputMute(2) for \(inputName)")

            let finalMutedResponse = try await connection.request("GetInputMute", requestData: ["inputName": inputName])
            assertSuccess(finalMutedResponse, context: "GetInputMute(final) for \(inputName)")
            let finalMuted = try boolValue(finalMutedResponse.responseData, key: "inputMuted")
            XCTAssertEqual(finalMuted, initialMuted, "Input mute state did not restore for \(inputName)")
            return
        }

        throw XCTSkip("No compatible input found for GetInputMute/ToggleInputMute roundtrip")
    }

    private func exerciseInputVolumeRoundtrip(connection: OBSLiveWebSocketConnection) async throws {
        let inputsResponse = try await connection.request("GetInputList")
        assertSuccess(inputsResponse, context: "GetInputList")
        let inputs = ((inputsResponse.responseData["inputs"] as? [[String: Any]]) ?? [])
            .compactMap { $0["inputName"] as? String }

        for inputName in inputs {
            let getVolume = try await connection.request("GetInputVolume", requestData: ["inputName": inputName])
            guard getVolume.result else { continue }

            let initialVolume = try doubleValue(getVolume.responseData, key: "inputVolumeMul")
            var targetVolume = initialVolume < 0.75 ? (initialVolume + 0.15) : (initialVolume - 0.15)
            targetVolume = min(2.0, max(0.0, targetVolume))
            if abs(targetVolume - initialVolume) < 0.01 {
                continue
            }

            let setVolume = try await connection.request(
                "SetInputVolume",
                requestData: [
                    "inputName": inputName,
                    "inputVolumeMul": targetVolume
                ]
            )
            guard setVolume.result else { continue }

            let afterSet = try await connection.request("GetInputVolume", requestData: ["inputName": inputName])
            assertSuccess(afterSet, context: "GetInputVolume(after set) for \(inputName)")
            let afterSetVolume = try doubleValue(afterSet.responseData, key: "inputVolumeMul")
            XCTAssertEqual(afterSetVolume, targetVolume, accuracy: 0.2, "Input volume did not change as expected for \(inputName)")

            let restoreVolume = try await connection.request(
                "SetInputVolume",
                requestData: [
                    "inputName": inputName,
                    "inputVolumeMul": initialVolume
                ]
            )
            assertSuccess(restoreVolume, context: "SetInputVolume(restore) for \(inputName)")
            return
        }

        throw XCTSkip("No compatible input found for GetInputVolume/SetInputVolume roundtrip")
    }

    private func exerciseInputAudioMonitorRoundtrip(connection: OBSLiveWebSocketConnection) async throws {
        let monitorTypes = [
            "OBS_MONITORING_TYPE_NONE",
            "OBS_MONITORING_TYPE_MONITOR_ONLY",
            "OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT"
        ]

        let inputsResponse = try await connection.request("GetInputList")
        assertSuccess(inputsResponse, context: "GetInputList")
        let inputs = ((inputsResponse.responseData["inputs"] as? [[String: Any]]) ?? [])
            .compactMap { $0["inputName"] as? String }

        for inputName in inputs {
            let getMonitor = try await connection.request("GetInputAudioMonitorType", requestData: ["inputName": inputName])
            guard getMonitor.result else { continue }
            guard let initialType = getMonitor.responseData["monitorType"] as? String else { continue }
            guard let targetType = monitorTypes.first(where: { $0 != initialType }) else { continue }

            let setMonitor = try await connection.request(
                "SetInputAudioMonitorType",
                requestData: [
                    "inputName": inputName,
                    "monitorType": targetType
                ]
            )
            guard setMonitor.result else { continue }

            let afterSet = try await connection.request("GetInputAudioMonitorType", requestData: ["inputName": inputName])
            assertSuccess(afterSet, context: "GetInputAudioMonitorType(after set) for \(inputName)")
            XCTAssertEqual(afterSet.responseData["monitorType"] as? String, targetType)

            let restore = try await connection.request(
                "SetInputAudioMonitorType",
                requestData: [
                    "inputName": inputName,
                    "monitorType": initialType
                ]
            )
            assertSuccess(restore, context: "SetInputAudioMonitorType(restore) for \(inputName)")
            return
        }

        throw XCTSkip("No compatible input found for Get/SetInputAudioMonitorType roundtrip")
    }

    private func exerciseSourceFilterEnabledRoundtrip(connection: OBSLiveWebSocketConnection) async throws {
        let inputsResponse = try await connection.request("GetInputList")
        assertSuccess(inputsResponse, context: "GetInputList")
        let inputs = ((inputsResponse.responseData["inputs"] as? [[String: Any]]) ?? [])
            .compactMap { $0["inputName"] as? String }

        for sourceName in inputs {
            let filtersResponse = try await connection.request("GetSourceFilterList", requestData: ["sourceName": sourceName])
            guard filtersResponse.result else { continue }
            let filters = (filtersResponse.responseData["filters"] as? [[String: Any]]) ?? []
            guard let firstFilter = filters.first,
                  let filterName = firstFilter["filterName"] as? String else {
                continue
            }

            let initialEnabled: Bool
            if let enabled = firstFilter["filterEnabled"] as? Bool {
                initialEnabled = enabled
            } else {
                let getFilter = try await connection.request(
                    "GetSourceFilter",
                    requestData: [
                        "sourceName": sourceName,
                        "filterName": filterName
                    ]
                )
                guard getFilter.result else { continue }
                initialEnabled = try boolValue(getFilter.responseData, key: "filterEnabled")
            }

            let setDisabled = try await connection.request(
                "SetSourceFilterEnabled",
                requestData: [
                    "sourceName": sourceName,
                    "filterName": filterName,
                    "filterEnabled": !initialEnabled
                ]
            )
            guard setDisabled.result else { continue }

            let getFilterAfter = try await connection.request(
                "GetSourceFilter",
                requestData: [
                    "sourceName": sourceName,
                    "filterName": filterName
                ]
            )
            assertSuccess(getFilterAfter, context: "GetSourceFilter(after set) for \(sourceName)/\(filterName)")
            let toggledEnabled = try boolValue(getFilterAfter.responseData, key: "filterEnabled")
            XCTAssertEqual(toggledEnabled, !initialEnabled)

            let restore = try await connection.request(
                "SetSourceFilterEnabled",
                requestData: [
                    "sourceName": sourceName,
                    "filterName": filterName,
                    "filterEnabled": initialEnabled
                ]
            )
            assertSuccess(restore, context: "SetSourceFilterEnabled(restore) for \(sourceName)/\(filterName)")
            return
        }

        throw XCTSkip("No compatible source filter found for GetSourceFilterList/SetSourceFilterEnabled roundtrip")
    }

    private func exerciseSceneItemEnabledRoundtrip(
        connection: OBSLiveWebSocketConnection,
        sceneNames: [String]
    ) async throws {
        for sceneName in sceneNames {
            let itemsResponse = try await connection.request("GetSceneItemList", requestData: ["sceneName": sceneName])
            guard itemsResponse.result else { continue }

            let sceneItems = (itemsResponse.responseData["sceneItems"] as? [[String: Any]]) ?? []
            guard let firstItem = sceneItems.first,
                  let sceneItemId = firstItem["sceneItemId"] as? Int else {
                continue
            }

            let enabledResponse = try await connection.request(
                "GetSceneItemEnabled",
                requestData: ["sceneName": sceneName, "sceneItemId": sceneItemId]
            )
            guard enabledResponse.result else { continue }

            let initialEnabled = try boolValue(enabledResponse.responseData, key: "sceneItemEnabled")

            let toggleItem = try await connection.request(
                "SetSceneItemEnabled",
                requestData: [
                    "sceneName": sceneName,
                    "sceneItemId": sceneItemId,
                    "sceneItemEnabled": !initialEnabled
                ]
            )
            assertSuccess(toggleItem, context: "SetSceneItemEnabled(toggle)")

            let restoreItem = try await connection.request(
                "SetSceneItemEnabled",
                requestData: [
                    "sceneName": sceneName,
                    "sceneItemId": sceneItemId,
                    "sceneItemEnabled": initialEnabled
                ]
            )
            assertSuccess(restoreItem, context: "SetSceneItemEnabled(restore)")

            return
        }

        throw XCTSkip("No scene item found for SetSceneItemEnabled roundtrip")
    }

    private func ensureSceneItemTarget(
        connection: OBSLiveWebSocketConnection,
        existingSceneNames: [String]
    ) async throws -> [String] {
        if try await hasSceneItem(connection: connection, sceneNames: existingSceneNames) {
            return existingSceneNames
        }

        var sceneNames = existingSceneNames
        if !sceneNames.contains(bootstrapSceneName) {
            let createScene = try await connection.request("CreateScene", requestData: ["sceneName": bootstrapSceneName])
            if !createScene.result {
                // If scene already exists (or similar benign state), continue and verify via scene listing.
                let benignSceneCreateCodes: Set<Int> = [601, 602]
                guard benignSceneCreateCodes.contains(createScene.code) else {
                    throw XCTSkip("Unable to create bootstrap OBS scene '\(bootstrapSceneName)' (code: \(createScene.code), comment: \(createScene.comment ?? "none"))")
                }
            }
            sceneNames.insert(bootstrapSceneName, at: 0)
        }

        if try await hasSceneItem(connection: connection, sceneNames: [bootstrapSceneName]) {
            if !sceneNames.contains(bootstrapSceneName) {
                sceneNames.insert(bootstrapSceneName, at: 0)
            }
            return sceneNames
        }

        // Reuse existing input if present; otherwise create one using best-effort input kinds.
        var hasBootstrapInput = false
        let inputList = try await connection.request("GetInputList")
        if inputList.result {
            let inputNames = ((inputList.responseData["inputs"] as? [[String: Any]]) ?? [])
                .compactMap { $0["inputName"] as? String }
            hasBootstrapInput = inputNames.contains(bootstrapSourceName)
        }

        if hasBootstrapInput {
            let createSceneItem = try await connection.request(
                "CreateSceneItem",
                requestData: [
                    "sceneName": bootstrapSceneName,
                    "sourceName": bootstrapSourceName,
                    "sceneItemEnabled": true
                ]
            )
            if !createSceneItem.result {
                let benignSceneItemCodes: Set<Int> = [601, 602]
                guard benignSceneItemCodes.contains(createSceneItem.code) else {
                    throw XCTSkip("Unable to attach bootstrap source '\(bootstrapSourceName)' to scene '\(bootstrapSceneName)' (code: \(createSceneItem.code), comment: \(createSceneItem.comment ?? "none"))")
                }
            }
        } else {
            var availableKinds = Set(preferredBootstrapInputKinds)
            let kindsResponse = try await connection.request("GetInputKindList")
            if kindsResponse.result,
               let kinds = kindsResponse.responseData["inputKinds"] as? [String] {
                availableKinds = Set(kinds)
            }

            let candidateKinds = preferredBootstrapInputKinds.filter { availableKinds.contains($0) }
            var created = false
            for inputKind in candidateKinds {
                let createInput = try await connection.request(
                    "CreateInput",
                    requestData: [
                        "sceneName": bootstrapSceneName,
                        "inputName": bootstrapSourceName,
                        "inputKind": inputKind,
                        "inputSettings": [:],
                        "sceneItemEnabled": true
                    ]
                )
                if createInput.result {
                    created = true
                    break
                }
            }

            guard created else {
                throw XCTSkip("Unable to create bootstrap OBS input for scene-item tests. Tried kinds: \(candidateKinds.joined(separator: ", "))")
            }
        }

        if try await hasSceneItem(connection: connection, sceneNames: [bootstrapSceneName]) {
            if !sceneNames.contains(bootstrapSceneName) {
                sceneNames.insert(bootstrapSceneName, at: 0)
            }
            return sceneNames
        }

        throw XCTSkip("Bootstrap scene '\(bootstrapSceneName)' exists but has no scene items to toggle")
    }

    private func hasSceneItem(
        connection: OBSLiveWebSocketConnection,
        sceneNames: [String]
    ) async throws -> Bool {
        for sceneName in sceneNames {
            let itemsResponse = try await connection.request("GetSceneItemList", requestData: ["sceneName": sceneName])
            guard itemsResponse.result else { continue }
            let sceneItems = (itemsResponse.responseData["sceneItems"] as? [[String: Any]]) ?? []
            if sceneItems.contains(where: { $0["sceneItemId"] as? Int != nil }) {
                return true
            }
        }
        return false
    }

    private func exerciseRecordSplitAndChapter(connection: OBSLiveWebSocketConnection) async throws {
        try await withTemporarilyActiveOutput(
            connection: connection,
            featureName: "Recording",
            statusRequest: "GetRecordStatus",
            startRequest: "StartRecord",
            stopRequest: "StopRecord"
        ) {
            let chapter = try await connection.request("CreateRecordChapter")
            guard chapter.result else {
                throw XCTSkip("CreateRecordChapter unavailable in current OBS recording setup (code: \(chapter.code), comment: \(chapter.comment ?? "none"))")
            }

            let split = try await connection.request("SplitRecordFile")
            guard split.result else {
                throw XCTSkip("SplitRecordFile unavailable in current OBS recording setup (code: \(split.code), comment: \(split.comment ?? "none"))")
            }
        }
    }

    private func waitForLastReplayBufferPath(
        connection: OBSLiveWebSocketConnection,
        maxAttempts: Int = 20,
        intervalNanos: UInt64 = 200_000_000
    ) async throws {
        for attempt in 0..<maxAttempts {
            let replayPath = try await connection.request("GetLastReplayBufferReplay")
            if replayPath.result,
               let path = replayPath.responseData["savedReplayPath"] as? String,
               !path.isEmpty {
                return
            }

            if attempt < (maxAttempts - 1) {
                try? await Task.sleep(nanoseconds: intervalNanos)
            }
        }

        throw XCTSkip("GetLastReplayBufferReplay did not return a saved replay path after SaveReplayBuffer")
    }

    private func restoreStreamServiceSettings(
        connection: OBSLiveWebSocketConnection,
        streamServiceType: String?,
        streamServiceSettings: [String: Any]?
    ) async throws {
        guard let streamServiceType, let streamServiceSettings else { return }
        let restore = try await connection.request(
            "SetStreamServiceSettings",
            requestData: [
                "streamServiceType": streamServiceType,
                "streamServiceSettings": streamServiceSettings
            ]
        )
        if !restore.result {
            throw XCTSkip("Failed to restore original OBS stream service settings (code: \(restore.code), comment: \(restore.comment ?? "none"))")
        }
    }

    private func verifyOutputRoundtrip(
        connection: OBSLiveWebSocketConnection,
        featureName: String,
        statusRequest: String,
        startRequest: String,
        stopRequest: String,
        unavailableCodes: Set<Int> = []
    ) async throws {
        let initialStatus = try await connection.request(statusRequest)
        if !initialStatus.result && unavailableCodes.contains(initialStatus.code) {
            throw XCTSkip("\(featureName): unavailable in current OBS profile/config (code: \(initialStatus.code), comment: \(initialStatus.comment ?? "none"))")
        }
        assertSuccess(initialStatus, context: statusRequest)
        guard let initiallyActive = initialStatus.responseData["outputActive"] as? Bool else {
            throw XCTSkip("\(featureName): outputActive missing from \(statusRequest)")
        }

        if initiallyActive {
            let stop = try await connection.request(stopRequest)
            guard stop.result else {
                throw XCTSkip("\(featureName): \(stopRequest) unavailable in current OBS state (code: \(stop.code), comment: \(stop.comment ?? "none"))")
            }

            guard let afterStop = try await waitForOutputState(
                connection: connection,
                statusRequest: statusRequest,
                expectedActive: false
            ) else {
                throw XCTSkip("\(featureName): output did not become inactive after \(stopRequest)")
            }
            assertSuccess(afterStop, context: "\(statusRequest) after stop")

            let restore = try await connection.request(startRequest)
            guard restore.result else {
                throw XCTSkip("\(featureName): failed to restore running state via \(startRequest) (code: \(restore.code), comment: \(restore.comment ?? "none"))")
            }
        } else {
            let start = try await connection.request(startRequest)
            guard start.result else {
                throw XCTSkip("\(featureName): \(startRequest) unavailable in current OBS config/state (code: \(start.code), comment: \(start.comment ?? "none"))")
            }

            guard let afterStart = try await waitForOutputState(
                connection: connection,
                statusRequest: statusRequest,
                expectedActive: true
            ) else {
                throw XCTSkip("\(featureName): output did not become active after \(startRequest)")
            }
            assertSuccess(afterStart, context: "\(statusRequest) after start")

            let restore = try await connection.request(stopRequest)
            guard restore.result else {
                throw XCTSkip("\(featureName): failed to restore stopped state via \(stopRequest) (code: \(restore.code), comment: \(restore.comment ?? "none"))")
            }
        }

        guard let finalStatus = try await waitForOutputState(
            connection: connection,
            statusRequest: statusRequest,
            expectedActive: initiallyActive
        ) else {
            throw XCTSkip("\(featureName): final state did not restore to \(initiallyActive ? "active" : "inactive")")
        }
        assertSuccess(finalStatus, context: "final \(statusRequest)")
        XCTAssertEqual(finalStatus.responseData["outputActive"] as? Bool, initiallyActive)
    }

    private func verifyOutputToggleRoundtrip(
        connection: OBSLiveWebSocketConnection,
        featureName: String,
        statusRequest: String,
        toggleRequest: String,
        unavailableCodes: Set<Int> = []
    ) async throws {
        let initialStatus = try await connection.request(statusRequest)
        if !initialStatus.result && unavailableCodes.contains(initialStatus.code) {
            throw XCTSkip("\(featureName): unavailable in current OBS profile/config (code: \(initialStatus.code), comment: \(initialStatus.comment ?? "none"))")
        }
        assertSuccess(initialStatus, context: statusRequest)
        guard let initiallyActive = initialStatus.responseData["outputActive"] as? Bool else {
            throw XCTSkip("\(featureName): outputActive missing from \(statusRequest)")
        }

        let firstToggle = try await connection.request(toggleRequest)
        guard firstToggle.result else {
            throw XCTSkip("\(featureName): \(toggleRequest) unavailable in current OBS state/config (code: \(firstToggle.code), comment: \(firstToggle.comment ?? "none"))")
        }

        guard let afterFirst = try await waitForOutputState(
            connection: connection,
            statusRequest: statusRequest,
            expectedActive: !initiallyActive
        ) else {
            throw XCTSkip("\(featureName): output did not toggle after first \(toggleRequest)")
        }
        assertSuccess(afterFirst, context: "\(statusRequest) after first \(toggleRequest)")

        let secondToggle = try await connection.request(toggleRequest)
        guard secondToggle.result else {
            throw XCTSkip("\(featureName): second \(toggleRequest) failed (code: \(secondToggle.code), comment: \(secondToggle.comment ?? "none"))")
        }

        guard let finalStatus = try await waitForOutputState(
            connection: connection,
            statusRequest: statusRequest,
            expectedActive: initiallyActive
        ) else {
            throw XCTSkip("\(featureName): output did not restore after second \(toggleRequest)")
        }
        assertSuccess(finalStatus, context: "final \(statusRequest) after \(toggleRequest)")
        XCTAssertEqual(finalStatus.responseData["outputActive"] as? Bool, initiallyActive)
    }

    private func withTemporarilyActiveOutput(
        connection: OBSLiveWebSocketConnection,
        featureName: String,
        statusRequest: String,
        startRequest: String,
        stopRequest: String,
        unavailableCodes: Set<Int> = [],
        body: () async throws -> Void
    ) async throws {
        let initialStatus = try await connection.request(statusRequest)
        if !initialStatus.result && unavailableCodes.contains(initialStatus.code) {
            throw XCTSkip("\(featureName): unavailable in current OBS profile/config (code: \(initialStatus.code), comment: \(initialStatus.comment ?? "none"))")
        }
        assertSuccess(initialStatus, context: statusRequest)
        guard let initiallyActive = initialStatus.responseData["outputActive"] as? Bool else {
            throw XCTSkip("\(featureName): outputActive missing from \(statusRequest)")
        }

        var startedByTest = false
        do {
            if !initiallyActive {
                let start = try await connection.request(startRequest)
                guard start.result else {
                    throw XCTSkip("\(featureName): \(startRequest) unavailable in current OBS config/state (code: \(start.code), comment: \(start.comment ?? "none"))")
                }

                guard let afterStart = try await waitForOutputState(
                    connection: connection,
                    statusRequest: statusRequest,
                    expectedActive: true
                ) else {
                    throw XCTSkip("\(featureName): output did not become active after \(startRequest)")
                }
                assertSuccess(afterStart, context: "\(statusRequest) after temporary start")
                startedByTest = true
            }

            try await body()
        } catch {
            if startedByTest {
                _ = try? await connection.request(stopRequest)
                _ = try? await waitForOutputState(connection: connection, statusRequest: statusRequest, expectedActive: false)
            }
            throw error
        }

        if startedByTest {
            let stop = try await connection.request(stopRequest)
            guard stop.result else {
                throw XCTSkip("\(featureName): failed to stop temporary output via \(stopRequest) (code: \(stop.code), comment: \(stop.comment ?? "none"))")
            }

            guard let afterStop = try await waitForOutputState(
                connection: connection,
                statusRequest: statusRequest,
                expectedActive: false
            ) else {
                throw XCTSkip("\(featureName): output did not return inactive after temporary \(stopRequest)")
            }
            assertSuccess(afterStop, context: "\(statusRequest) after temporary stop")
        }
    }

    private func waitForOutputState(
        connection: OBSLiveWebSocketConnection,
        statusRequest: String,
        expectedActive: Bool,
        maxAttempts: Int = 20,
        intervalNanos: UInt64 = 200_000_000
    ) async throws -> OBSLiveResponse? {
        for attempt in 0..<maxAttempts {
            let response = try await connection.request(statusRequest)
            if response.result, (response.responseData["outputActive"] as? Bool) == expectedActive {
                return response
            }

            if attempt < (maxAttempts - 1) {
                try? await Task.sleep(nanoseconds: intervalNanos)
            }
        }

        return nil
    }

    private func doubleValue(_ dictionary: [String: Any], key: String) throws -> Double {
        guard let value = dictionary[key] as? NSNumber else {
            throw XCTSkip("Expected numeric key '\(key)' in OBS response, got: \(dictionary)")
        }
        return value.doubleValue
    }
}
