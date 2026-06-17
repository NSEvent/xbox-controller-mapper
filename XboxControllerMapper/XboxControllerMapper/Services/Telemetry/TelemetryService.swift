import Foundation

/// Anonymous, opt-out usage telemetry.
///
/// ControllerKeys used to be downloaded through Gumroad, which gave rich
/// per-download data. Now the app is distributed free via GitHub Releases and
/// Homebrew, so that visibility is gone. This service posts small, anonymous
/// JSON events to the ControllerKeys analytics Worker so we can see active
/// installs, version adoption, rough geography, and trial → license conversion.
///
/// Privacy:
/// - A random install UUID (no account, no name, no email) is stored in
///   `UserDefaults` and wiped on a clean uninstall (`brew uninstall --zap` or
///   trashing the prefs). It is the only identifier sent.
/// - Country is derived server-side from the request IP and is **never** sent by
///   the app; the server stores only a salted hash of the IP, not the IP.
/// - Opt out any time with Settings → "Share Anonymous Usage Data"
///   (the `telemetryEnabled` default; on by default).
///
/// Every call is fire-and-forget: it never blocks the UI and never surfaces an
/// error. If the network or backend is down, events are simply dropped.
final class TelemetryService {
    static let shared = TelemetryService()

    private let endpoint = URL(string: "https://analytics.kevintang.app/controllerkeys/e")!
    private let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "telemetryEnabled"
        static let installID = "telemetryInstallID"
        static let installDate = "telemetryInstallDate"
        static let lastLaunchDay = "telemetryLastLaunchDay"
        static let didReportInstall = "telemetryDidReportInstall"
        static let lastReportedStatus = "telemetryLastReportedStatus"
    }

    private init() {
        defaults.register(defaults: [Key.enabled: true])
    }

    /// Honors the Settings opt-out toggle.
    var isEnabled: Bool { defaults.bool(forKey: Key.enabled) }

    // MARK: - Anonymous identity

    private var installID: String {
        if let existing = defaults.string(forKey: Key.installID) { return existing }
        let id = UUID().uuidString
        defaults.set(id, forKey: Key.installID)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.installDate)
        return id
    }

    /// Days since first launch (rough trial-timeline bucket).
    private var trialDay: Int {
        let t0 = defaults.double(forKey: Key.installDate)
        guard t0 > 0 else { return 0 }
        return max(0, Int((Date().timeIntervalSince1970 - t0) / 86_400))
    }

    // MARK: - Public API

    /// Call once at app launch. Sends `install` the first time ever, then a
    /// day-throttled `launch` heartbeat, then reports any license-state change.
    func appLaunched(status: String) {
        guard isEnabled else { return }

        if !defaults.bool(forKey: Key.didReportInstall) {
            defaults.set(true, forKey: Key.didReportInstall)
            send(event: "install", status: status)
        }

        let today = Self.dayStamp()
        if defaults.string(forKey: Key.lastLaunchDay) != today {
            defaults.set(today, forKey: Key.lastLaunchDay)
            send(event: "launch", status: status)
        }

        reportStatusTransition(status)
    }

    /// Fire-and-forget activation event carrying the Gumroad `sale_id` so the
    /// backend can join this install to its purchase (no PII in the join).
    func licenseActivated(saleID: String?) {
        guard isEnabled else { return }
        send(event: "license_activated", status: "licensed", saleID: saleID)
    }

    /// Emits `trial_expired` / `license_valid` exactly once per transition.
    /// Safe to call repeatedly — it dedups on the last reported status.
    func reportStatusTransition(_ status: String) {
        guard isEnabled else { return }
        guard defaults.string(forKey: Key.lastReportedStatus) != status else { return }
        defaults.set(status, forKey: Key.lastReportedStatus)
        switch status {
        case "expired": send(event: "trial_expired", status: status)
        case "licensed": send(event: "license_valid", status: status)
        default: break
        }
    }

    // MARK: - Payload + send

    private func send(event: String, status: String, saleID: String? = nil) {
        // Never phone home from tests or screenshot captures.
        guard !AppRuntime.isRunningTests, AppRuntime.screenshotVariant == nil else { return }

        var payload: [String: Any] = [
            "event": event,
            "install_id": installID,
            "app_version": Self.appVersion,
            "build": Self.build,
            "os_version": Self.osVersion,
            "arch": Self.arch,
            "locale": Locale.current.identifier,
            "status": status,
            "trial_day": trialDay,
            "channel": Self.channel,
        ]
        if let saleID, !saleID.isEmpty { payload["sale_id"] = saleID }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }

    // MARK: - Environment

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    private static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Architecture of the running slice (Apple Silicon vs Intel adoption).
    private static var arch: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    /// Best-effort install-channel detection: if a Homebrew Caskroom entry for
    /// our cask token exists, the app was installed via `brew install`. The app
    /// isn't sandboxed, so it can read these paths; a false read just yields
    /// "direct".
    private static var channel: String {
        let fm = FileManager.default
        for prefix in ["/opt/homebrew", "/usr/local"] {
            if fm.fileExists(atPath: "\(prefix)/Caskroom/controllerkeys") { return "homebrew" }
        }
        return "direct"
    }

    private static func dayStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
