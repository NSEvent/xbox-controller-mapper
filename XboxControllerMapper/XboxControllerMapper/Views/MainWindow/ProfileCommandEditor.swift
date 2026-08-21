import SwiftUI

struct ProfileCommandSelection: Equatable {
	enum Mode: String, CaseIterable, Identifiable {
		case specific
		case lastUsed
		case next
		case previous

		var id: String { rawValue }

		var displayName: String {
			switch self {
			case .specific: return "Specific Profile"
			case .lastUsed: return ProfileNavigationAction.lastUsed.displayName
			case .next: return ProfileNavigationAction.next.displayName
			case .previous: return ProfileNavigationAction.previous.displayName
			}
		}

		var navigationAction: ProfileNavigationAction? {
			switch self {
			case .specific: return nil
			case .lastUsed: return .lastUsed
			case .next: return .next
			case .previous: return .previous
			}
		}

		init(navigationAction: ProfileNavigationAction) {
			switch navigationAction {
			case .lastUsed: self = .lastUsed
			case .next: self = .next
			case .previous: self = .previous
			}
		}
	}

	var mode: Mode = .specific
	var profileId: UUID?
	var profileName: String?

	var systemCommand: SystemCommand? {
		if let navigationAction = mode.navigationAction {
			return .navigateProfile(navigationAction)
		}
		guard let profileId else { return nil }
		return .switchProfile(profileId: profileId, profileName: profileName)
	}

	mutating func load(_ command: SystemCommand) {
		switch command {
		case .switchProfile(let profileId, let profileName):
			mode = .specific
			self.profileId = profileId
			self.profileName = profileName
		case .navigateProfile(let action):
			mode = Mode(navigationAction: action)
			profileId = nil
			profileName = nil
		default:
			break
		}
	}
}

struct ProfileCommandPicker: View {
	@Binding var selection: ProfileCommandSelection

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Picker("Profile Action", selection: $selection.mode) {
				ForEach(ProfileCommandSelection.Mode.allCases) { mode in
					Text(mode.displayName).tag(mode)
				}
			}

			if let navigationAction = selection.mode.navigationAction {
				Text(navigationAction.helpText)
					.font(.caption)
					.foregroundColor(.secondary)
			} else {
				ProfileSelectionPicker(
					selection: $selection.profileId,
					selectedName: $selection.profileName
				)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

struct ProfileSelectionPicker: View {
	@EnvironmentObject var profileManager: ProfileManager
	@Binding var selection: UUID?
	let selectedName: Binding<String?>?

	init(selection: Binding<UUID?>, selectedName: Binding<String?>? = nil) {
		self._selection = selection
		self.selectedName = selectedName
	}

	var body: some View {
		Picker("Profile", selection: $selection) {
			Text("Select Profile...").tag(nil as UUID?)
			ForEach(profileManager.profiles) { profile in
				Text(profile.name).tag(profile.id as UUID?)
			}
		}
		.labelsHidden()
		.frame(maxWidth: .infinity)
		.onAppear(perform: syncSelectedName)
		.onChange(of: selection) { _, _ in syncSelectedName() }
	}

	private func syncSelectedName() {
		guard let selectedName else { return }
		guard let selection,
		      let profile = profileManager.profiles.first(where: { $0.id == selection }) else {
			selectedName.wrappedValue = nil
			return
		}
		selectedName.wrappedValue = profile.name
	}
}
