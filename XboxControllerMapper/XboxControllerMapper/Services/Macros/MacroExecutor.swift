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
        // Use Task to enable async/await for steps that need main-thread work
        // (openApp, openURL), eliminating semaphore-based deadlock risk.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            for step in macro.steps {
                switch step {
                case .press(let mapping):
                    self.pressKeyMapping(mapping)

                case .hold(let mapping, let duration):
                    self.holdKeyMapping(mapping, duration: duration)

                case .delay(let duration):
                    // Use Task.sleep for delays to avoid blocking a GCD thread
                    try? await Task.sleep(nanoseconds: UInt64(min(duration * 1_000_000_000, Double(UInt64.max / 2))))

                case .typeText(let text, let speed, let pressEnter):
                    self.inputSimulator.typeText(text, speed: speed, pressEnter: pressEnter)

                case .openApp(let bundleIdentifier, let newWindow):
                    await self.openApplicationAsync(bundleIdentifier: bundleIdentifier, newWindow: newWindow)

                case .openLink(let url):
                    await self.openURLAsync(url)

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
            usleep(useconds_t(min(duration * 1_000_000, Double(UInt32.max))))
            inputSimulator.keyUp(keyCode)
        } else if mapping.modifiers.hasAny {
            let flags = mapping.modifiers.cgEventFlags
            inputSimulator.holdModifier(flags)
            usleep(useconds_t(min(duration * 1_000_000, Double(UInt32.max))))
            inputSimulator.releaseModifier(flags)
        }
    }

    @MainActor
    private func openApplicationAsync(bundleIdentifier: String, newWindow: Bool) async {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSLog("[Macro] App not found: \(bundleIdentifier)")
            return
        }

        let config = NSWorkspace.OpenConfiguration()

        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        } catch {
            NSLog("[Macro] Failed to open app: \(error.localizedDescription)")
        }

        if newWindow {
            try? await Task.sleep(nanoseconds: 300_000_000)
            inputSimulator.pressKey(CGKeyCode(kVK_ANSI_N), modifiers: .maskCommand)
        }
    }

    @MainActor
    private func openURLAsync(_ urlString: String) async {
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

        NSWorkspace.shared.open(url)

        try? await Task.sleep(nanoseconds: 200_000_000)
    }
}
