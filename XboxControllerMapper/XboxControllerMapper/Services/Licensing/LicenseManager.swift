import Foundation
import SwiftUI
import Combine

/// Owns the trial / license state for the app.
///
/// - The 14-day trial clock is anchored in the **login keychain** (not
///   UserDefaults), so deleting + reinstalling the app does not grant a fresh
///   trial. (A determined user can still build from source — that segment was
///   never the paying one.)
/// - A Gumroad license key, once verified, is cached in the keychain and the
///   app treats itself as licensed offline thereafter (offline grace).
/// - When the trial expires with no license, `isActive` becomes false; the app
///   forces controller mapping off and the UI nudges the user to license.
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    enum Status: Equatable {
        case licensed
        case trial(daysRemaining: Int)
        case expired
    }

    @Published private(set) var status: Status = .trial(daysRemaining: trialLengthDays)

    /// True while the app is fully usable (licensed or within the trial).
    var isActive: Bool {
        if case .expired = status { return false }
        return true
    }

    var isLicensed: Bool {
        if case .licensed = status { return true }
        return false
    }

    var trialDaysRemaining: Int {
        if case let .trial(days) = status { return days }
        return 0
    }

    /// Compact status string for anonymous telemetry.
    var telemetryStatus: String { Self.telemetryString(status) }

    static func telemetryString(_ status: Status) -> String {
        switch status {
        case .licensed: return "licensed"
        case .trial: return "trial"
        case .expired: return "expired"
        }
    }

    var storedLicenseKey: String? {
        KeychainService.retrievePassword(key: Keys.licenseKey, service: keychainService)
    }

    // MARK: - Config

    static let trialLengthDays = 14

    /// Gumroad product ID (from the product's settings → Advanced). Used by
    /// the License Verification API.
    static let productID = "9AsXgsuZVzxgNYfoVcFW1A=="

    private let keychainService = "com.controllerkeys.license"
    private enum Keys {
        static let trialStart = "trialStart"
        static let licenseKey = "licenseKey"
        static let licensedConfirmed = "licensedConfirmed"
    }

    private let isoFormatter = ISO8601DateFormatter()
    private var clockTimer: Timer?
    private var enforcementCancellable: AnyCancellable?

    private init() {
        refresh()
        // A long-running app should notice the trial expiring at a day
        // boundary without needing a relaunch.
        clockTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Runs `disableMapping` immediately if the trial is already expired, and
    /// again whenever it transitions to expired — so mapping stops even with no
    /// window open. Called once at app startup.
    func enforce(disableMapping: @escaping () -> Void) {
        enforcementCancellable = $status.sink { status in
            if case .expired = status {
                disableMapping()
            }
            // Report trial_expired / license_valid once per transition (dedup'd
            // inside TelemetryService) so expiry is caught even in a long-running
            // session that never relaunches.
            TelemetryService.shared.reportStatusTransition(Self.telemetryString(status))
        }
    }

    // MARK: - Status

    /// Demo/QA override: `--demo-license expired|trial<N>|licensed` forces a
    /// status so the trial/expired/licensed UI can be previewed deterministically
    /// (e.g. to demo the expiry flow or shoot marketing). `licensed` is honored
    /// only in screenshot mode so it can never be a real-build bypass; the
    /// restrictive states are harmless to allow anywhere.
    private static var demoForcedStatus: Status? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--demo-license"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "expired":
            return .expired
        case let value where value.hasPrefix("trial"):
            return .trial(daysRemaining: Int(value.dropFirst("trial".count)) ?? trialLengthDays)
        case "licensed":
            return AppRuntime.screenshotVariant != nil ? .licensed : nil
        default:
            return nil
        }
    }

    /// Recomputes `status` from the keychain (license first, then trial clock).
    func refresh() {
        if let forced = Self.demoForcedStatus {
            status = forced
            return
        }
#if DEV_BYPASS_LICENSE
        // Local `make install` dev/contributor builds compile in this flag so
        // the developer isn't trial-gated. The notarized release pipeline
        // (Scripts/sign-and-notarize.sh) never defines it, so shipped binaries
        // stay gated and contain no bypass code path at all.
        status = .licensed
        return
#endif
        // A previously-verified license wins, and stays valid offline.
        if storedLicenseKey != nil,
           KeychainService.retrievePassword(key: Keys.licensedConfirmed, service: keychainService) == "1" {
            status = .licensed
            return
        }

        let start = ensureTrialStart()
        let elapsedDays = Int(floor(Date().timeIntervalSince(start) / 86_400))
        let remaining = Self.trialLengthDays - elapsedDays
        status = remaining > 0 ? .trial(daysRemaining: remaining) : .expired
    }

    /// Returns the trial start date, creating (and persisting) it on first launch.
    @discardableResult
    private func ensureTrialStart() -> Date {
        if let stored = KeychainService.retrievePassword(key: Keys.trialStart, service: keychainService),
           let date = isoFormatter.date(from: stored) {
            return date
        }
        let now = Date()
        KeychainService.storePassword(isoFormatter.string(from: now), key: Keys.trialStart, service: keychainService)
        return now
    }

    // MARK: - License verification

    struct VerifyResult {
        let success: Bool
        let message: String
    }

    /// Verifies a Gumroad license key against the Gumroad License API and, on
    /// success, caches it so the app is licensed (including offline) going
    /// forward.
    func verify(key rawKey: String) async -> VerifyResult {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return VerifyResult(success: false, message: "Enter your license key.")
        }

        guard let url = URL(string: "https://api.gumroad.com/v2/licenses/verify") else {
            return VerifyResult(success: false, message: "Internal error building the request.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // application/x-www-form-urlencoded: percent-encode everything but the
        // unreserved set, so the product_id's trailing "==" survives intact.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func formEncode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        }
        let form = [
            "product_id=\(formEncode(Self.productID))",
            "license_key=\(formEncode(key))",
            // Don't burn an activation just for a verify; only count on activate.
            "increment_uses_count=false",
        ].joined(separator: "&")
        request.httpBody = form.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return VerifyResult(success: false, message: "No response from Gumroad.")
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            // Gumroad returns 404 when the key/product isn't found.
            guard http.statusCode == 200, (json?["success"] as? Bool) == true else {
                let message = (json?["message"] as? String) ?? "That license key wasn't recognized."
                return VerifyResult(success: false, message: message)
            }

            if let purchase = json?["purchase"] as? [String: Any] {
                let refunded = (purchase["refunded"] as? Bool) ?? false
                let disputed = (purchase["disputed"] as? Bool) ?? false
                let chargebacked = (purchase["chargebacked"] as? Bool) ?? false
                if refunded || disputed || chargebacked {
                    return VerifyResult(
                        success: false,
                        message: "This license is no longer valid (the purchase was refunded or disputed)."
                    )
                }
            }

            KeychainService.storePassword(key, key: Keys.licenseKey, service: keychainService)
            KeychainService.storePassword("1", key: Keys.licensedConfirmed, service: keychainService)
            status = .licensed
            // Tier 3 join: report activation with the Gumroad sale_id so the
            // backend can tie this anonymous install to its purchase.
            let saleID = (json?["purchase"] as? [String: Any])?["sale_id"] as? String
            TelemetryService.shared.licenseActivated(saleID: saleID)
            return VerifyResult(success: true, message: "License activated — thank you for your support!")
        } catch {
            return VerifyResult(
                success: false,
                message: "Couldn't reach Gumroad. Check your connection and try again."
            )
        }
    }

    /// Removes the stored license (used for testing / "deactivate this Mac").
    func clearLicense() {
        KeychainService.deletePassword(key: Keys.licenseKey, service: keychainService)
        KeychainService.deletePassword(key: Keys.licensedConfirmed, service: keychainService)
        refresh()
    }

#if DEBUG
    /// Backdates the trial start so the trial shows `daysRemaining` left
    /// (use 0 or negative to force the expired state). Debug builds only.
    func debugSetTrialDaysRemaining(_ daysRemaining: Int) {
        clearLicense()
        let offsetDays = Self.trialLengthDays - daysRemaining
        let backdated = Date().addingTimeInterval(-Double(offsetDays) * 86_400)
        KeychainService.storePassword(isoFormatter.string(from: backdated), key: Keys.trialStart, service: keychainService)
        refresh()
    }
#endif
}
