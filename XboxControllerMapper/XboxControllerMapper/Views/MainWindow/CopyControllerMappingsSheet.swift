import SwiftUI

/// Copies one controller's button mappings from a profile into another profile,
/// with a live preview of what will be copied, overwritten and cleared.
struct CopyControllerMappingsSheet: View {
	@EnvironmentObject var profileManager: ProfileManager
	@EnvironmentObject var controllerService: ControllerService
	@Environment(\.dismiss) private var dismiss

	let sourceProfileId: UUID
	@State var layout: ControllerPreviewLayout

	@State private var destinationId: UUID?
	@State private var options = ControllerMappingTransferOptions()

	private var source: Profile? {
		profileManager.profiles.first { $0.id == sourceProfileId }
	}

	private var destinations: [Profile] {
		profileManager.profiles.filter { $0.id != sourceProfileId }
	}

	private var descriptor: ControllerVisualDescriptor {
		ControllerVisualDescriptor.resolved(previewLayout: layout, using: controllerService)
	}

	private var plan: ControllerMappingTransferPlan? {
		guard let source,
			  let destinationId,
			  let destination = profileManager.profiles.first(where: { $0.id == destinationId }) else { return nil }
		return ControllerMappingTransfer.plan(
			from: source,
			to: destination,
			buttons: ControllerMappingTransfer.buttonScope(for: descriptor),
			options: options
		)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Copy Controller Mappings")
				.font(.headline)
				.frame(maxWidth: .infinity)

			Form {
				LabeledContent("From", value: source?.name ?? "")

				Picker("Controller", selection: $layout) {
					ForEach(ControllerPreviewLayout.allCases) { layout in
						Text(layoutTitle(layout)).tag(layout)
					}
				}

				Picker("To", selection: $destinationId) {
					Text("Choose a profile").tag(UUID?.none)
					ForEach(destinations) { profile in
						Text(profile.name).tag(UUID?.some(profile.id))
					}
				}

				Picker("Mode", selection: $options.mode) {
					Text("Replace").tag(ControllerMappingTransferOptions.Mode.replace)
					Text("Fill empty only").tag(ControllerMappingTransferOptions.Mode.fillEmpty)
				}
				.pickerStyle(.segmented)

				Toggle("Include layers (matched by name)", isOn: $options.includeLayers)
			}
			.formStyle(.grouped)
			.scrollDisabled(true)
			.frame(height: 250)

			preview

			HStack {
				Text("A snapshot is saved first. Restore it from History.")
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				Button("Cancel") { dismiss() }
					.keyboardShortcut(.cancelAction)
				Button("Copy") {
					copy()
				}
				.keyboardShortcut(.defaultAction)
				.buttonStyle(.borderedProminent)
				.disabled(plan?.hasChanges != true)
			}
		}
		.padding(20)
		.frame(width: 500)
		.onAppear {
			if destinationId == nil, destinations.count == 1 {
				destinationId = destinations.first?.id
			}
		}
	}

	@ViewBuilder
	private var preview: some View {
		VStack(alignment: .leading, spacing: 6) {
			if destinations.isEmpty {
				Text("Create another profile to copy mappings into.")
			} else if let plan, let destination = profileManager.profiles.first(where: { $0.id == destinationId }) {
				if plan.hasChanges {
					previewLine("square.on.square", "\(plan.copiedCount) \(plural(plan.copiedCount, "mapping")) copied to \(destination.name)")
					if !plan.overwritten.isEmpty {
						previewLine("exclamationmark.triangle", overwrittenSummary(plan.overwritten), tint: .orange)
						PairingMinimapView(
							layout: layout,
							pressedButtons: Set(plan.overwritten.map(\.button)),
							targetWidth: 240,
							remoteTargetHeight: 200,
							descriptor: descriptor
						)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 4)
					}
					if plan.clearedCount > 0 {
						previewLine("xmark.circle", "Clears \(plan.clearedCount) \(plural(plan.clearedCount, "mapping")) that \(source?.name ?? "the source") leaves unmapped", tint: .orange)
					}
					if !plan.createdLayerNames.isEmpty {
						previewLine("square.stack.3d.up", "Creates \(plural(plan.createdLayerNames.count, "layer")): \(plan.createdLayerNames.joined(separator: ", "))")
					}
					if !plan.skippedLayerNames.isEmpty {
						previewLine("exclamationmark.triangle", "Layer limit reached; skipped \(plan.skippedLayerNames.joined(separator: ", "))", tint: .orange)
					}
					if plan.carriedMacroCount + plan.carriedScriptCount > 0 {
						previewLine("wand.and.stars", "Brings along \(dependencySummary(plan))")
					}
				} else {
					previewLine("checkmark.circle", "\(destination.name) already matches these mappings.")
				}
				if descriptor.supportedButtons.contains(.a) {
					Text("Face buttons, sticks and triggers are shared across controller types, so these changes also apply to other controllers using \(destination.name).")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
			} else {
				Text("Choose a profile to see what will change.")
			}
		}
		.font(.callout)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
	}

	private func previewLine(_ systemImage: String, _ text: String, tint: Color = .accentColor) -> some View {
		Label {
			Text(text).fixedSize(horizontal: false, vertical: true)
		} icon: {
			Image(systemName: systemImage).foregroundStyle(tint)
		}
	}

	private func layoutTitle(_ layout: ControllerPreviewLayout) -> String {
		guard layout == .active else { return layout.displayName }
		let resolved = ControllerVisualDescriptor.resolved(previewLayout: .active, using: controllerService)
		return "\(layout.displayName) (\(resolved.displayName))"
	}

	private func overwrittenSummary(_ changes: [ControllerMappingTransferPlan.Change]) -> String {
		let summary = "Overwrites \(changes.count) \(plural(changes.count, "mapping")), highlighted below"
		let layerNames = changes.compactMap(\.layerName).reduce(into: [String]()) { names, name in
			if !names.contains(name) { names.append(name) }
		}
		guard !layerNames.isEmpty else { return summary }
		let layerCount = changes.filter { $0.layerName != nil }.count
		return summary + " (\(layerCount) in \(plural(layerNames.count, "layer")): \(layerNames.joined(separator: ", ")))"
	}

	private func dependencySummary(_ plan: ControllerMappingTransferPlan) -> String {
		var parts: [String] = []
		if plan.carriedMacroCount > 0 { parts.append("\(plan.carriedMacroCount) \(plural(plan.carriedMacroCount, "macro"))") }
		if plan.carriedScriptCount > 0 { parts.append("\(plan.carriedScriptCount) \(plural(plan.carriedScriptCount, "script"))") }
		return parts.joined(separator: " and ")
	}

	private func plural(_ count: Int, _ noun: String) -> String {
		count == 1 ? noun : noun + "s"
	}

	private func copy() {
		guard let source, let destinationId else { return }
		profileManager.copyControllerMappings(
			from: source,
			to: destinationId,
			buttons: ControllerMappingTransfer.buttonScope(for: descriptor),
			controllerName: descriptor.displayName,
			options: options
		)
		dismiss()
	}
}
