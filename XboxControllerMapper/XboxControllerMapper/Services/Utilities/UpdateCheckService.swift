import Foundation
import AppKit

/// Checks GitHub Releases for newer versions and shows an in-app alert.
/// Users can skip a specific version or snooze for 3 days.
@MainActor
final class UpdateCheckService {

    /// Check for updates, respecting throttle/snooze/skip rules.
    /// Called once on app launch from ServiceContainer.
    func checkForUpdates() {
        // Delay a few seconds so the app finishes launching first
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await self?.performCheck()
        }
    }

    // MARK: - Core Logic

    private func performCheck() async {
        let defaults = UserDefaults.standard

        // Throttle: skip if checked within the last 24 hours
        if let lastChecked = defaults.object(forKey: Config.updateCheckLastCheckedKey) as? Date,
           Date().timeIntervalSince(lastChecked) < Config.updateCheckInterval {
            return
        }

        // Snooze: skip if "remind later" was tapped within the last 3 days
        if let remindDate = defaults.object(forKey: Config.updateCheckRemindLaterDateKey) as? Date,
           Date().timeIntervalSince(remindDate) < Config.updateCheckRemindLaterInterval {
            return
        }

        guard let release = await fetchLatestRelease() else { return }

        // Record that we checked
        defaults.set(Date(), forKey: Config.updateCheckLastCheckedKey)

        let remoteVersion = release.version
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }

        // Compare versions
        guard isVersion(remoteVersion, greaterThan: currentVersion) else { return }

        // Skip: user chose to skip this specific version
        if let skipped = defaults.string(forKey: Config.updateCheckSkippedVersionKey),
           skipped == remoteVersion {
            return
        }

        showUpdateAlert(version: remoteVersion)
    }

    // MARK: - GitHub API

    private struct GitHubRelease {
        let version: String
    }

    private func fetchLatestRelease() async -> GitHubRelease? {
        let urlString = "https://api.github.com/repos/\(Config.updateCheckGitHubRepo)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return nil }

            // Strip leading "v" prefix
            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            return GitHubRelease(version: version)
        } catch {
            NSLog("[UpdateCheck] Failed to fetch latest release: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Version Comparison

    /// Semantic version comparison: returns true if `a` is strictly greater than `b`.
    private func isVersion(_ a: String, greaterThan b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }

        let count = max(partsA.count, partsB.count)
        for i in 0..<count {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va > vb { return true }
            if va < vb { return false }
        }
        return false
    }

    // MARK: - Alert

    private func showUpdateAlert(version: String) {
        // Bring app to front so the alert is visible
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "ControllerKeys v\(version) Available"
        alert.informativeText = "A new version is available. Would you like to download it from Gumroad?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")

        let response = alert.runModal()
        let defaults = UserDefaults.standard

        switch response {
        case .alertFirstButtonReturn:
            // Download Update — open Gumroad
            if let url = URL(string: Config.updateCheckGumroadURL) {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            // Remind Me Later — snooze for 3 days
            defaults.set(Date(), forKey: Config.updateCheckRemindLaterDateKey)
        case .alertThirdButtonReturn:
            // Skip This Version
            defaults.set(version, forKey: Config.updateCheckSkippedVersionKey)
        default:
            break
        }
    }
}
