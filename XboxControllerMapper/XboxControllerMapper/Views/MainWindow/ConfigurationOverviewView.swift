import SwiftUI

/// A compact, searchable table of contents for the active profile.
///
/// The controller canvas remains the direct spatial editor. This view answers
/// the complementary questions that a canvas cannot answer quickly: “What is
/// configured?”, “What changes in this layer?”, and “Where do I edit it?”
struct ConfigurationOverviewView: View {
	@EnvironmentObject private var profileManager: ProfileManager
	@EnvironmentObject private var mappingEngine: MappingEngine
	@AppStorage("hasDismissedConfigurationOverviewCoach") private var hasDismissedCoach = false

	@Binding var selectedLayerId: UUID?
	let presentation: ConfigurationOverviewPresentation
	let onOpenVisualEditor: () -> Void
	let onSelect: (ConfigurationOverviewTarget) -> Void

	@State private var query = ""
	@State private var filter: ConfigurationOverviewFilter = .all
	@State private var showingOtherDeviceMappings = false

	private func makeSnapshot() -> ConfigurationOverviewSnapshot? {
		profileManager.activeProfile.map {
			ConfigurationOverviewBuilder.make(
				profile: $0,
				selectedLayerId: selectedLayerId,
				presentation: presentation,
				sharedLibraryMacros: profileManager.sharedLibraryMacros
			)
		}
	}

	var body: some View {
		let snapshot = makeSnapshot()
		VStack(spacing: 0) {
			header(snapshot)
			Divider().opacity(0.45)

			if let snapshot {
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 18) {
						if !hasDismissedCoach { startHereCard }
						scopeSummary(snapshot)
						filterBar
						rows(snapshot)
					}
					.padding(20)
				}
			} else {
				ContentUnavailableView(
					"No Active Profile",
					systemImage: "rectangle.stack.badge.minus",
					description: Text("Create or select a profile to view its configuration.")
				)
			}
		}
		.onChange(of: profileManager.activeProfileId) { _, _ in
			selectedLayerId = nil
		}
		.onChange(of: query) { _, value in
			if !value.isEmpty { showingOtherDeviceMappings = true }
		}
	}

	private func header(_ snapshot: ConfigurationOverviewSnapshot?) -> some View {
		HStack(alignment: .center, spacing: 14) {
			VStack(alignment: .leading, spacing: 3) {
				Text("Configuration Overview")
					.font(.title2.bold())
				if let snapshot {
					Text(String(
						format: String(localized: "%@ · Editing: %@"),
						snapshot.profileName,
						snapshot.scopeName
					))
						.font(.callout)
						.foregroundStyle(.secondary)
				}
			}

			Spacer()

			scopeMenu(snapshot)

			Button(action: onOpenVisualEditor) {
				Label("Open Visual Editor", systemImage: "gamecontroller.fill")
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.help("Edit mappings on the controller diagram")
		}
		.padding(.horizontal, 20)
		.padding(.vertical, 14)
	}

	private func scopeMenu(_ snapshot: ConfigurationOverviewSnapshot?) -> some View {
		Menu {
			Button {
				selectedLayerId = nil
			} label: {
				Label("Base", systemImage: selectedLayerId == nil ? "checkmark" : "square.stack.3d.up")
			}

			if let profile = profileManager.activeProfile, !profile.layers.isEmpty {
				Divider()
				ForEach(profile.layers) { layer in
					Button {
						selectedLayerId = layer.id
					} label: {
						Label(layer.name, systemImage: selectedLayerId == layer.id ? "checkmark" : "square.stack.3d.up")
					}
				}
			}
		} label: {
			HStack(spacing: 7) {
				Image(systemName: "square.stack.3d.up")
				VStack(alignment: .leading, spacing: 0) {
					Text("EDITING")
						.font(.system(size: 9, weight: .bold))
						.foregroundStyle(.secondary)
					Text(snapshot?.scopeName ?? String(localized: "Base"))
						.font(.callout.weight(.semibold))
						.lineLimit(1)
				}
				Image(systemName: "chevron.down")
					.font(.caption2.bold())
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 12)
			.frame(height: 38)
			.background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 9, style: .continuous)
					.stroke(Color.primary.opacity(0.12), lineWidth: 1)
			}
		}
		.menuStyle(.borderlessButton)
		.fixedSize()
		.help("Choose what to edit. Runtime layers can activate independently.")
		.accessibilityLabel("Editing scope")
		.accessibilityValue(snapshot?.scopeName ?? String(localized: "Base"))
	}

	private var startHereCard: some View {
		HStack(spacing: 14) {
			Image(systemName: "cursorarrow.click.2")
				.font(.system(size: 25, weight: .semibold))
				.foregroundStyle(.tint)
				.frame(width: 42, height: 42)
				.background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

			VStack(alignment: .leading, spacing: 3) {
				Text("Start with the controller")
					.font(.headline)
				Text("Choose a control on the visual map, assign what it should do, then save and try it.")
					.font(.callout)
					.foregroundStyle(.secondary)
			}

			Spacer(minLength: 12)

			Button("Choose a Control") {
				hasDismissedCoach = true
				onOpenVisualEditor()
			}
				.controlSize(.large)

			Button {
				hasDismissedCoach = true
			} label: {
				Image(systemName: "xmark.circle.fill")
					.foregroundStyle(.secondary)
			}
			.buttonStyle(.plain)
			.help("Dismiss this guide")
			.accessibilityLabel("Dismiss getting started guide")
		}
		.padding(16)
		.background(
			LinearGradient(
				colors: [Color.accentColor.opacity(0.15), Color.primary.opacity(0.055)],
				startPoint: .leading,
				endPoint: .trailing
			),
			in: RoundedRectangle(cornerRadius: 14, style: .continuous)
		)
		.overlay {
			RoundedRectangle(cornerRadius: 14, style: .continuous)
				.stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
		}
	}

	private func scopeSummary(_ snapshot: ConfigurationOverviewSnapshot) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 16) {
				metric(snapshot.configuredControlCount, "configured controls", systemImage: "button.programmable")
				metric(snapshot.advancedTriggerCount, "advanced triggers", systemImage: "link")
				metric(snapshot.commandWheelCount, "wheel actions", systemImage: "circle.hexagongrid")
				metric(snapshot.automationCount, "automations", systemImage: "bolt.fill")
				if let profile = profileManager.activeProfile {
					metric(profile.layers.count, "layers", systemImage: "square.stack.3d.up")
				}
			}

			if let layer = snapshot.layer {
				HStack(spacing: 8) {
					Image(systemName: "square.stack.3d.up.fill")
						.foregroundStyle(.tint)
					Text(layer.name)
						.font(.callout.weight(.semibold))
					Text(layer.activator.map { "\(layer.activationStyle) · \($0)" } ?? String(localized: "No activator assigned"))
						.font(.callout)
						.foregroundStyle(layer.activator == nil ? Color.orange : Color.secondary)
					Spacer()
					VStack(alignment: .trailing, spacing: 1) {
						Text(String(
							format: String(localized: "%lld configured changes"),
							layer.overrideCount
						))
							.font(.caption.weight(.semibold))
						if !layer.overrideDetails.isEmpty {
							Text(layer.overrideDetails.joined(separator: " · "))
								.font(.caption2)
								.foregroundStyle(.secondary)
								.lineLimit(2)
						}
					}
					Button("Edit Layer") { onSelect(.layer(layer.id)) }
						.buttonStyle(.link)
				}
				.padding(.horizontal, 12)
				.padding(.vertical, 9)
				.background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
			}

			if let activeLayerId = mappingEngine.activeRuntimeLayerId,
			   let activeLayer = profileManager.activeProfile?.layers.first(where: { $0.id == activeLayerId }) {
				HStack {
					Label(
						String(
							format: String(localized: "Runtime layer active now: %@"),
							activeLayer.name
						),
						systemImage: "bolt.horizontal.circle.fill"
					)
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
					Spacer()
					if selectedLayerId != activeLayerId {
						Button("Edit Active Layer") { selectedLayerId = activeLayerId }
							.buttonStyle(.link)
					}
				}
			}
		}
	}

	private func metric(_ value: Int, _ label: LocalizedStringKey, systemImage: String) -> some View {
		Label {
			Text("\(value) ") + Text(label)
		} icon: {
			Image(systemName: systemImage)
		}
		.font(.callout.weight(.medium))
		.foregroundStyle(.secondary)
	}

	private var filterBar: some View {
		HStack(spacing: 12) {
			HStack(spacing: 8) {
				Image(systemName: "magnifyingglass")
					.foregroundStyle(.secondary)
				TextField("Search controls, actions, and hints", text: $query)
					.textFieldStyle(.plain)
				if !query.isEmpty {
					Button {
						query = ""
					} label: {
						Image(systemName: "xmark.circle.fill")
							.foregroundStyle(.secondary)
					}
					.buttonStyle(.plain)
					.help("Clear search")
					.accessibilityLabel("Clear search")
				}
			}
			.padding(.horizontal, 11)
			.frame(height: 34)
			.background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 8, style: .continuous)
					.stroke(Color.primary.opacity(0.1), lineWidth: 1)
			}

			Picker("Filter", selection: $filter) {
				ForEach(ConfigurationOverviewFilter.allCases) { item in
					Text(item.localizedLabel).tag(item)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.frame(maxWidth: 560)
		}
	}

	@ViewBuilder
	private func rows(_ snapshot: ConfigurationOverviewSnapshot) -> some View {
		let visibleRows = ConfigurationOverviewBuilder.filteredRows(
			snapshot.rows,
			category: filter.category,
			query: query
		)

		if visibleRows.isEmpty {
			let rowsInSelectedCategory = snapshot.rows.filter {
				filter.category == nil || $0.category == filter.category
			}
			emptyState(
				hasConfiguration: !rowsInSelectedCategory.isEmpty
					|| !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			)
		} else {
			let currentDeviceRows = visibleRows.filter(\.isCurrentDevice)
			let otherDeviceRows = visibleRows.filter { !$0.isCurrentDevice }
			if ConfigurationOverviewEmptyStatePolicy.showsUnavailableOnlyState(
				rows: visibleRows,
				query: query
			) {
				unavailableOnlyState()
			}

			ForEach(ConfigurationOverviewCategory.allCases) { category in
				let categoryRows = currentDeviceRows.filter { $0.category == category }
				if !categoryRows.isEmpty {
					rowSection(category, rows: categoryRows)
				}
			}

			if !otherDeviceRows.isEmpty {
				DisclosureGroup(isExpanded: $showingOtherDeviceMappings) {
					LazyVStack(spacing: 5) {
						ForEach(otherDeviceRows) { row in overviewRow(row) }
					}
					.padding(.top, 8)
				} label: {
					Label(
						String(
							format: String(localized: "Unavailable for %@ (%lld)"),
							presentation.deviceName,
							otherDeviceRows.count
						),
						systemImage: "gamecontroller"
					)
						.font(.headline)
				}
			}
		}
	}

	private func rowSection(
		_ category: ConfigurationOverviewCategory,
		rows: [ConfigurationOverviewRow]
	) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 7) {
				Image(systemName: category.systemImage)
					.foregroundStyle(.secondary)
				Text(category.localizedLabel)
					.font(.headline)
				Text("\(rows.count)")
					.font(.caption.bold())
					.foregroundStyle(.secondary)
			}

			LazyVStack(spacing: 5) {
				ForEach(rows) { row in
					overviewRow(row)
				}
			}
		}
	}

	private func overviewRow(_ row: ConfigurationOverviewRow) -> some View {
		Button {
			onSelect(row.target)
		} label: {
			HStack(spacing: 12) {
				Image(systemName: row.systemImage)
					.font(.system(size: 15, weight: .semibold))
					.foregroundStyle(sourceColor(row.source))
					.frame(width: 28, height: 28)
					.background(sourceColor(row.source).opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

				Text(row.trigger)
					.font(.callout.weight(.semibold))
					.foregroundStyle(.primary)
					.lineLimit(2)
					.frame(width: 190, alignment: .leading)

				VStack(alignment: .leading, spacing: 2) {
					Text(row.action)
						.font(.callout.weight(.medium))
						.foregroundStyle(.primary)
						.lineLimit(1)
					if let detail = row.detail {
						Text(detail)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(2)
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)

				Text(row.source.label)
					.font(.caption.weight(.semibold))
					.foregroundStyle(sourceColor(row.source))
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
					.background(sourceColor(row.source).opacity(0.11), in: Capsule())

				Image(systemName: "chevron.right")
					.font(.caption.bold())
					.foregroundStyle(.tertiary)
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 10, style: .continuous)
					.stroke(Color.primary.opacity(0.07), lineWidth: 1)
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.help("Open \(row.trigger)")
		.accessibilityLabel(row.accessibilitySummary)
		.accessibilityHint("Open configuration")
	}

	private func unavailableOnlyState() -> some View {
		let emptyConfiguration = filter.emptyConfiguration
		return VStack(spacing: 10) {
			Image(systemName: "gamecontroller.fill")
				.font(.system(size: 30))
				.foregroundStyle(.secondary)
			Text("No Available Configuration")
				.font(.headline)
			Text("Configured items for other controllers are preserved below. Open the editor to add something this controller can use.")
				.font(.callout)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
			Button(emptyConfiguration.action) {
				onSelect(emptyConfiguration.target)
			}
			.buttonStyle(.borderedProminent)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 28)
	}

	private func emptyState(hasConfiguration: Bool) -> some View {
		let emptyConfiguration = filter.emptyConfiguration
		return VStack(spacing: 10) {
			Image(systemName: hasConfiguration ? "line.3.horizontal.decrease.circle" : "gamecontroller.badge.plus")
				.font(.system(size: 30))
				.foregroundStyle(.secondary)
			Text(hasConfiguration ? String(localized: "No Matching Configuration") : emptyConfiguration.title)
				.font(.headline)
			Text(hasConfiguration
				 ? String(localized: "Try another search or show all configuration types.")
				 : emptyConfiguration.description)
				.font(.callout)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
			Button(hasConfiguration ? String(localized: "Clear Filters") : emptyConfiguration.action) {
				if hasConfiguration {
					query = ""
					filter = .all
				} else {
					onSelect(emptyConfiguration.target)
				}
			}
			.buttonStyle(.borderedProminent)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 44)
	}

	private func sourceColor(_ source: ConfigurationOverviewSource) -> Color {
		switch source {
		case .base: return .blue
		case .inherited: return .secondary
		case .override: return .cyan
		case .profile: return .orange
		case .library: return .purple
		}
	}
}
