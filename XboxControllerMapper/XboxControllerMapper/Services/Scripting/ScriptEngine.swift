import Foundation
import JavaScriptCore
import CoreGraphics
import AppKit

/// JavaScript scripting engine that executes user-defined scripts triggered by controller input.
/// Uses JavaScriptCore (built into macOS) for lightweight, sandboxed script execution.
class ScriptEngine {
    private let context: JSContext
    private var scriptState: [UUID: [String: Any]] = [:]  // Per-script persistent state
    private let inputSimulator: InputSimulatorProtocol
    private let inputQueue: DispatchQueue
    private weak var controllerService: ControllerService?
    private weak var inputLogService: InputLogService?

    /// Whether this is a test execution (key presses are logged instead of executed)
    private var isTestMode = false
    private var testLogs: [String] = []

    /// Named key code mapping for pressKey()
    private static let namedKeys: [String: CGKeyCode] = [
        "space": 49, "return": 36, "enter": 36, "tab": 48, "escape": 53, "esc": 53,
        "delete": 51, "backspace": 51, "forwarddelete": 117,
        "up": 126, "down": 125, "left": 123, "right": 124,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113,
        "volumeup": 72, "volumedown": 73, "mute": 74,
    ]

    init(inputSimulator: InputSimulatorProtocol, inputQueue: DispatchQueue,
         controllerService: ControllerService? = nil, inputLogService: InputLogService? = nil) {
        self.inputSimulator = inputSimulator
        self.inputQueue = inputQueue
        self.controllerService = controllerService
        self.inputLogService = inputLogService
        self.context = JSContext()!
        installAPI()
    }

    // MARK: - Script Execution

    func execute(script: Script, trigger: ScriptTrigger) -> ScriptResult {
        isTestMode = false
        return runScript(script: script, trigger: trigger)
    }

    /// Execute in test mode - key presses are logged instead of executed
    func executeTest(script: Script, trigger: ScriptTrigger) -> (ScriptResult, [String]) {
        isTestMode = true
        testLogs = []
        let result = runScript(script: script, trigger: trigger)
        let logs = testLogs
        isTestMode = false
        testLogs = []
        return (result, logs)
    }

    /// Clear all script state (called on profile switch)
    func clearState() {
        scriptState.removeAll()
    }

    // MARK: - Internal Execution

    private func runScript(script: Script, trigger: ScriptTrigger) -> ScriptResult {
        // Set up trigger context
        var triggerObj: [String: Any] = [
            "button": trigger.button.rawValue,
            "pressType": trigger.pressType,
        ]
        if let holdDuration = trigger.holdDuration {
            triggerObj["holdDuration"] = holdDuration
        }
        context.setObject(triggerObj, forKeyedSubscript: "trigger" as NSString)

        // Set up per-script state namespace (installs state object via JS evaluation)
        installStateObject(for: script.id)

        // Clear any previous exception
        context.exception = nil

        // Set timeout flag - timer fires on global queue so it can set the flag
        // while the script blocks inputQueue
        let timedOut = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        timedOut.initialize(to: false)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + .milliseconds(Int(Config.scriptExecutionTimeoutMs)))
        timer.setEventHandler {
            timedOut.pointee = true
        }
        timer.resume()

        // Execute
        context.evaluateScript(script.source)

        timer.cancel()
        let didTimeout = timedOut.pointee
        timedOut.deinitialize(count: 1)
        timedOut.deallocate()

        // Check for errors
        if let exception = context.exception {
            let errorMessage = exception.toString() ?? "Unknown error"
            logMessage("[Script Error] \(script.name): \(errorMessage)")
            return .error(errorMessage)
        }

        if didTimeout {
            logMessage("[Script Timeout] \(script.name): exceeded \(Config.scriptExecutionTimeoutMs)ms")
            return .error("Script timed out (\(Config.scriptExecutionTimeoutMs)ms limit)")
        }

        return .success(hintOverride: nil)
    }

    // MARK: - API Installation

    private func installAPI() {
        installInputAPI()
        installAppAPI()
        installSystemAPI()
        installFeedbackAPI()
        installLoggingAPI()

        // Set up error handler
        context.exceptionHandler = { [weak self] _, exception in
            if let msg = exception?.toString() {
                self?.logMessage("[JS Exception] \(msg)")
            }
        }
    }

    // MARK: - Input Simulation API

    private func installInputAPI() {
        // press(keyCode) or press(keyCode, {modifiers})
        let press: @convention(block) (Int, JSValue?) -> Void = { [weak self] keyCode, modifiersVal in
            guard let self else { return }
            let flags = self.parseModifiers(modifiersVal)
            if self.isTestMode {
                self.testLogs.append("[press] keyCode=\(keyCode) modifiers=\(self.modifierString(flags))")
            } else {
                self.inputSimulator.pressKey(CGKeyCode(keyCode), modifiers: flags)
            }
        }
        context.setObject(press, forKeyedSubscript: "press" as NSString)

        // hold(keyCode, duration) or hold(keyCode, duration, {modifiers})
        let hold: @convention(block) (Int, Double, JSValue?) -> Void = { [weak self] keyCode, duration, modifiersVal in
            guard let self else { return }
            let flags = self.parseModifiers(modifiersVal)
            if self.isTestMode {
                self.testLogs.append("[hold] keyCode=\(keyCode) duration=\(duration)s modifiers=\(self.modifierString(flags))")
            } else {
                self.inputSimulator.keyDown(CGKeyCode(keyCode), modifiers: flags)
                let durationUs = useconds_t(min(duration, 5.0) * 1_000_000)
                usleep(durationUs)
                self.inputSimulator.keyUp(CGKeyCode(keyCode))
            }
        }
        context.setObject(hold, forKeyedSubscript: "hold" as NSString)

        // click() or click("right") or click("middle")
        let click: @convention(block) (JSValue?) -> Void = { [weak self] typeVal in
            guard let self else { return }
            let clickType = typeVal?.toString() ?? "left"
            let keyCode: CGKeyCode
            switch clickType {
            case "right": keyCode = KeyCodeMapping.mouseRightClick
            case "middle": keyCode = KeyCodeMapping.mouseMiddleClick
            default: keyCode = KeyCodeMapping.mouseLeftClick
            }
            if self.isTestMode {
                self.testLogs.append("[click] \(clickType)")
            } else {
                self.inputSimulator.pressKey(keyCode, modifiers: [])
            }
        }
        context.setObject(click, forKeyedSubscript: "click" as NSString)

        // type("text") - character-by-character typing via CGEvent unicode
        let typeText: @convention(block) (String) -> Void = { [weak self] text in
            guard let self else { return }
            if self.isTestMode {
                self.testLogs.append("[type] \"\(text)\"")
            } else {
                for char in text {
                    var chars = Array(String(char).utf16)
                    let length = chars.count
                    if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                        event.keyboardSetUnicodeString(stringLength: length, unicodeString: &chars)
                        event.flags = []
                        event.post(tap: .cghidEventTap)
                    }
                    usleep(Config.keyPressDuration)
                    if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                        event.keyboardSetUnicodeString(stringLength: length, unicodeString: &chars)
                        event.flags = []
                        event.post(tap: .cghidEventTap)
                    }
                    usleep(Config.typingDelay)
                }
            }
        }
        context.setObject(typeText, forKeyedSubscript: "type" as NSString)

        // paste("text") - via clipboard
        let paste: @convention(block) (String) -> Void = { [weak self] text in
            guard let self else { return }
            if self.isTestMode {
                self.testLogs.append("[paste] \"\(text)\"")
            } else {
                let pasteboard = NSPasteboard.general
                let oldContent = pasteboard.string(forType: .string)
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                // Cmd+V
                self.inputSimulator.pressKey(9, modifiers: .maskCommand)
                // Restore clipboard after brief delay
                usleep(100_000) // 100ms
                if let old = oldContent {
                    pasteboard.clearContents()
                    pasteboard.setString(old, forType: .string)
                }
            }
        }
        context.setObject(paste, forKeyedSubscript: "paste" as NSString)

        // pressKey("space"), pressKey("return"), etc.
        let pressKey: @convention(block) (String, JSValue?) -> Void = { [weak self] name, modifiersVal in
            guard let self else { return }
            guard let keyCode = ScriptEngine.namedKeys[name.lowercased()] else {
                self.logMessage("[Script Warning] Unknown key name: \(name)")
                return
            }
            let flags = self.parseModifiers(modifiersVal)
            if self.isTestMode {
                self.testLogs.append("[pressKey] \"\(name)\" modifiers=\(self.modifierString(flags))")
            } else {
                self.inputSimulator.pressKey(keyCode, modifiers: flags)
            }
        }
        context.setObject(pressKey, forKeyedSubscript: "pressKey" as NSString)
    }

    // MARK: - Application Context API

    private func installAppAPI() {
        // app object with name, bundleId, and is() method
        let appObj = JSValue(newObjectIn: context)!

        // app.name and app.bundleId are computed via getters
        let getName: @convention(block) () -> String = {
            if let app = NSWorkspace.shared.frontmostApplication {
                return app.localizedName ?? ""
            }
            return ""
        }

        let getBundleId: @convention(block) () -> String = {
            if let app = NSWorkspace.shared.frontmostApplication {
                return app.bundleIdentifier ?? ""
            }
            return ""
        }

        // Use defineProperty for getters
        context.evaluateScript("""
        Object.defineProperty(this, '_appGetName', { value: function() { return ''; }, writable: true, configurable: true });
        Object.defineProperty(this, '_appGetBundleId', { value: function() { return ''; }, writable: true, configurable: true });
        """)
        context.setObject(getName, forKeyedSubscript: "_appGetName" as NSString)
        context.setObject(getBundleId, forKeyedSubscript: "_appGetBundleId" as NSString)

        context.evaluateScript("""
        var app = {
            get name() { return _appGetName(); },
            get bundleId() { return _appGetBundleId(); },
            is: function(bid) { return _appGetBundleId() === bid; }
        };
        """)
    }

    // MARK: - System Integration API

    private func installSystemAPI() {
        // clipboard.get() / clipboard.set()
        context.evaluateScript("""
        var clipboard = {
            get: function() { return _clipboardGet(); },
            set: function(text) { _clipboardSet(text); }
        };
        """)

        let clipGet: @convention(block) () -> String = {
            NSPasteboard.general.string(forType: .string) ?? ""
        }
        context.setObject(clipGet, forKeyedSubscript: "_clipboardGet" as NSString)

        let clipSet: @convention(block) (String) -> Void = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        context.setObject(clipSet, forKeyedSubscript: "_clipboardSet" as NSString)

        // shell("command") - synchronous, returns stdout
        let shell: @convention(block) (String) -> String = { [weak self] command in
            guard let self else { return "" }
            if self.isTestMode {
                self.testLogs.append("[shell] \"\(command)\"")
                return "(test mode - shell not executed)"
            }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()

                // 5-second timeout for shell commands
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    group.leave()
                }
                let result = group.wait(timeout: .now() + .seconds(Int(Config.shellCommandTimeoutSeconds)))
                if result == .timedOut {
                    process.terminate()
                    return "(shell command timed out)"
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data.prefix(10240), encoding: .utf8) ?? "" // 10KB limit
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return ""
            }
        }
        context.setObject(shell, forKeyedSubscript: "shell" as NSString)

        // openURL("https://...")
        let openURL: @convention(block) (String) -> Void = { [weak self] urlString in
            if self?.isTestMode == true {
                self?.testLogs.append("[openURL] \"\(urlString)\"")
                return
            }
            if let url = URL(string: urlString) {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        context.setObject(openURL, forKeyedSubscript: "openURL" as NSString)

        // openApp("com.apple.Safari")
        let openApp: @convention(block) (String) -> Void = { [weak self] bundleId in
            if self?.isTestMode == true {
                self?.testLogs.append("[openApp] \"\(bundleId)\"")
                return
            }
            DispatchQueue.main.async {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
        context.setObject(openApp, forKeyedSubscript: "openApp" as NSString)

        // expand("{date} {time} - {app}") - variable expansion
        let expand: @convention(block) (String) -> String = { text in
            VariableExpander.expand(text)
        }
        context.setObject(expand, forKeyedSubscript: "expand" as NSString)

        // delay(seconds)
        let delay: @convention(block) (Double) -> Void = { seconds in
            let clamped = min(max(seconds, 0), 5.0) // Max 5 seconds
            usleep(useconds_t(clamped * 1_000_000))
        }
        context.setObject(delay, forKeyedSubscript: "delay" as NSString)
    }

    // MARK: - Feedback API

    private func installFeedbackAPI() {
        // haptic() or haptic("light") or haptic("heavy")
        let haptic: @convention(block) (JSValue?) -> Void = { [weak self] intensityVal in
            guard let self else { return }
            if self.isTestMode {
                self.testLogs.append("[haptic] \(intensityVal?.toString() ?? "default")")
                return
            }
            let intensityStr = intensityVal?.toString() ?? "default"
            let intensity: Float
            let sharpness: Float
            switch intensityStr {
            case "light":
                intensity = 0.15
                sharpness = 0.8
            case "heavy":
                intensity = 0.6
                sharpness = 0.3
            default:
                intensity = 0.3
                sharpness = 0.6
            }
            self.controllerService?.playHaptic(intensity: intensity, sharpness: sharpness, duration: 0.08)
        }
        context.setObject(haptic, forKeyedSubscript: "haptic" as NSString)

        // notify("message") - floating HUD text
        let notify: @convention(block) (String) -> Void = { [weak self] message in
            if self?.isTestMode == true {
                self?.testLogs.append("[notify] \"\(message)\"")
                return
            }
            DispatchQueue.main.async {
                ActionFeedbackIndicator.shared.show(action: message, type: .singlePress)
            }
        }
        context.setObject(notify, forKeyedSubscript: "notify" as NSString)
    }

    // MARK: - Logging API

    private func installLoggingAPI() {
        let log: @convention(block) (JSValue) -> Void = { [weak self] value in
            let message = value.toString() ?? ""
            self?.logMessage("[Script] \(message)")
            if self?.isTestMode == true {
                self?.testLogs.append(message)
            }
        }
        context.setObject(log, forKeyedSubscript: "log" as NSString)
    }

    // MARK: - Per-Script State

    private func installStateObject(for scriptId: UUID) {
        // Initialize state storage if needed
        if scriptState[scriptId] == nil {
            scriptState[scriptId] = [:]
        }

        // Install state functions that reference this script's namespace
        let stateGet: @convention(block) (String) -> Any? = { [weak self] key in
            return self?.scriptState[scriptId]?[key]
        }

        let stateSet: @convention(block) (String, Any) -> Void = { [weak self] key, value in
            self?.scriptState[scriptId]?[key] = value
        }

        let stateToggle: @convention(block) (String) -> Bool = { [weak self] key in
            let current = self?.scriptState[scriptId]?[key] as? Bool ?? false
            let newValue = !current
            self?.scriptState[scriptId]?[key] = newValue
            return newValue
        }

        context.setObject(stateGet, forKeyedSubscript: "_stateGet" as NSString)
        context.setObject(stateSet, forKeyedSubscript: "_stateSet" as NSString)
        context.setObject(stateToggle, forKeyedSubscript: "_stateToggle" as NSString)

        context.evaluateScript("""
        var state = {
            get: function(key) { return _stateGet(key); },
            set: function(key, value) { _stateSet(key, value); },
            toggle: function(key) { return _stateToggle(key); }
        };
        """)
    }

    // MARK: - Helpers

    private func parseModifiers(_ jsValue: JSValue?) -> CGEventFlags {
        guard let val = jsValue, !val.isUndefined, !val.isNull else { return [] }
        var flags: CGEventFlags = []
        if val.objectForKeyedSubscript("command")?.toBool() == true { flags.insert(.maskCommand) }
        if val.objectForKeyedSubscript("option")?.toBool() == true { flags.insert(.maskAlternate) }
        if val.objectForKeyedSubscript("shift")?.toBool() == true { flags.insert(.maskShift) }
        if val.objectForKeyedSubscript("control")?.toBool() == true { flags.insert(.maskControl) }
        return flags
    }

    private func modifierString(_ flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append("Cmd") }
        if flags.contains(.maskAlternate) { parts.append("Opt") }
        if flags.contains(.maskShift) { parts.append("Shift") }
        if flags.contains(.maskControl) { parts.append("Ctrl") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }

    private func logMessage(_ message: String) {
        NSLog("%@", message)
        if let logService = inputLogService {
            DispatchQueue.main.async {
                logService.log(buttons: [], type: .singlePress, action: message)
            }
        }
    }
}
