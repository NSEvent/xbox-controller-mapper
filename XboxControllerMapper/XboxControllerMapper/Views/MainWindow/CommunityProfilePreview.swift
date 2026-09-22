import SwiftUI

// MARK: - Community Profile Row

struct CommunityProfileRow: View {
	let profileInfo: CommunityProfileInfo
	let isSelected: Bool
	let isAlreadyImported: Bool
	let isPreviewing: Bool
	let onToggleSelect: () -> Void
	let onPreview: () -> Void

	var body: some View {
		HStack(spacing: 8) {
			// Checkbox - disabled for already-imported profiles
			Button(action: onToggleSelect) {
				Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
					.foregroundColor(isAlreadyImported ? .secondary : (isSelected ? .accentColor : .secondary))
			}
			.buttonStyle(.plain)
			.disabled(isAlreadyImported)
			.help(isSelected ? "Deselect \(profileInfo.displayName)" : "Select \(profileInfo.displayName)")
			.accessibilityLabel(isSelected ? "Deselect \(profileInfo.displayName)" : "Select \(profileInfo.displayName)")

			// Profile name (clickable for preview)
			Text(profileInfo.displayName)
				.lineLimit(1)
				.frame(maxWidth: .infinity, alignment: .leading)
				.foregroundColor(isAlreadyImported ? .secondary : .primary)

			// Already imported indicator
			if isAlreadyImported {
				Text("Imported")
					.font(.caption2)
					.foregroundColor(.secondary)
					.padding(.horizontal, 6)
					.padding(.vertical, 2)
					.background(Color.secondary.opacity(0.2))
					.cornerRadius(4)
			}

			// Preview indicator
			if isPreviewing {
				Image(systemName: "eye.fill")
					.font(.caption)
					.foregroundColor(.accentColor)
			}
		}
		.padding(.vertical, 6)
		.padding(.horizontal, 8)
		.background(isPreviewing ? Color.accentColor.opacity(0.15) : Color.clear)
		.cornerRadius(6)
		.contentShape(Rectangle())
		.onTapGesture(count: 2) {
			onToggleSelect()
			onPreview()
		}
		.onTapGesture(count: 1) {
			onPreview()
		}
	}
}

// MARK: - Community Profile Preview

struct CommunityProfilePreview: View {
	let profile: Profile?
	let profileName: String?
	let setupGuide: String?
	let isLoading: Bool

	var body: some View {
		VStack(spacing: 0) {
			if isLoading {
				Spacer()
				ProgressView("Loading preview...")
				Spacer()
			} else if let profile = profile {
				// Header
				HStack {
					Text(profileName ?? profile.name)
						.font(.system(size: 14, weight: .semibold))
					Spacer()
					Text("\(profile.buttonMappings.count) mappings")
						.font(.caption)
						.foregroundColor(.secondary)
					if !profile.chordMappings.isEmpty {
						Text("• \(profile.chordMappings.count) chords")
							.font(.caption)
							.foregroundColor(.secondary)
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)

				Divider()

				// Mappings list
				ScrollView {
					VStack(spacing: 6) {
						// Setup guide (if a sidecar markdown exists for this profile)
						if let guide = setupGuide {
							SetupGuideSection(markdown: guide)
								.padding(.horizontal, 16)
								.padding(.bottom, 12)
							Divider()
								.padding(.bottom, 8)
						}

						// Button mappings
						ForEach(ControllerButton.allCases.filter { profile.buttonMappings[$0] != nil }, id: \.self) { button in
							if let mapping = profile.buttonMappings[button], !mapping.isEmpty {
								PreviewMappingRow(button: button, mapping: mapping, profile: profile)
							}
						}

						// Chord mappings
						if !profile.chordMappings.isEmpty {
							Divider()
								.padding(.vertical, 12)

							HStack {
								Text("CHORDS")
									.font(.system(size: 10, weight: .bold))
									.foregroundColor(.secondary)
								Spacer()
							}
							.padding(.horizontal, 16)
							.padding(.bottom, 8)

							VStack(spacing: 8) {
								ForEach(profile.chordMappings) { chord in
									PreviewChordRow(chord: chord, profile: profile)
								}
							}
						}
					}
					.padding(.vertical, 8)
				}
			} else {
				// Empty state - no profile selected
				VStack(spacing: 16) {
					Spacer()

					Image(systemName: "gamecontroller")
						.font(.system(size: 40, weight: .light))
						.foregroundColor(.secondary.opacity(0.3))

					VStack(spacing: 4) {
						Text("Preview")
							.font(.system(size: 14, weight: .medium))
							.foregroundColor(.secondary.opacity(0.6))
						Text("Click a profile to see its mappings")
							.font(.system(size: 12))
							.foregroundColor(.secondary.opacity(0.4))
					}

					Spacer()
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.background(Color.black.opacity(0.15))
	}
}

// MARK: - Preview Mapping Row

struct PreviewMappingRow: View {
	@EnvironmentObject var controllerService: ControllerService

	let button: ControllerButton
	let mapping: KeyMapping
	let profile: Profile

	private var controllerPresentationState: ControllerPresentationState {
		controllerService.threadSafeControllerPresentationState
	}

	var body: some View {
		let presentationState = controllerPresentationState

		HStack(spacing: 12) {
			ButtonIconView(
				button: button,
				isPressed: false,
				isDualSense: presentationState.isPlayStation,
				isNintendo: presentationState.isNintendo,
				isSteamController: presentationState.isSteamController,
				isAppleTVRemote: presentationState.isAppleTVRemote,
				isEightBitDo: presentationState.eightBitDoModel != nil
			)
				.frame(width: 28, height: 28)

			// Show mappings with hint + actual shortcut side by side
			HStack(spacing: 16) {
				// Primary mapping
				if let systemCommand = mapping.systemCommand {
					PreviewMappingLabel(
						text: mapping.hint ?? systemCommand.displayName,
						shortcut: mapping.hint != nil ? systemCommand.displayName : nil,
						icon: "SYS",
						color: .green
					)
				} else if let macroId = mapping.macroId,
						  let macroName = profile.macroDisplayName(for: macroId) {
					PreviewMappingLabel(
						text: mapping.hint ?? macroName,
						shortcut: mapping.hint != nil ? "Macro: \(macroName)" : nil,
						icon: "▶",
						color: .purple
					)
				} else if !mapping.isEmpty {
					PreviewMappingLabel(
						text: mapping.hint ?? mapping.displayString,
						shortcut: mapping.hint != nil ? mapping.displayString : nil,
						icon: mapping.isHoldModifier ? "▼" : nil,
						color: mapping.isHoldModifier ? .purple : .primary
					)
				}

				// Long hold
				if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
					PreviewMappingLabel(
						text: longHold.hint ?? longHold.displayString,
						shortcut: longHold.hint != nil ? longHold.displayString : nil,
						icon: "⏱",
						color: .orange
					)
				}

				// Double tap
				if let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty {
					PreviewMappingLabel(
						text: doubleTap.hint ?? doubleTap.displayString,
						shortcut: doubleTap.hint != nil ? doubleTap.displayString : nil,
						icon: "2×",
						color: .cyan
					)
				}
			}

			Spacer()
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 6)
		.background(Color.white.opacity(0.03))
		.cornerRadius(6)
		.padding(.horizontal, 8)
	}
}

struct PreviewMappingLabel: View {
	let text: String
	let shortcut: String?
	let icon: String?
	let color: Color

	var body: some View {
		HStack(spacing: 6) {
			if let icon = icon {
				Text(icon)
					.font(.system(size: 8, weight: .black))
					.foregroundColor(.white)
					.padding(.horizontal, 3)
					.padding(.vertical, 1)
					.background(color)
					.cornerRadius(2)
			}
			Text(text)
				.font(.system(size: 12, weight: .medium))
				.foregroundColor(color == .primary ? .primary : color)
				.lineLimit(1)

			// Show actual shortcut to the right if there's a hint
			if let shortcut = shortcut {
				Text(shortcut)
					.font(.system(size: 11))
					.foregroundColor(.secondary)
					.lineLimit(1)
			}
		}
	}
}

// MARK: - Preview Chord Row

struct PreviewChordRow: View {
	@EnvironmentObject var controllerService: ControllerService

	let chord: ChordMapping
	let profile: Profile

	private var controllerPresentationState: ControllerPresentationState {
		controllerService.threadSafeControllerPresentationState
	}

	var body: some View {
		let presentationState = controllerPresentationState

		HStack(spacing: 12) {
			// Button icons - match main chord list spacing
			HStack(spacing: 4) {
				ForEach(Array(chord.buttons).sorted(by: { $0.category.chordDisplayOrder < $1.category.chordDisplayOrder }), id: \.self) { button in
					ButtonIconView(
						button: button,
						isPressed: false,
						isDualSense: presentationState.isPlayStation,
						isNintendo: presentationState.isNintendo,
						isSteamController: presentationState.isSteamController,
						isAppleTVRemote: presentationState.isAppleTVRemote,
						isEightBitDo: presentationState.eightBitDoModel != nil
					)
				}
			}

			Image(systemName: "arrow.right")
				.font(.system(size: 10))
				.foregroundColor(.secondary)

			// Action with hint + actual shortcut shown inline
			if let systemCommand = chord.systemCommand {
				chordActionLabel(
					text: chord.hint ?? systemCommand.displayName,
					shortcut: chord.hint != nil ? systemCommand.displayName : nil,
					color: .green.opacity(0.9)
				)
			} else if let macroId = chord.macroId,
					  let macroName = profile.macroDisplayName(for: macroId) {
				chordActionLabel(
					text: chord.hint ?? macroName,
					shortcut: chord.hint != nil ? "Macro: \(macroName)" : nil,
					color: .purple.opacity(0.9)
				)
			} else if let scriptId = chord.scriptId,
					  let script = profile.scripts.first(where: { $0.id == scriptId }) {
				chordActionLabel(
					text: chord.hint ?? script.name,
					shortcut: chord.hint != nil ? "Script: \(script.name)" : nil,
					color: .primary
				)
			} else {
				chordActionLabel(
					text: chord.hint ?? chord.actionDisplayString,
					shortcut: chord.hint != nil ? chord.actionDisplayString : nil,
					color: .primary
				)
			}

			Spacer()
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
		.background(Color.white.opacity(0.03))
		.cornerRadius(6)
		.padding(.horizontal, 8)
	}

	@ViewBuilder
	private func chordActionLabel(text: String, shortcut: String?, color: Color) -> some View {
		HStack(spacing: 8) {
			Text(text)
				.font(.system(size: 12, weight: .medium))
				.foregroundColor(color)

			if let shortcut = shortcut {
				Text(shortcut)
					.font(.system(size: 11))
					.foregroundColor(.secondary)
			}
		}
	}
}
