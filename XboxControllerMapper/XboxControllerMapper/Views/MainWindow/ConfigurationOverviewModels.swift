import Foundation

enum ConfigurationOverviewFilter: String, CaseIterable, Identifiable {
	case all = "All"
	case controls = "Controls"
	case triggers = "Triggers"
	case wheel = "Wheel"
	case settings = "Settings"
	case automations = "Automations"

	var id: String { rawValue }
	var localizedLabel: String { String(localized: String.LocalizationValue(rawValue)) }

	var category: ConfigurationOverviewCategory? {
		switch self {
		case .all: return nil
		case .controls: return .controls
		case .triggers: return .triggers
		case .wheel: return .wheel
		case .settings: return .settings
		case .automations: return .automations
		}
	}

	var emptyConfiguration: ConfigurationOverviewEmptyState {
		switch self {
		case .all, .controls:
			return ConfigurationOverviewEmptyState(
				title: String(localized: "No Mappings Yet"),
				description: String(localized: "Open the visual editor and choose a controller control to create the first mapping."),
				action: String(localized: "Open Visual Editor"),
				target: .section(MainWindowSection.buttons.rawValue)
			)
		case .triggers:
			return ConfigurationOverviewEmptyState(
				title: String(localized: "No Advanced Triggers Yet"),
				description: String(localized: "Create a chord, sequence, or motion gesture in its editor."),
				action: String(localized: "Open Chords"),
				target: .section(MainWindowSection.chords.rawValue)
			)
		case .wheel:
			return ConfigurationOverviewEmptyState(
				title: String(localized: "No Wheel Actions Yet"),
				description: String(localized: "Add the first action in Command Wheel settings."),
				action: String(localized: "Open Command Wheel"),
				target: .section(MainWindowSection.wheel.rawValue)
			)
		case .settings:
			return ConfigurationOverviewEmptyState(
				title: String(localized: "No Hardware Settings Available"),
				description: String(localized: "Review input settings for the current controller."),
				action: String(localized: "Open Input Settings"),
				target: .section(MainWindowSection.input.rawValue)
			)
		case .automations:
			return ConfigurationOverviewEmptyState(
				title: String(localized: "No Automations Yet"),
				description: String(localized: "Create a macro or script, then assign it to a control."),
				action: String(localized: "Open Macros"),
				target: .section(MainWindowSection.macros.rawValue)
			)
		}
	}
}

struct ConfigurationOverviewEmptyState {
	let title: String
	let description: String
	let action: String
	let target: ConfigurationOverviewTarget
}

enum ConfigurationOverviewEmptyStatePolicy {
	static func showsUnavailableOnlyState(
		rows: [ConfigurationOverviewRow],
		query: String
	) -> Bool {
		!rows.isEmpty
			&& !rows.contains(where: \.isCurrentDevice)
			&& query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
}

enum ConfigurationOverviewCategory: String, CaseIterable, Identifiable {
	case controls = "Controls"
	case triggers = "Advanced Triggers"
	case wheel = "Command Wheel"
	case settings = "Layer & Hardware"
	case automations = "Automation Library"

	var id: String { rawValue }

	var localizedLabel: String {
		switch self {
		case .controls: return String(localized: "Controls")
		case .triggers: return String(localized: "Advanced Triggers")
		case .wheel: return String(localized: "Command Wheel")
		case .settings: return String(localized: "Layer & Hardware")
		case .automations: return String(localized: "Automation Library")
		}
	}

	var systemImage: String {
		switch self {
		case .controls: return "gamecontroller.fill"
		case .triggers: return "point.3.connected.trianglepath.dotted"
		case .wheel: return "circle.hexagongrid.fill"
		case .settings: return "slider.horizontal.3"
		case .automations: return "bolt.fill"
		}
	}
}

enum ConfigurationOverviewSource: Equatable {
	case base
	case inherited
	case override
	case profile
	case library

	var label: String {
		switch self {
		case .base: return String(localized: "Base")
		case .inherited: return String(localized: "Inherited")
		case .override: return String(localized: "Override")
		case .profile: return String(localized: "Profile")
		case .library: return String(localized: "Library")
		}
	}
}

enum ConfigurationOverviewTarget: Equatable {
	/// Scope captured with each row, preventing deferred sheet presentation
	/// from editing whichever layer becomes selected later.
	case button(ControllerButton, layerId: UUID?)
	case chord(UUID)
	case sequence(UUID)
	case gesture(MotionGestureType)
	case layer(UUID)
	case layerLED(UUID)
	case layerLinkedApps(profileId: UUID, layerId: UUID)
	case wheel(layerId: UUID?)
	case joysticks(layerId: UUID?, side: JoystickSide)
	case linkedApps(profileId: UUID)
	case linkedControllers(profileId: UUID)
	case section(Int)
}

struct ConfigurationOverviewRow: Identifiable, Equatable {
	let id: String
	let category: ConfigurationOverviewCategory
	let trigger: String
	let action: String
	let detail: String?
	let source: ConfigurationOverviewSource
	let systemImage: String
	let target: ConfigurationOverviewTarget
	let isCurrentDevice: Bool

	var accessibilitySummary: String {
		[trigger, action, detail, source.label]
			.compactMap { value in
				guard let value, !value.isEmpty else { return nil }
				return value
			}
			.joined(separator: ", ")
	}

	func matches(_ query: String) -> Bool {
		let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !normalized.isEmpty else { return true }
		return [trigger, action, detail, source.label, category.localizedLabel]
			.compactMap { $0?.lowercased() }
			.contains { $0.contains(normalized) }
	}
}

struct ConfigurationOverviewLayerSummary: Equatable {
	let id: UUID
	let name: String
	let activator: String?
	let activationStyle: String
	let overrideCount: Int
	let overrideDetails: [String]
}

struct ConfigurationOverviewSnapshot: Equatable {
	let profileName: String
	let scopeName: String
	let layer: ConfigurationOverviewLayerSummary?
	let rows: [ConfigurationOverviewRow]

	var mappedControlCount: Int {
		rows.filter { row in
			guard row.category == .controls, row.isCurrentDevice else { return false }
			if case .layer = row.target { return false }
			return true
		}.count
	}

	/// All usable control rows, including layer activators. This matches the
	/// count shown beside the Controls inventory.
	var configuredControlCount: Int {
		rows.filter { $0.category == .controls && $0.isCurrentDevice }.count
	}

	var advancedTriggerCount: Int {
		rows.filter { $0.category == .triggers && $0.isCurrentDevice }.count
	}

	var automationCount: Int {
		rows.filter { $0.category == .automations }.count
	}

	var commandWheelCount: Int {
		rows.filter {
			$0.category == .wheel && $0.isCurrentDevice && !$0.id.hasPrefix("wheel-disabled-")
		}.count
	}

	var settingCount: Int {
		rows.filter { $0.category == .settings && $0.isCurrentDevice }.count
	}

	var otherDeviceMappingCount: Int {
		rows.filter { !$0.isCurrentDevice }.count
	}
}

struct ProfileConfigurationCounts: Equatable {
	let baseControlCount: Int
	let layerOverrideCount: Int
	let advancedTriggerCount: Int
	let automationCount: Int
	let layerCount: Int

	var primarySummary: String {
		String(
			format: String(localized: "%lld controls · %lld triggers"),
			baseControlCount,
			advancedTriggerCount
		)
	}

	var secondarySummary: String? {
		var parts: [String] = []
		if layerCount > 0 {
			parts.append(String(format: String(localized: "%lld layers"), layerCount))
		}
		if layerOverrideCount > 0 {
			parts.append(String(format: String(localized: "%lld layer changes"), layerOverrideCount))
		}
		if automationCount > 0 {
			parts.append(String(format: String(localized: "%lld automations"), automationCount))
		}
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
	}
}

struct ConfigurationOverviewPresentation: Equatable {
	var isPlayStation = false
	var isDualSense = false
	var isDualSenseEdge = false
	var isDualShock = false
	var isXboxElite = false
	var isSteamController = false
	var isNintendo = false
	var isAppleTVRemote = false
	var isEightBitDo = false
	var isOuraRing = false
	var isBeamdeskHands = false
	var isStickless = false
	var hasTriggers = true
	var hasMotion = false
	var supportsCommandWheel = true
	var supportsPlayerAndMuteLEDs = true
	var supportedButtons = Set(ControllerButton.xboxButtons)
	var deviceName = "Xbox"

	func name(for button: ControllerButton) -> String {
		button.displayName(
			forDualSense: isPlayStation,
			forNintendo: isNintendo,
			forAppleTVRemote: isAppleTVRemote,
			forEightBitDo: isEightBitDo
		)
	}

	func supports(_ button: ControllerButton) -> Bool {
		supportedButtons.contains(button)
	}

	func supports(_ buttons: [ControllerButton]) -> Bool {
		!buttons.isEmpty && buttons.allSatisfy(supports)
	}

	var supportsMotionGestures: Bool { hasMotion }
	var supportsLeftStick: Bool {
		!isOuraRing && !isBeamdeskHands && !isAppleTVRemote && !isStickless
	}
	var supportsRightStick: Bool { supportsLeftStick }
}
