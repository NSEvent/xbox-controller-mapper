import Foundation

extension ConfigurationOverviewBuilder {
	static func baseStickRow(
		side: JoystickSide,
		tuning: StickTuning,
		source: ConfigurationOverviewSource,
		editingLayerId: UUID?,
		isCurrentDevice: Bool,
		presentation: ConfigurationOverviewPresentation
	) -> ConfigurationOverviewRow {
		ConfigurationOverviewRow(
			id: "base-stick-\(side.rawValue)",
			category: .settings,
			trigger: side == .left ? String(localized: "Left Stick") : String(localized: "Right Stick"),
			action: localizedDisplayName(tuning.mode.displayName),
			detail: availabilityDetail(
				stickDetail(tuning),
				isSupported: isCurrentDevice,
				presentation: presentation
			),
			source: source,
			systemImage: "circle.circle",
			target: .joysticks(layerId: editingLayerId, side: side),
			isCurrentDevice: isCurrentDevice
		)
	}

	static func stickOverrideRow(
		side: JoystickSide,
		tuning: StickTuningOverride,
		layerId: UUID,
		isCurrentDevice: Bool,
		presentation: ConfigurationOverviewPresentation
	) -> ConfigurationOverviewRow {
		let mode = tuning.mode.map { localizedDisplayName($0.displayName) }
		let fieldCount = overrideFieldCount(tuning)
		return ConfigurationOverviewRow(
			id: "layer-stick-\(side.rawValue)",
			category: .settings,
			trigger: side == .left ? String(localized: "Left Stick") : String(localized: "Right Stick"),
			action: mode ?? String(localized: "Custom tuning"),
			detail: availabilityDetail(
				String(
					format: String(localized: "%lld tuned values · the rest inherit from Base"),
					fieldCount
				),
				isSupported: isCurrentDevice,
				presentation: presentation
			),
			source: .override,
			systemImage: "slider.horizontal.3",
			target: .joysticks(layerId: layerId, side: side),
			isCurrentDevice: isCurrentDevice
		)
	}

	static func ledRow(
		settings: DualSenseLEDSettings,
		source: ConfigurationOverviewSource,
		layerId: UUID?,
		isCurrentDevice: Bool,
		presentation: ConfigurationOverviewPresentation
	) -> ConfigurationOverviewRow {
		ConfigurationOverviewRow(
			id: "led-\(source.label)",
			category: .settings,
			trigger: String(localized: "Controller LEDs"),
			action: settings.lightBarEnabled ? String(localized: "Light bar on") : String(localized: "Light bar off"),
			detail: availabilityDetail(
				ledDetail(settings, presentation: presentation),
				isSupported: isCurrentDevice,
				presentation: presentation
			),
			source: source,
			systemImage: "lightbulb.led.fill",
			target: layerId.map(ConfigurationOverviewTarget.layerLED)
				?? .section(MainWindowSection.leds.rawValue),
			isCurrentDevice: isCurrentDevice
		)
	}

	private static func stickDetail(_ tuning: StickTuning) -> String {
		switch tuning.mode {
		case .mouse:
			return String(format: String(localized: "Sensitivity %.0f%% · acceleration %.0f%% · deadzone %.0f%%"), tuning.mouseSensitivity * 100, tuning.mouseAcceleration * 100, tuning.mouseDeadzone * 100)
		case .scroll:
			return String(format: String(localized: "Sensitivity %.0f%% · acceleration %.0f%% · deadzone %.0f%%"), tuning.scrollSensitivity * 100, tuning.scrollAcceleration * 100, tuning.scrollDeadzone * 100)
		case .custom:
			return String(format: String(localized: "%@ directions · deadzone %.0f%%"), localizedDisplayName(tuning.customDirectionLayout.displayName), tuning.customDeadzone * 100)
		default:
			return String(localized: "Base stick behavior and tuning")
		}
	}

	private static func overrideFieldCount(_ tuning: StickTuningOverride) -> Int {
		[
			tuning.mode != nil,
			tuning.mouseSensitivity != nil,
			tuning.mouseAcceleration != nil,
			tuning.mouseDeadzone != nil,
			tuning.invertMouseY != nil,
			tuning.scrollSensitivity != nil,
			tuning.scrollAcceleration != nil,
			tuning.scrollDeadzone != nil,
			tuning.invertScrollX != nil,
			tuning.invertScrollY != nil,
			tuning.customDirectionLayout != nil,
			tuning.customHorizontalSliceSize != nil,
			tuning.customVerticalSliceSize != nil,
			tuning.customDeadzone != nil,
		].filter { $0 }.count
	}

	private static func ledDetail(
		_ settings: DualSenseLEDSettings,
		presentation: ConfigurationOverviewPresentation
	) -> String {
		let color = settings.batteryLightBar
			? String(localized: "battery color")
			: String(format: "#%02X%02X%02X", settings.lightBarColor.redByte, settings.lightBarColor.greenByte, settings.lightBarColor.blueByte)
		guard presentation.supportsPlayerAndMuteLEDs else {
			let unsupportedDetail = presentation.isDualShock
				? String(localized: "Player and mute LEDs unavailable on DualShock 4")
				: String(localized: "Player and mute LEDs unavailable over Bluetooth")
			return [
				color,
				localizedDisplayName(settings.lightBarBrightness.displayName),
				unsupportedDetail
			].joined(separator: " · ")
		}
		return String(
			format: String(localized: "%@ · %@ · player LEDs %lld · mute %@"),
			color,
			localizedDisplayName(settings.lightBarBrightness.displayName),
			settings.playerLEDs.bitmask,
			localizedDisplayName(settings.muteButtonLED.displayName)
		)
	}
}
