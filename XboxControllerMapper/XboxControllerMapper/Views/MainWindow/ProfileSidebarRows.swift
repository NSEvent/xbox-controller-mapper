import SwiftUI
import AppKit

struct ProfileListRow: View {
	@EnvironmentObject var appMonitor: AppMonitor

	let profile: Profile

	private var configurationCounts: ProfileConfigurationCounts {
		ConfigurationOverviewBuilder.counts(for: profile)
	}

	var body: some View {
		HStack {
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text(profile.name)
						.font(.system(size: 13, weight: .medium))
						.foregroundColor(.white)
						.lineLimit(1)

					LinkedProfileAppIcons(bundleIdentifiers: profile.linkedApps)
				}

				Text(configurationCounts.primarySummary)
					.font(.system(size: 11))
					.foregroundColor(.white.opacity(0.6))

				if let secondarySummary = configurationCounts.secondarySummary {
					Text(secondarySummary)
						.font(.system(size: 10))
						.foregroundColor(.white.opacity(0.45))
						.lineLimit(1)
				}
			}

			Spacer()

			HStack(spacing: 7) {
				if let iconName = profile.icon {
					ProfileStatusBadge(
						systemName: iconName,
						color: .accentColor,
						helpText: "Profile icon"
					)
				}

				if profile.inputLatencyMode == .realtime {
					ProfileStatusBadge(
						systemName: "bolt.fill",
						color: .orange,
						helpText: "Realtime input latency"
					)
				}

				if !profile.linkedControllers.isEmpty {
					ProfileStatusBadge(
						systemName: "gamecontroller.fill",
						color: .accentColor,
						helpText: "Linked controller"
					)
				}

		if profile.inheritedOnScreenKeyboardProfileId != nil {
		    ProfileStatusBadge(
			systemName: "keyboard",
			color: .accentColor,
			helpText: "Shared keyboard settings"
		    )
		}

				if profile.isDefault {
					ProfileStatusBadge(
						systemName: "star.fill",
						color: .yellow,
						helpText: "Default profile"
					)
				}
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
	}
}

private struct LinkedProfileAppIcons: View {
	@EnvironmentObject var appMonitor: AppMonitor

	let bundleIdentifiers: [String]

	private var visibleBundleIds: [String] {
		Array(bundleIdentifiers.prefix(4))
	}

	private var remainingCount: Int {
		max(0, bundleIdentifiers.count - visibleBundleIds.count)
	}

	var body: some View {
		if !bundleIdentifiers.isEmpty {
			HStack(spacing: 3) {
				ForEach(visibleBundleIds, id: \.self) { bundleId in
					LinkedProfileAppIcon(appInfo: appMonitor.appInfo(for: bundleId), bundleId: bundleId)
				}

				if remainingCount > 0 {
					Text("+\(remainingCount)")
						.font(.system(size: 10, weight: .semibold))
						.foregroundStyle(.white.opacity(0.65))
						.monospacedDigit()
						.help("\(remainingCount) more Linked Apps")
				}
			}
			.fixedSize(horizontal: true, vertical: false)
		}
	}
}

private struct LinkedProfileAppIcon: View {
	let appInfo: AppInfo?
	let bundleId: String

	var body: some View {
		Group {
			if let icon = appInfo?.icon {
				Image(nsImage: icon)
					.resizable()
					.scaledToFit()
			} else {
				Image(systemName: "app")
					.resizable()
					.scaledToFit()
					.foregroundStyle(.white.opacity(0.7))
					.padding(1)
			}
		}
		.frame(width: 14, height: 14)
		.clipShape(RoundedRectangle(cornerRadius: 3))
		.help(appInfo?.name ?? bundleId)
		.accessibilityLabel(appInfo?.name ?? bundleId)
	}
}

private struct ProfileStatusBadge: View {
	let systemName: String
	let color: Color
	let helpText: String

	var body: some View {
		Image(systemName: systemName)
			.font(.caption)
			.foregroundColor(color)
			.help(helpText)
			.accessibilityLabel(helpText)
	}
}

struct ProfileContextMenu: View {
	let profile: Profile
	let profileCount: Int
	let onDuplicate: () -> Void
	let onRename: () -> Void
	let onSetDefault: () -> Void
	let onLinkApps: () -> Void
	let onLinkController: () -> Void
	let keyboardSourceProfiles: [Profile]
	let onSetOnScreenKeyboardSource: (UUID?) -> Void
	let onSetIcon: (String?) -> Void
	let onExport: () -> Void
	let onShare: () -> Void
	let onDelete: () -> Void

	var body: some View {
		Button("Duplicate", action: onDuplicate)

		Button("Rename", action: onRename)

		Button("Set as Default Profile", action: onSetDefault)
			.disabled(profile.isDefault)

		Button("Linked Apps...", action: onLinkApps)
		Button("Linked Controller...", action: onLinkController)

	Menu("Shared Keyboard Settings") {
	    Button("Do Not Inherit") {
		onSetOnScreenKeyboardSource(nil)
	    }
	    .disabled(profile.inheritedOnScreenKeyboardProfileId == nil)

	    Divider()

	    if keyboardSourceProfiles.isEmpty {
		Button("No available profiles") {}
		    .disabled(true)
	    } else {
		ForEach(keyboardSourceProfiles) { sourceProfile in
		    Button {
			onSetOnScreenKeyboardSource(sourceProfile.id)
		    } label: {
			Label(
			    sourceProfile.name,
			    systemImage: profile.inheritedOnScreenKeyboardProfileId == sourceProfile.id
				? "checkmark"
				: "keyboard"
			)
		    }
		}
	    }
	}

		Menu("Set Icon") {
			ForEach(ProfileIcon.grouped, id: \.name) { group in
				Menu(group.name) {
					ForEach(group.icons) { icon in
						Button {
							onSetIcon(icon.rawValue)
						} label: {
							Label(icon.displayName, systemImage: icon.rawValue)
						}
					}
				}
			}

			Divider()

			Button("Remove Icon") {
				onSetIcon(nil)
			}
			.disabled(profile.icon == nil)
		}

		Button("Export...", action: onExport)
		Button("Share to Community…", action: onShare)

		Divider()

		Button("Delete", role: .destructive, action: onDelete)
			.disabled(profileCount <= 1)
	}
}

// MARK: - Profile Name Sheet

struct ProfileNameSheet: View {
	let title: String
	let actionLabel: String
	@Binding var name: String
	let onSave: () -> Void
	let onCancel: () -> Void

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(spacing: 16) {
			Text(title)
				.font(.headline)

			TextField("Profile name", text: $name)
				.textFieldStyle(.roundedBorder)

			HStack {
				Spacer()

				Button("Cancel") {
					onCancel()
					dismiss()
				}
				.keyboardShortcut(.cancelAction)

				Button(actionLabel) {
					onSave()
					dismiss()
				}
				.keyboardShortcut(.return, modifiers: .command)
				.buttonStyle(.borderedProminent)
				.disabled(name.isEmpty)
			}
		}
		.padding(20)
		.frame(width: 340)
		.onSubmit {
			guard !name.isEmpty else { return }
			onSave()
			dismiss()
		}
	}
}
