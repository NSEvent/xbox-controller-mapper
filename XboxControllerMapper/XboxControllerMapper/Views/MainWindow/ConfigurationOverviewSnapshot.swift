import Foundation
import TriggerKitCore

enum ConfigurationOverviewBuilder {
	static func counts(for profile: Profile) -> ProfileConfigurationCounts {
		ProfileConfigurationCounts(
			baseControlCount: profile.buttonMappings.values.filter(\.hasConfiguredBehavior).count,
			layerOverrideCount: profile.layers.reduce(0) { count, layer in
				count + layerConfigurationCount(layer, profile: profile)
			},
			advancedTriggerCount: profile.chordMappings.filter(\.hasAction).count
				+ profile.sequenceMappings.filter(\.hasAction).count
				+ profile.gestureMappings.filter(\.hasAction).count,
			automationCount: profile.macros.count + profile.scripts.count + profile.sharedMacroSnapshots.count,
			layerCount: profile.layers.count
		)
	}

	static func make(
		profile: Profile,
		selectedLayerId: UUID?,
		presentation: ConfigurationOverviewPresentation,
		sharedLibraryMacros: [AutomationMacro] = []
	) -> ConfigurationOverviewSnapshot {
		let selectedLayer = selectedLayerId.flatMap { id in
			profile.layers.first { $0.id == id }
		}
		// Runtime resolves shared macros from the live library before falling
		// back to the profile snapshot. Mirror that naming precedence in every
		// mapped-action summary without adding unrelated library items to the
		// profile's automation inventory.
		var actionDisplayProfile = profile
		for libraryMacro in sharedLibraryMacros {
			var liveProgram = libraryMacro.program
			liveProgram.name = libraryMacro.name
			actionDisplayProfile.sharedMacroSnapshots[libraryMacro.id] = liveProgram
		}

		let layerSummary = selectedLayer.map { layer in
			let detail = layerOverrideDetails(layer, profile: profile)
			return ConfigurationOverviewLayerSummary(
				id: layer.id,
				name: layer.name,
				activator: layer.activatorButton.map(presentation.name(for:)),
				activationStyle: layer.activationStyle.displayName,
				overrideCount: layerConfigurationCount(layer, profile: profile),
				overrideDetails: detail
			)
		}

		var rows = controlRows(
			profile: actionDisplayProfile,
			selectedLayer: selectedLayer,
			presentation: presentation
		)
		rows.append(contentsOf: triggerRows(
			profile: actionDisplayProfile,
			selectedLayer: selectedLayer,
			presentation: presentation
		))
		rows.append(contentsOf: wheelRows(
			profile: actionDisplayProfile,
			selectedLayer: selectedLayer,
			presentation: presentation
		))
		rows.append(contentsOf: settingsRows(
			profile: profile,
			selectedLayer: selectedLayer,
			presentation: presentation
		))
		rows.append(contentsOf: legacyTouchpadRows(profile: actionDisplayProfile, presentation: presentation))
		rows.append(contentsOf: automationRows(profile: profile, sharedLibraryMacros: sharedLibraryMacros))

		return ConfigurationOverviewSnapshot(
			profileName: profile.name,
			scopeName: selectedLayer?.name ?? String(localized: "Base"),
			layer: layerSummary,
			rows: rows
		)
	}

	static func filteredRows(
		_ rows: [ConfigurationOverviewRow],
		category: ConfigurationOverviewCategory?,
		query: String
	) -> [ConfigurationOverviewRow] {
		rows.filter { row in
			(category == nil || row.category == category) && row.matches(query)
		}
	}

	private static func controlRows(
		profile: Profile,
		selectedLayer: Layer?,
		presentation: ConfigurationOverviewPresentation
	) -> [ConfigurationOverviewRow] {
		let layerActivatorMap = MappingProfileIndex(profile: profile).layerActivatorMap
		var buttons = Set(profile.buttonMappings.keys)
		if let selectedLayer {
			buttons.formUnion(selectedLayer.buttonMappings.keys)
			if let activator = selectedLayer.activatorButton { buttons.insert(activator) }
		} else {
			buttons.formUnion(profile.layers.compactMap(\.activatorButton))
		}

		return ControllerButton.allCases.flatMap { button -> [ConfigurationOverviewRow] in
			guard buttons.contains(button) else { return [] }
			var result: [ConfigurationOverviewRow] = []

			if let selectedLayer, selectedLayer.activatorButton == button {
				let winningLayer = layerActivatorMap[button]
					.flatMap { winnerId in
						winnerId == selectedLayer.id
							? nil
							: profile.layers.first(where: { $0.id == winnerId })
					}
				result.append(layerActivatorRow(
					button: button,
					layer: selectedLayer,
					shadowedBy: winningLayer?.name,
					presentation: presentation
				))
				// The runtime consumes the winning activator. A shadowed layer can
				// still become active through app activation, in which case this
				// button falls through to that layer's mapping or Base mapping.
				if winningLayer == nil { return result }
			}

			if selectedLayer == nil,
			   let activatedLayerId = layerActivatorMap[button],
			   let activatedLayer = profile.layers.first(where: { $0.id == activatedLayerId }) {
				return [layerActivatorRow(
					button: button,
					layer: activatedLayer,
					shadowedBy: nil,
					presentation: presentation
				)]
			}

			let mapping: KeyMapping
			let source: ConfigurationOverviewSource
			if let selectedLayer,
			   let layerMapping = selectedLayer.buttonMappings[button],
			   layerMapping.hasConfiguredBehavior {
				mapping = layerMapping
				source = .override
			} else if let baseMapping = profile.buttonMappings[button], baseMapping.hasConfiguredBehavior {
				mapping = baseMapping
				source = selectedLayer == nil ? .base : .inherited
			} else {
				return result
			}

			let isCurrent = controlIsCurrent(
				button: button,
				profile: profile,
				selectedLayer: selectedLayer,
				presentation: presentation
			)
			result.append(ConfigurationOverviewRow(
				id: "button-\(button.rawValue)",
				category: .controls,
				trigger: presentation.name(for: button),
				action: buttonActionName(mapping, profile: profile),
				detail: availabilityDetail(
					buttonDetail(mapping, profile: profile),
					isSupported: isCurrent,
					presentation: presentation
				),
				source: source,
				systemImage: "button.programmable",
				target: .button(button, layerId: selectedLayer?.id),
				isCurrentDevice: isCurrent
			))
			return result
		}
	}

	private static func controlIsCurrent(
		button: ControllerButton,
		profile: Profile,
		selectedLayer: Layer?,
		presentation: ConfigurationOverviewPresentation
	) -> Bool {
		guard presentation.supports(button) else { return false }

		let effectiveTouchpadMode = presentation.isAppleTVRemote
			? TouchpadInputMode.wholePad
			: profile.touchpadInputMode
		if button.isTouchpadQuadrant {
			return effectiveTouchpadMode == .quadrants
		}
		let wholePadButtons: Set<ControllerButton> = [
			.touchpadButton, .touchpadTap,
			.leftTouchpadButton, .leftTouchpadTap,
			.rightTouchpadButton, .rightTouchpadTap,
		]
		if wholePadButtons.contains(button) {
			return effectiveTouchpadMode == .wholePad
		}

		if let side = button.joystickSide {
			let base = profile.joystickSettings.stick(side)
			let layerOverride = side == .left
				? selectedLayer?.leftStickTuning
				: selectedLayer?.rightStickTuning
			return (layerOverride?.applied(to: base) ?? base).mode.exposesJoystickDirections
		}

		let isLogicalPaddle = !button.physicalEquivalentButtons.isEmpty
		if presentation.isXboxElite || presentation.isSteamController,
		   button.isXboxEliteOnly || isLogicalPaddle {
			let activators = MappingProfileIndex(profile: profile).layerActivatorMap
			let activeLayerIds = selectedLayer.map { [$0.id] } ?? []
			let reachable = Set(ControllerButton.xboxEliteButtons.map { physical in
				ButtonMappingResolutionPolicy.resolvedButton(
					button: physical,
					profile: profile,
					activeLayerIds: activeLayerIds,
					layerActivatorMap: activators
				)
			})
			return reachable.contains(button)
		}

		return true
	}

	private static func layerActivatorRow(
		button: ControllerButton,
		layer: Layer,
		shadowedBy winningLayerName: String?,
		presentation: ConfigurationOverviewPresentation
	) -> ConfigurationOverviewRow {
		let action: String
		if let winningLayerName {
			action = String(format: String(localized: "Overridden by layer %@"), winningLayerName)
		} else {
			action = layer.activationStyle == .hold
				? String(format: String(localized: "Hold for %@"), layer.name)
				: String(format: String(localized: "Toggle %@"), layer.name)
		}
		return ConfigurationOverviewRow(
			id: "layer-activator-\(layer.id.uuidString)",
			category: .controls,
			trigger: presentation.name(for: button),
			action: action,
			detail: winningLayerName == nil
				? String(localized: "Layer activator")
				: String(localized: "Duplicate layer activator"),
			source: .profile,
			systemImage: "square.stack.3d.up.fill",
			target: .layer(layer.id),
			isCurrentDevice: presentation.supports(button)
		)
	}

	private static func triggerRows(
		profile: Profile,
		selectedLayer: Layer?,
		presentation: ConfigurationOverviewPresentation
	) -> [ConfigurationOverviewRow] {
		let chords = profile.chordMappings.compactMap { chord -> ConfigurationOverviewRow? in
			guard chord.hasAction else { return nil }
			let isSupported = chord.buttons.allSatisfy {
				controlIsCurrent(
					button: $0,
					profile: profile,
					selectedLayer: selectedLayer,
					presentation: presentation
				)
			}
			let trigger = chord.buttons
				.sorted { $0.rawValue < $1.rawValue }
				.map(presentation.name(for:))
				.joined(separator: " + ")
			return ConfigurationOverviewRow(
				id: "chord-\(chord.id.uuidString)",
				category: .triggers,
				trigger: trigger,
				action: actionName(chord, profile: profile),
				detail: availabilityDetail(
					actionDetail(chord, prefix: String(localized: "Chord · press together"), profile: profile),
					isSupported: isSupported,
					presentation: presentation
				),
				source: .profile,
				systemImage: "link",
				target: .chord(chord.id),
				isCurrentDevice: isSupported
			)
		}

		let sequences = profile.sequenceMappings.compactMap { sequence -> ConfigurationOverviewRow? in
			guard sequence.hasAction else { return nil }
			let isSupported = sequence.steps.allSatisfy {
				controlIsCurrent(
					button: $0,
					profile: profile,
					selectedLayer: selectedLayer,
					presentation: presentation
				)
			}
			let trigger = sequence.steps
				.map(presentation.name(for:))
				.joined(separator: " → ")
			return ConfigurationOverviewRow(
				id: "sequence-\(sequence.id.uuidString)",
				category: .triggers,
				trigger: trigger,
				action: actionName(sequence, profile: profile),
				detail: availabilityDetail(
					actionDetail(sequence, prefix: String(localized: "Sequence · press in order"), profile: profile),
					isSupported: isSupported,
					presentation: presentation
				),
				source: .profile,
				systemImage: "point.3.connected.trianglepath.dotted",
				target: .sequence(sequence.id),
				isCurrentDevice: isSupported
			)
		}

		let gestures = profile.gestureMappings.compactMap { gesture -> ConfigurationOverviewRow? in
			guard gesture.hasAction else { return nil }
			let isSupported = presentation.supportsMotionGestures
			return ConfigurationOverviewRow(
				id: "gesture-\(gesture.id.uuidString)",
				category: .triggers,
				trigger: String(localized: String.LocalizationValue(gesture.gestureType.displayName)),
				action: actionName(gesture, profile: profile),
				detail: availabilityDetail(
					actionDetail(gesture, prefix: String(localized: "Motion gesture"), profile: profile),
					isSupported: isSupported,
					presentation: presentation
				),
				source: .profile,
				systemImage: gesture.gestureType.iconName,
				target: .gesture(gesture.gestureType),
				isCurrentDevice: isSupported
			)
		}

		return chords + sequences + gestures
	}

	private static func wheelRows(
		profile: Profile,
		selectedLayer: Layer?,
		presentation: ConfigurationOverviewPresentation
	) -> [ConfigurationOverviewRow] {
		let actions: [CommandWheelAction]
		let source: ConfigurationOverviewSource
		if let selectedLayer, let overrides = selectedLayer.commandWheelActions {
			if overrides.isEmpty {
				return [ConfigurationOverviewRow(
					id: "wheel-disabled-\(selectedLayer.id.uuidString)",
					category: .wheel,
					trigger: String(localized: "Command Wheel"),
					action: String(localized: "Disabled in this layer"),
					detail: availabilityDetail(
						String(localized: "Overrides the Base command wheel"),
						isSupported: presentation.supportsCommandWheel,
						presentation: presentation
					),
					source: .override,
					systemImage: "nosign",
					target: .wheel(layerId: selectedLayer.id),
					isCurrentDevice: presentation.supportsCommandWheel
				)]
			}
			actions = overrides
			source = .override
		} else {
			actions = profile.commandWheelActions
			source = selectedLayer == nil ? .base : .inherited
		}

		return actions.enumerated().compactMap { index, action in
			guard action.hasAction else { return nil }
			let slotName = action.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
			return ConfigurationOverviewRow(
				id: "wheel-\(selectedLayer?.id.uuidString ?? "base")-\(action.id.uuidString)",
				category: .wheel,
				trigger: slotName.isEmpty
					? String(format: String(localized: "Wheel Slot %lld"), index + 1)
					: slotName,
				action: actionName(action, profile: profile),
				detail: availabilityDetail(
					actionDetail(action, prefix: String(localized: "Command wheel action"), profile: profile),
					isSupported: presentation.supportsCommandWheel,
					presentation: presentation
				),
				source: source,
				systemImage: action.iconName ?? "circle.hexagongrid",
				target: .wheel(layerId: selectedLayer?.id),
				isCurrentDevice: presentation.supportsCommandWheel
			)
		}
	}

	private static func legacyTouchpadRows(
		profile: Profile,
		presentation: ConfigurationOverviewPresentation
	) -> [ConfigurationOverviewRow] {
		profile.touchpadRegionMappings.compactMap { mapping in
			guard !mapping.isEmpty else { return nil }
			let underlying = legacyTouchpadActionName(mapping, profile: profile, preferHint: false)
			let hint = mapping.hint?.trimmingCharacters(in: .whitespacesAndNewlines)
			return ConfigurationOverviewRow(
				id: "legacy-touchpad-\(mapping.id.uuidString)",
				category: .controls,
				trigger: "\(String(localized: String.LocalizationValue(mapping.region.displayName))) · \(String(localized: String.LocalizationValue(mapping.triggerMode.displayName)))",
				action: legacyTouchpadActionName(mapping, profile: profile, preferHint: true),
				detail: availabilityDetail(hint?.isEmpty == false && hint != underlying
					? String(format: String(localized: "Legacy touchpad region · %@"), underlying)
					: String(localized: "Legacy touchpad region"),
					isSupported: presentation.isPlayStation,
					presentation: presentation),
				source: .base,
				systemImage: "rectangle.split.2x2",
				target: .section(MainWindowSection.touchpad.rawValue),
				isCurrentDevice: presentation.isPlayStation
			)
		}
	}

	static func availabilityDetail(
		_ detail: String?,
		isSupported: Bool,
		presentation: ConfigurationOverviewPresentation
	) -> String? {
		guard !isSupported else { return detail }
		let note = String(
			format: String(localized: "Not available on %@"),
			presentation.deviceName
		)
		guard let detail, !detail.isEmpty else { return note }
		return "\(note) · \(detail)"
	}

}
