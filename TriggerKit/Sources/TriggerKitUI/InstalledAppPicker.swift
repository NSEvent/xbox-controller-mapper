import AppKit
import SwiftUI

struct InstalledApp: Identifiable, Hashable, Sendable {
	let bundleIdentifier: String
	let name: String
	let path: String

	var id: String { bundleIdentifier }
}

struct InstalledAppPickerButton: View {
	let bundleIdentifier: String
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			HStack(spacing: 10) {
				AppIcon(bundleIdentifier: bundleIdentifier)
					.frame(width: 28, height: 28)

				VStack(alignment: .leading, spacing: 2) {
					Text(title)
						.font(.callout.weight(.semibold))
						.lineLimit(1)
					Text(subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}

				Spacer()

				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
			}
			.padding(8)
			.background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
			.clipShape(RoundedRectangle(cornerRadius: 8))
		}
		.buttonStyle(.plain)
	}

	private var title: String {
		guard !bundleIdentifier.isEmpty else { return "Select App" }
		return appName(for: bundleIdentifier) ?? bundleIdentifier
	}

	private var subtitle: String {
		bundleIdentifier.isEmpty ? "Choose from installed applications" : bundleIdentifier
	}
}

struct InstalledAppPickerSheet: View {
	let currentBundleIdentifier: String
	let onSelect: (InstalledApp) -> Void

	@Environment(\.dismiss) private var dismiss
	@FocusState private var searchFocused: Bool
	@State private var searchText = ""
	@State private var installedApps: [InstalledApp] = []
	@State private var isLoading = true

	private var filteredApps: [InstalledApp] {
		guard !searchText.isEmpty else { return installedApps }
		return installedApps.filter { app in
			app.name.localizedCaseInsensitiveContains(searchText) ||
				app.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
		}
	}

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Text("Select App")
					.font(.headline)
				Spacer()
				Button("Cancel") { dismiss() }
					.keyboardShortcut(.cancelAction)
			}
			.padding()

			Divider()

			TextField("Search apps", text: $searchText)
				.textFieldStyle(.roundedBorder)
				.focused($searchFocused)
				.onSubmit { selectFirstMatch() }
				.padding()

			Divider()

			if isLoading {
				ProgressView()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if filteredApps.isEmpty {
				Text("No matching apps")
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				List(filteredApps) { app in
					Button {
						select(app)
					} label: {
						HStack(spacing: 12) {
							AppIcon(path: app.path)
								.frame(width: 32, height: 32)

							VStack(alignment: .leading, spacing: 2) {
								Text(app.name)
									.font(.callout.weight(.semibold))
									.lineLimit(1)
								Text(app.bundleIdentifier)
									.font(.caption)
									.foregroundStyle(.secondary)
									.lineLimit(1)
							}

							Spacer()

							if app.bundleIdentifier == currentBundleIdentifier {
								Image(systemName: "checkmark")
									.foregroundStyle(Color.accentColor)
							}
						}
						.padding(.vertical, 4)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
				.listStyle(.plain)
			}
		}
		.frame(width: 460, height: 520)
		.onAppear {
			searchFocused = true
			loadInstalledApps()
		}
	}

	private func select(_ app: InstalledApp) {
		onSelect(app)
		dismiss()
	}

	private func selectFirstMatch() {
		guard let app = filteredApps.first else { return }
		select(app)
	}

	private func loadInstalledApps() {
		guard installedApps.isEmpty else { return }
		isLoading = true
		Task.detached(priority: .userInitiated) {
			let apps = InstalledApp.discover()
			await MainActor.run {
				installedApps = apps
				isLoading = false
			}
		}
	}
}

private struct AppIcon: View {
	var bundleIdentifier: String?
	var path: String?

	var body: some View {
		Group {
			if let image {
				Image(nsImage: image)
					.resizable()
			} else {
				Image(systemName: "app.fill")
					.resizable()
					.symbolRenderingMode(.hierarchical)
					.foregroundStyle(.secondary)
					.padding(3)
			}
		}
	}

	private var image: NSImage? {
		if let path {
			return NSWorkspace.shared.icon(forFile: path)
		}
		if let bundleIdentifier,
		   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
			return NSWorkspace.shared.icon(forFile: url.path)
		}
		return nil
	}
}

private extension InstalledApp {
	static func discover() -> [InstalledApp] {
		let directories = [
			"/Applications",
			"/Applications/Utilities",
			"/System/Applications",
			"/System/Applications/Utilities",
			"/System/Library/CoreServices",
			"/System/Cryptexes/App/System/Applications",
			NSHomeDirectory() + "/Applications"
		]

		var appsByBundleIdentifier: [String: InstalledApp] = [:]
		for directory in directories {
			guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
				continue
			}

			for item in contents where item.hasSuffix(".app") {
				let path = (directory as NSString).appendingPathComponent(item)
				guard let bundle = Bundle(path: path),
				      let bundleIdentifier = bundle.bundleIdentifier else {
					continue
				}

				let name = (item as NSString).deletingPathExtension
				appsByBundleIdentifier[bundleIdentifier] = InstalledApp(
					bundleIdentifier: bundleIdentifier,
					name: name,
					path: path
				)
			}
		}

		return appsByBundleIdentifier.values.sorted {
			$0.name.localizedStandardCompare($1.name) == .orderedAscending
		}
	}
}

private func appName(for bundleIdentifier: String) -> String? {
	guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
		return nil
	}
	return url.deletingPathExtension().lastPathComponent
}
