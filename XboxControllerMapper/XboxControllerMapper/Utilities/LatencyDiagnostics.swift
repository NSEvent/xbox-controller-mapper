import Foundation

enum LatencyDiagnostics {
    private static let defaultsKey = "controllerkeysLatencyDiagnostics"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func mark(_ event: String) {
        guard isEnabled else { return }
        NSLog("[Latency] %.6f %@", CFAbsoluteTimeGetCurrent(), event)
    }
}
