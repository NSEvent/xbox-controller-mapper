import Combine
import GameController
import SwiftUI

extension Notification.Name {
    static let hideFromDockPreferenceDidChange = Notification.Name("hideFromDockPreferenceDidChange")
}

@MainActor
final class DockMenuPreferenceObserver: ObservableObject {
    @Published private(set) var hideFromDock: Bool

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.hideFromDock = defaults.bool(forKey: DockVisibilityController.hideFromDockDefaultsKey)

        observers.append(
            notificationCenter.addObserver(
                forName: .hideFromDockPreferenceDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
        )

        observers.append(
            notificationCenter.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
        )
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    private func refresh() {
        hideFromDock = defaults.bool(forKey: DockVisibilityController.hideFromDockDefaultsKey)
    }
}

/// Menu bar popover view
struct MenuBarView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var mappingEngine: MappingEngine
    @EnvironmentObject var inputLogService: InputLogService

    @Environment(\.openWindow) private var openWindow

    @StateObject private var dockPreference = DockMenuPreferenceObserver()
    @State private var streamOverlayEnabled: Bool = StreamOverlayManager.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            // Connection Status
            connectionStatusSection

            Divider()

            // Quick Controls
            quickControlsSection

            Divider()

            // Profile Selection
            profileSection

            Divider()

            // Footer
            footerSection
        }
        .frame(width: 280)
    }

    // MARK: - Connection Status

    private var connectionStatusSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: controllerService.isConnected ? "gamecontroller.fill" : "gamecontroller")
                    .font(.title2)
                    .foregroundColor(controllerService.isConnected ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(controllerService.isConnected ? "Connected" : "No Controller")
                        .font(.headline)

                    if controllerService.isConnected {
                        Text(controllerService.controllerName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Connect via Bluetooth")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

				if controllerService.isConnected {
					MenuBarBatteryBadge(
						level: controllerService.batteryLevel,
						state: controllerService.batteryState
					)
				}
            }

            // Accessibility permission status
            if !AppDelegate.isAccessibilityEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Accessibility permission required for global input")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)

                Button("Open System Settings") {
                    openAccessibilitySettings()
                }
                .font(.caption)
            }
        }
        .padding(12)
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Quick Controls

    private var quickControlsSection: some View {
        VStack(spacing: 8) {
            Toggle(isOn: $mappingEngine.isEnabled) {
                HStack {
                    Image(systemName: "keyboard")
                    Text("Mapping Enabled")
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: $streamOverlayEnabled) {
                HStack {
                    Image(systemName: "play.rectangle.on.rectangle")
                    Text("Stream Overlay")
                }
            }
            .toggleStyle(.switch)
            .onChange(of: streamOverlayEnabled) { _, newValue in
                if newValue {
                    StreamOverlayManager.shared.show(
                        controllerService: controllerService,
                        inputLogService: inputLogService
                    )
                } else {
                    StreamOverlayManager.shared.hide()
                }
            }
        }
        .padding(12)
    }

    // MARK: - Profile Selection

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(profileManager.profiles) { profile in
                ProfileRow(
                    profile: profile,
                    isSelected: profile.id == profileManager.activeProfileId,
                    onSelect: {
                        profileManager.setActiveProfile(profile)
                    }
                )
            }
        }
        .padding(12)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            if dockPreference.hideFromDock {
                Button(action: openMainWindow) {
                    HStack(spacing: 4) {
                        Image(systemName: "macwindow")
                        Text("Open Window")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            Button(action: openMainWindow) {
                HStack(spacing: 4) {
                    Image(systemName: "gear")
                    Text("Settings")
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button(action: quitApp) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                    Text("Quit ControllerKeys")
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Version and copyright
            HStack {
                Text("v\(appVersion)")
                Text("•")
                Text("© 2026 Kevin Tang. All rights reserved.")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(12)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Actions

    private func openMainWindow() {
        // Promote the activation policy first so the dock icon appears as the
        // window comes up, and hold that promotion while SwiftUI opens the
        // Window scene.
        DockVisibilityController.shared.promoteForOpeningMainWindow()
        // SwiftUI's openWindow reliably opens (or reactivates) the Window scene
        // by id, even after the user closed it with the red traffic light.
        // The previous AppKit fallback used a non-existent selector and only
        // worked while the window was still in NSApp.windows.
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func quitApp() {
        NSApp.terminate(nil)
    }
}

private struct MenuBarBatteryBadge: View {
    let level: Float
    let state: GCDeviceBattery.State

    private var percentage: Int? {
		ControllerBatteryDisplayPolicy.percentage(level: level, state: state)
    }

    private var batterySymbolName: String {
		guard let percentage else { return "battery.0percent" }
		if percentage >= 88 { return "battery.100percent" }
		if percentage >= 63 { return "battery.75percent" }
		if percentage >= 38 { return "battery.50percent" }
		if percentage >= 13 { return "battery.25percent" }
		return "battery.0percent"
    }

    private var tint: Color {
		guard let percentage else { return .secondary }
		if state == .charging { return .green }
		if percentage > 60 { return .green }
		if percentage > 20 { return .orange }
		return .red
    }

    var body: some View {
		HStack(spacing: 4) {
			if state == .charging, percentage != nil {
				Image(systemName: "bolt.fill")
					.font(.system(size: 9, weight: .bold))
					.foregroundColor(.yellow)
			}

			Image(systemName: batterySymbolName)
				.font(.system(size: 12, weight: .semibold))

			Text(percentage.map { "\($0)%" } ?? "--")
				.font(.caption.weight(.semibold))
				.monospacedDigit()
		}
		.foregroundColor(tint)
		.padding(.horizontal, 7)
		.padding(.vertical, 4)
		.background(Color.primary.opacity(0.07))
		.cornerRadius(6)
		.help(percentage.map { "Battery: \($0)%" } ?? "Battery unavailable")
		.accessibilityLabel(percentage.map { "Battery: \($0) percent" } ?? "Battery unavailable")
    }
}

// MARK: - Profile Row

struct ProfileRow: View {
    let profile: Profile
    let isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(profile.name)
                    .foregroundColor(.primary)

                if let iconName = profile.icon {
                    Image(systemName: iconName)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }

                Spacer()

                if profile.isDefault {
                    Text("Default")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let controllerService = ControllerService()
    let profileManager = ProfileManager()
    let appMonitor = AppMonitor()
    let inputLogService = InputLogService()
    let mappingEngine = MappingEngine(
        controllerService: controllerService,
        profileManager: profileManager,
        appMonitor: appMonitor,
        inputLogService: inputLogService
    )

    return MenuBarView()
        .environmentObject(controllerService)
        .environmentObject(profileManager)
        .environmentObject(mappingEngine)
        .environmentObject(inputLogService)
}
