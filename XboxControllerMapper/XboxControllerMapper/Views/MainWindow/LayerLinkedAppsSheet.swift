import SwiftUI

struct LayerLinkedAppsSheet: View {
	@EnvironmentObject private var profileManager: ProfileManager
	@EnvironmentObject private var appMonitor: AppMonitor
	@Environment(\.dismiss) private var dismiss

	let profileId: UUID
	let layerId: UUID
	@State private var showingAppPicker = false

	private var profile: Profile? {
		profileManager.profiles.first(where: { $0.id == profileId })
	}

	private var layer: Layer? {
		profile?.layers.first(where: { $0.id == layerId })
	}

	private var linkedBundleIds: [String] {
		guard let profile else { return [] }
		return profile.appLayerBindings
			.filter { $0.value == layerId }
			.map(\.key)
			.sorted()
	}

	var body: some View {
		VStack(spacing: 20) {
			Text("Apps for \(layer?.name ?? "Layer")")
				.font(.headline)

			Text("This layer activates automatically while a linked app is in front. A held layer button still takes priority.")
				.font(.caption)
				.foregroundColor(.secondary)
				.multilineTextAlignment(.center)
				.padding(.horizontal)

			List {
				if linkedBundleIds.isEmpty {
					Text("No apps linked")
						.foregroundColor(.secondary)
						.italic()
						.frame(maxWidth: .infinity, alignment: .center)
						.padding()
				} else {
					ForEach(linkedBundleIds, id: \.self) { bundleId in
						HStack {
							if let appInfo = appMonitor.appInfo(for: bundleId) {
								if let icon = appInfo.icon {
									Image(nsImage: icon)
										.resizable()
										.frame(width: 24, height: 24)
								}
								VStack(alignment: .leading, spacing: 2) {
									Text(appInfo.name)
										.fontWeight(.medium)
									Text(bundleId)
										.font(.caption)
										.foregroundColor(.secondary)
								}
							} else {
								Text(bundleId)
							}

							Spacer()

							Button {
								guard let profile else { return }
								profileManager.unlinkApp(bundleId, fromLayer: layerId, in: profile)
							} label: {
								Image(systemName: "trash")
									.foregroundColor(.red)
							}
							.buttonStyle(.borderless)
							.help("Remove")
							.accessibilityLabel("Remove Linked App")
						}
						.padding(.vertical, 4)
					}
				}
			}
			.listStyle(.inset)
			.frame(height: 220)
			.background(Color.black.opacity(0.1))
			.cornerRadius(8)

			HStack {
				Button {
					showingAppPicker = true
				} label: {
					Label("Add App...", systemImage: "plus")
				}

				Spacer()

				Button("Done") {
					dismiss()
				}
				.keyboardShortcut(.return, modifiers: .command)
				.buttonStyle(.borderedProminent)
			}
		}
		.padding(20)
		.frame(width: 480)
		.sheet(isPresented: $showingAppPicker) {
			LayerAppPickerSheet(profileId: profileId, layerId: layerId)
		}
	}
}

private struct LayerAppPickerSheet: View {
	@EnvironmentObject private var profileManager: ProfileManager
	@EnvironmentObject private var appMonitor: AppMonitor
	@Environment(\.dismiss) private var dismiss

	let profileId: UUID
	let layerId: UUID
	@State private var searchText = ""
	@State private var selectedTab = 0
	@State private var linkErrorMessage: String?

	private var profile: Profile? {
		profileManager.profiles.first(where: { $0.id == profileId })
	}

	var body: some View {
		VStack(spacing: 16) {
			Text("Select App")
				.font(.headline)

			Picker("", selection: $selectedTab) {
				Text("Running").tag(0)
				Text("Installed").tag(1)
			}
			.pickerStyle(.segmented)
			.frame(maxWidth: 200)

			TextField("Search", text: $searchText)
				.textFieldStyle(.roundedBorder)

			List(filteredApps) { app in
				HStack {
					if let icon = app.icon {
						Image(nsImage: icon)
							.resizable()
							.frame(width: 32, height: 32)
					}

					VStack(alignment: .leading) {
						Text(app.name)
							.fontWeight(.medium)
						Text(app.bundleIdentifier)
							.font(.caption)
							.foregroundColor(.secondary)
					}

					Spacer()

					if let profile,
					   let conflict = profileManager.fullProfileLinkConflict(
						for: app.bundleIdentifier,
						excluding: profile.id
					   ) {
						Label("Profile: \(conflict.name)", systemImage: "exclamationmark.triangle.fill")
							.font(.caption)
							.foregroundColor(.orange)
							.help("This app already switches to the \(conflict.name) profile")
					} else if profile?.appLayerBindings[app.bundleIdentifier] == layerId {
						Label("Linked", systemImage: "checkmark.circle.fill")
							.font(.caption)
							.foregroundColor(.green)
					} else {
						Button("Add") {
							guard let profile else { return }
							switch profileManager.linkApp(
								app.bundleIdentifier,
								toLayer: layerId,
								in: profile
							) {
							case .linked:
								dismiss()
							case .profileConflict(let profileName):
								linkErrorMessage =
									"This app already switches to the \(profileName) profile. Remove that profile link before linking it to this layer."
							case .invalidLayer:
								linkErrorMessage = "This layer no longer exists."
							}
						}
						.buttonStyle(.bordered)
						.controlSize(.small)
					}
				}
				.padding(.vertical, 4)
			}
			.listStyle(.inset)
			.frame(height: 400)
			.background(Color.black.opacity(0.1))
			.cornerRadius(8)

			HStack {
				Spacer()
				Button("Cancel") {
					dismiss()
				}
				.keyboardShortcut(.cancelAction)
			}
		}
		.padding(20)
		.frame(width: 500)
		.alert(
			"Cannot Link App",
			isPresented: Binding(
				get: { linkErrorMessage != nil },
				set: { if !$0 { linkErrorMessage = nil } }
			)
		) {
			Button("OK", role: .cancel) {
				linkErrorMessage = nil
			}
		} message: {
			Text(linkErrorMessage ?? "")
		}
	}

	private var filteredApps: [AppInfo] {
		let apps = selectedTab == 0 ? appMonitor.runningApplications : appMonitor.installedApplications
		guard !searchText.isEmpty else { return apps }
		return apps.filter {
			$0.name.localizedCaseInsensitiveContains(searchText)
				|| $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
		}
	}
}
