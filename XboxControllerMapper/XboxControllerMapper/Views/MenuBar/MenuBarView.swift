import SwiftUI

/// Menu bar popover view
struct MenuBarView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    @State private var mappingEngine: MappingEngine?

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
        .padding(12)
    }

    // MARK: - Quick Controls

    private var quickControlsSection: some View {
        VStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { mappingEngine?.isEnabled ?? true },
                set: { enabled in
                    if enabled {
                        mappingEngine?.enable()
                    } else {
                        mappingEngine?.disable()
                    }
                }
            )) {
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
        HStack {
            Button(action: openMainWindow) {
                HStack(spacing: 4) {
                    Image(systemName: "gear")
                    Text("Settings")
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: quitApp) {
                Text("Quit")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(12)
    }

    // MARK: - Actions

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title.contains("Xbox") || $0.isKeyWindow }) {
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
    MenuBarView()
        .environmentObject(ControllerService())
        .environmentObject(ProfileManager())
}
