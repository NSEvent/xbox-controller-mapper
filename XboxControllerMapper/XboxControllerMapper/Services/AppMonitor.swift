import Foundation
import AppKit
import Combine

/// Monitors the frontmost application for per-app mapping overrides
@MainActor
class AppMonitor: ObservableObject {
    @Published var frontmostApp: NSRunningApplication?
    @Published var frontmostBundleId: String?
    @Published var frontmostAppName: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupNotifications()
        updateFrontmostApp()
    }

    private func setupNotifications() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.setFrontmostApp(app)
                }
            }
            .store(in: &cancellables)
    }

    private func updateFrontmostApp() {
        if let app = NSWorkspace.shared.frontmostApplication {
            setFrontmostApp(app)
        }
    }

    private func setFrontmostApp(_ app: NSRunningApplication) {
        frontmostApp = app
        frontmostBundleId = app.bundleIdentifier
        frontmostAppName = app.localizedName
    }

    /// Gets a list of all running applications (for UI picker)
    var runningApplications: [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppInfo? in
                guard let bundleId = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                return AppInfo(
                    bundleIdentifier: bundleId,
                    name: name,
                    icon: app.icon
                )
            }
            .sorted { $0.name < $1.name }
    }

    /// Gets a list of installed applications (for UI picker)
    var installedApplications: [AppInfo] {
        let appDirectories = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications"
        ]

        var apps: [AppInfo] = []

        for directory in appDirectories {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                continue
            }

            for item in contents where item.hasSuffix(".app") {
                let path = (directory as NSString).appendingPathComponent(item)
                if let bundle = Bundle(path: path),
                   let bundleId = bundle.bundleIdentifier {
                    let name = (item as NSString).deletingPathExtension
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    apps.append(AppInfo(bundleIdentifier: bundleId, name: name, icon: icon))
                }
            }
        }

        return apps.sorted { $0.name < $1.name }
    }

    /// Gets app info for a bundle identifier
    func appInfo(for bundleId: String) -> AppInfo? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let name = url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return AppInfo(bundleIdentifier: bundleId, name: name, icon: icon)
        }
        return nil
    }
}

/// Information about an application
struct AppInfo: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String
    let icon: NSImage?

    var id: String { bundleIdentifier }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}
