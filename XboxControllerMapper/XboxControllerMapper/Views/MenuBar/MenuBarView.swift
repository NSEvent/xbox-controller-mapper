import SwiftUI

/// Menu bar popover view
struct MenuBarView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var mappingEngine: MappingEngine

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
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title.contains("ControllerKeys") || $0.isKeyWindow }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Open new window
            NSApp.sendAction(Selector(("showMainWindow:")), to: nil, from: nil)
        }
    }

    private func quitApp() {
        NSApp.terminate(nil)
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
    let mappingEngine = MappingEngine(
        controllerService: controllerService,
        profileManager: profileManager,
        appMonitor: appMonitor
    )

    return MenuBarView()
        .environmentObject(controllerService)
        .environmentObject(profileManager)
        .environmentObject(mappingEngine)
}
