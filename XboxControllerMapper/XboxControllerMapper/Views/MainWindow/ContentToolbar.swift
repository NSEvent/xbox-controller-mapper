import SwiftUI

/// Toolbar displayed at the top of the main content area showing connection status,
/// mapping toggle, and settings button.
struct ContentToolbar: View {
    @EnvironmentObject var controllerService: ControllerService
	@EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var mappingEngine: MappingEngine
    @Binding var showingSettingsSheet: Bool
	@Binding var profileSidebarVisible: Bool

    var body: some View {
        HStack {
			ProfileToolbarMenu(profileSidebarVisible: $profileSidebarVisible)

            Spacer()

			if controllerService.isConnected,
			   let mappingSource = controllerService.controllerMappingSource {
				Text(mappingSource)
					.font(.caption2)
					.foregroundColor(.secondary)
			}

			if !controllerService.isConnected {
				Button {
					ControllerSupportDumpService.runInteractiveDump()
				} label: {
					Image(systemName: "doc.text.magnifyingglass")
						.foregroundColor(.secondary)
				}
				.buttonStyle(.plain)
				.hoverableIconButton()
				.help("Controller Support Dump")
				.accessibilityLabel("Controller Support Dump")
			}

            // Connection status — sits on the right, just left of the toggle
            HStack(spacing: 8) {
                Circle()
                    .fill(controllerService.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: (controllerService.isConnected ? Color.green : Color.red).opacity(0.6), radius: 4)

                Text(controllerService.isConnected ? controllerService.controllerName : "No Controller")
                    .font(.caption.bold())
                    .foregroundColor(controllerService.isConnected ? .white : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)

            // Enable/disable toggle
            MappingActiveToggle(isEnabled: $mappingEngine.isEnabled)

            Button {
                showingSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .hoverableIconButton()
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // Transparent toolbar to let glass show through
    }
}

private struct ProfileToolbarMenu: View {
	@EnvironmentObject var profileManager: ProfileManager
	@Binding var profileSidebarVisible: Bool

	var body: some View {
		Menu {
			ForEach(profileManager.profiles) { profile in
				Button {
					profileManager.setActiveProfile(profile)
				} label: {
					Label(
						profile.name,
						systemImage: profile.id == profileManager.activeProfileId ? "checkmark" : (profile.icon ?? "gamecontroller")
					)
				}
			}

			Divider()

			Button {
				profileSidebarVisible.toggle()
			} label: {
				Label(
					profileSidebarVisible ? "Hide Profile Sidebar" : "Show Profile Sidebar",
					systemImage: "sidebar.leading"
				)
			}
			.keyboardShortcut("b", modifiers: .command)
		} label: {
			Label(profileManager.activeProfile?.name ?? "Profiles", systemImage: profileManager.activeProfile?.icon ?? "rectangle.stack")
				.font(.caption.bold())
				.lineLimit(1)
				.padding(.horizontal, 12)
				.padding(.vertical, 6)
				.background(Color.black.opacity(0.3))
				.cornerRadius(12)
				.overlay(
					RoundedRectangle(cornerRadius: 12)
						.stroke(Color.white.opacity(0.1), lineWidth: 1)
				)
		}
		.menuStyle(.borderlessButton)
		.help("Profiles")
		.accessibilityLabel("Profiles")
		.fixedSize()
	}
}
