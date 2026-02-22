import Foundation
import CoreGraphics
import AppKit
import Carbon.HIToolbox

/// Executes macro sequences by dispatching individual steps to the appropriate services.
///
/// Extracted from InputSimulator to separate concerns:
/// - InputSimulator handles low-level key/mouse event posting (including typeText)
/// - MacroExecutor orchestrates multi-step macro sequences
/// - SystemCommandExecutor handles shell/webhook/OBS steps directly (no closure callback)
class MacroExecutor: @unchecked Sendable {
    private let inputSimulator: InputSimulatorProtocol
    private let systemCommandExecutor: SystemCommandExecutor
    private let executionQueue: DispatchQueue

    init(
        inputSimulator: InputSimulatorProtocol,
        systemCommandExecutor: SystemCommandExecutor,
        executionQueue: DispatchQueue = DispatchQueue(label: "com.controllerkeys.macro", qos: .userInteractive)
    ) {
        self.inputSimulator = inputSimulator
        self.systemCommandExecutor = systemCommandExecutor
        self.executionQueue = executionQueue
    }

    func execute(_ macro: Macro) {
        executionQueue.async { [weak self] in
            guard let self = self else { return }

            for step in macro.steps {
                switch step {
                case .press(let mapping):
                    self.pressKeyMapping(mapping)

                case .hold(let mapping, let duration):
                    self.holdKeyMapping(mapping, duration: duration)

                case .delay(let duration):
                    usleep(useconds_t(duration * 1_000_000))

                case .typeText(let text, let speed, let pressEnter):
                    self.inputSimulator.typeText(text, speed: speed, pressEnter: pressEnter)

                case .openApp(let bundleIdentifier, let newWindow):
                    self.openApplication(bundleIdentifier: bundleIdentifier, newWindow: newWindow)

                case .openLink(let url):
                    self.openURL(url)

                case .shellCommand(let command, let inTerminal):
                    let systemCommand = SystemCommand.shellCommand(command: command, inTerminal: inTerminal)
                    self.systemCommandExecutor.execute(systemCommand)

                case .webhook(let url, let method, let headers, let body):
                    let systemCommand = SystemCommand.httpRequest(url: url, method: method, headers: headers, body: body)
                    self.systemCommandExecutor.execute(systemCommand)

                case .obsWebSocket(let url, let password, let requestType, let requestData):
                    let systemCommand = SystemCommand.obsWebSocket(url: url, password: password, requestType: requestType, requestData: requestData)
                    self.systemCommandExecutor.execute(systemCommand)
                }
            }
        }
    }

    // MARK: - Step Implementations

    private func pressKeyMapping(_ mapping: KeyMapping) {
        if let keyCode = mapping.keyCode {
            inputSimulator.pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        } else if mapping.modifiers.hasAny {
            let flags = mapping.modifiers.cgEventFlags
            inputSimulator.holdModifier(flags)
            usleep(Config.keyPressDuration)
            inputSimulator.releaseModifier(flags)
        }
    }

    private func holdKeyMapping(_ mapping: KeyMapping, duration: TimeInterval) {
        if let keyCode = mapping.keyCode {
            inputSimulator.keyDown(keyCode, modifiers: mapping.modifiers.cgEventFlags)
            usleep(useconds_t(duration * 1_000_000))
            inputSimulator.keyUp(keyCode)
        } else if mapping.modifiers.hasAny {
            let flags = mapping.modifiers.cgEventFlags
            inputSimulator.holdModifier(flags)
            usleep(useconds_t(duration * 1_000_000))
            inputSimulator.releaseModifier(flags)
        }
    }

    private func openApplication(bundleIdentifier: String, newWindow: Bool) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSLog("[Macro] App not found: \(bundleIdentifier)")
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        let config = NSWorkspace.OpenConfiguration()

        DispatchQueue.main.async {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                if let error = error {
                    NSLog("[Macro] Failed to open app: \(error.localizedDescription)")
                }
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + 3.0)

        if newWindow {
            usleep(300_000)
            inputSimulator.pressKey(CGKeyCode(kVK_ANSI_N), modifiers: .maskCommand)
        }
    }

    private func openURL(_ urlString: String) {
        var resolved = urlString
        if !resolved.contains("://") {
            resolved = "https://" + resolved
        }
        guard let url = URL(string: resolved) else {
            NSLog("[Macro] Invalid URL: \(urlString)")
            return
        }
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            NSLog("[Macro] openURL blocked non-http(s) scheme: %@", urlString)
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)

        usleep(200_000)
    }
}
