import Foundation

extension ConfigurationOverviewBuilder {
	static func settingsRows(
		profile: Profile,
		selectedLayer: Layer?,
		presentation: ConfigurationOverviewPresentation
	) -> [ConfigurationOverviewRow] {
		var rows: [ConfigurationOverviewRow] = []

		if let selectedLayer {
			if let tuning = selectedLayer.leftStickTuning, !tuning.isEmpty {
				rows.append(stickOverrideRow(
					side: .left,
					tuning: tuning,
					layerId: selectedLayer.id,
					isCurrentDevice: presentation.supportsLeftStick,
					presentation: presentation
				))
			} else if presentation.supportsLeftStick
				|| profile.joystickSettings.leftStick != .leftDefault {
				rows.append(baseStickRow(
					side: .left,
					tuning: profile.joystickSettings.leftStick,
					source: .inherited,
					editingLayerId: selectedLayer.id,
					isCurrentDevice: presentation.supportsLeftStick,
					presentation: presentation
				))
			}
			if let tuning = selectedLayer.rightStickTuning, !tuning.isEmpty {
				rows.append(stickOverrideRow(
					side: .right,
					tuning: tuning,
					layerId: selectedLayer.id,
					isCurrentDevice: presentation.supportsRightStick,
					presentation: presentation
				))
			} else if presentation.supportsRightStick
				|| profile.joystickSettings.rightStick != .rightDefault {
				rows.append(baseStickRow(
					side: .right,
					tuning: profile.joystickSettings.rightStick,
					source: .inherited,
					editingLayerId: selectedLayer.id,
					isCurrentDevice: presentation.supportsRightStick,
					presentation: presentation
				))
			}
			if let led = selectedLayer.dualSenseLEDSettings {
				rows.append(ledRow(
					settings: led,
					source: .override,
					layerId: selectedLayer.id,
					isCurrentDevice: presentation.isPlayStation,
					presentation: presentation
				))
			} else if presentation.isPlayStation
				|| profile.dualSenseLEDSettings != .default {
				rows.append(ledRow(
					settings: profile.dualSenseLEDSettings,
					source: .inherited,
					layerId: selectedLayer.id,
					isCurrentDevice: presentation.isPlayStation,
					presentation: presentation
				))
			}

			let apps = profile.appLayerBindings
				.filter { $0.value == selectedLayer.id }
				.map(\.key)
				.sorted()
			rows.append(ConfigurationOverviewRow(
				id: "layer-apps-\(selectedLayer.id.uuidString)",
				category: .settings,
				trigger: String(localized: "Automatic Activation"),
				action: String(format: String(localized: "%lld linked apps"), apps.count),
				detail: apps.isEmpty ? nil : apps.joined(separator: ", "),
				source: apps.isEmpty ? .profile : .override,
				systemImage: "app.badge.checkmark",
				target: .layerLinkedApps(profileId: profile.id, layerId: selectedLayer.id),
				isCurrentDevice: true
			))
		} else {
			if presentation.supportsLeftStick || profile.joystickSettings.leftStick != .leftDefault {
				rows.append(baseStickRow(
					side: .left,
					tuning: profile.joystickSettings.leftStick,
					source: .base,
					editingLayerId: nil,
					isCurrentDevice: presentation.supportsLeftStick,
					presentation: presentation
				))
			}
			if presentation.supportsRightStick || profile.joystickSettings.rightStick != .rightDefault {
				rows.append(baseStickRow(
					side: .right,
					tuning: profile.joystickSettings.rightStick,
					source: .base,
					editingLayerId: nil,
					isCurrentDevice: presentation.supportsRightStick,
					presentation: presentation
				))
			}
			if presentation.isPlayStation || profile.dualSenseLEDSettings != .default {
				rows.append(ledRow(
					settings: profile.dualSenseLEDSettings,
					source: .base,
					layerId: nil,
					isCurrentDevice: presentation.isPlayStation,
					presentation: presentation
				))
			}
		}
		rows.append(contentsOf: profileSettingRows(profile: profile, presentation: presentation))

		return rows
	}

	private static func profileSettingRows(
		profile: Profile,
		presentation: ConfigurationOverviewPresentation
	) -> [ConfigurationOverviewRow] {
		var rows: [ConfigurationOverviewRow] = [
			settingRow(
				id: "dpad-preset",
				trigger: String(localized: "D-Pad Preset"),
				action: localizedDisplayName(profile.dpadPreset.displayName),
				detail: profile.dpadPresetWasExplicitlySelected
					? String(localized: "Explicitly selected")
					: String(localized: "Derived from individual mappings"),
				systemImage: "dpad.fill",
				target: .section(MainWindowSection.buttons.rawValue),
				isCurrentDevice: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight].allSatisfy(presentation.supports)
			),
			settingRow(
				id: "preview-layout",
				trigger: String(localized: "Controller Preview"),
				action: localizedDisplayName(profile.controllerPreviewLayout.displayName),
				detail: String(localized: "Visual editor layout"),
				systemImage: "gamecontroller",
				target: .section(MainWindowSection.buttons.rawValue)
			),
			settingRow(
				id: "input-latency",
				trigger: String(localized: "Input Latency"),
				action: localizedDisplayName(profile.inputLatencyMode.displayName),
				detail: String(localized: "Simple key dispatch mode"),
				systemImage: "speedometer",
				target: .section(MainWindowSection.input.rawValue)
			),
			keyboardRow(profile),
		]
		let settings = profile.joystickSettings
		let motionSupported = presentation.supportsMotionGestures
		let touchSurfaceSupported = presentation.isPlayStation
			|| presentation.isSteamController
			|| presentation.isAppleTVRemote
		let defaults = JoystickSettings.default
		let hasSavedAnalogPrecision = settings.analogPrecisionTriggerMode != defaults.analogPrecisionTriggerMode
			|| settings.analogPrecisionMinimumSpeed != defaults.analogPrecisionMinimumSpeed
			|| settings.analogPrecisionDeadzone != defaults.analogPrecisionDeadzone
			|| settings.analogPrecisionCurve != defaults.analogPrecisionCurve
		let hasSavedTouchpadTuning = settings.touchpadSensitivity != defaults.touchpadSensitivity
			|| settings.touchpadAcceleration != defaults.touchpadAcceleration
			|| settings.touchpadDeadzone != defaults.touchpadDeadzone
			|| settings.touchpadSmoothing != defaults.touchpadSmoothing
			|| settings.touchpadPanSensitivity != defaults.touchpadPanSensitivity
			|| settings.touchpadInvertScrollX != defaults.touchpadInvertScrollX
			|| settings.touchpadInvertScrollY != defaults.touchpadInvertScrollY
			|| settings.touchpadZoomToPanRatio != defaults.touchpadZoomToPanRatio
			|| settings.touchpadUseNativeZoom != defaults.touchpadUseNativeZoom
			|| settings.disableTouchpadAsMouse != defaults.disableTouchpadAsMouse
			|| settings.requireActiveTouchForRegionClick != defaults.requireActiveTouchForRegionClick
		let hasSavedMotionTuning = settings.gestureSensitivity != defaults.gestureSensitivity
			|| settings.gestureCooldown != defaults.gestureCooldown
			|| settings.gyroAimingEnabled != defaults.gyroAimingEnabled
			|| settings.gyroActivationMode != defaults.gyroActivationMode
			|| settings.gyroAimingSensitivity != defaults.gyroAimingSensitivity
			|| settings.gyroAimingDeadzone != defaults.gyroAimingDeadzone
		let hasSavedAppleTVTuning = settings.appleTVRemoteCircularScrollEnabled != defaults.appleTVRemoteCircularScrollEnabled
			|| settings.appleTVRemoteCircularInputMode != defaults.appleTVRemoteCircularInputMode
			|| settings.appleTVRemoteCircularScrollSensitivity != defaults.appleTVRemoteCircularScrollSensitivity

		rows.append(settingRow(
			id: "focus-mode",
			trigger: String(localized: "Focus Mode"),
			action: String(format: String(localized: "%.0f%% cursor speed"), settings.focusModeSensitivity * 100),
			detail: String(
				format: String(localized: "%@ activation · haptics %@"),
				modifierDescription(settings.focusModeModifier),
				settings.focusModeHapticsEnabled ? String(localized: "on") : String(localized: "off")
			),
			systemImage: "scope",
			target: .section(MainWindowSection.joysticks.rawValue)
		))

		if presentation.hasTriggers || hasSavedAnalogPrecision {
			rows.append(settingRow(
				id: "analog-precision",
				trigger: String(localized: "Analog Trigger Precision"),
				action: localizedDisplayName(settings.analogPrecisionTriggerMode.displayName),
				detail: ConfigurationOverviewBuilder.availabilityDetail(
					String(
						format: String(localized: "Minimum %.0f%% · deadzone %.0f%% · curve %.0f%%"),
						settings.analogPrecisionMinimumSpeed * 100,
						settings.analogPrecisionDeadzone * 100,
						settings.analogPrecisionCurve * 100
					),
					isSupported: presentation.hasTriggers,
					presentation: presentation
				),
				systemImage: "gauge.with.dots.needle.33percent",
				target: .section(MainWindowSection.joysticks.rawValue),
				isCurrentDevice: presentation.hasTriggers
			))
		}

		rows.append(settingRow(
			id: "pointer-lock",
			trigger: String(localized: "Pointer-Lock Aiming"),
			action: localizedDisplayName(settings.pointerLockMouseMode.displayName),
			detail: String(localized: "Relative mouse behavior for captured-cursor games"),
			systemImage: "scope",
			target: .section(MainWindowSection.joysticks.rawValue)
		))

		if presentation.supportsRightStick || settings.scrollBoostMultiplier != defaults.scrollBoostMultiplier {
			rows.append(settingRow(
				id: "scroll-boost",
				trigger: String(localized: "Scroll Boost"),
				action: String(format: String(localized: "%.1f× speed"), settings.scrollBoostMultiplier),
				detail: ConfigurationOverviewBuilder.availabilityDetail(
					String(localized: "Right-stick double-tap scroll multiplier"),
					isSupported: presentation.supportsRightStick,
					presentation: presentation
				),
				systemImage: "arrow.up.and.down.circle",
				target: .section(MainWindowSection.joysticks.rawValue),
				isCurrentDevice: presentation.supportsRightStick
			))
		}

		if touchSurfaceSupported || hasSavedTouchpadTuning {
			rows.append(settingRow(
				id: "touchpad-cursor",
				trigger: String(localized: "Touchpad Cursor & Gestures"),
				action: settings.disableTouchpadAsMouse ? String(localized: "Cursor off") : String(localized: "Cursor on"),
				detail: ConfigurationOverviewBuilder.availabilityDetail(
					String(
						format: String(localized: "Sensitivity %.0f%% · pan %.0f%% · smoothing %.0f%%"),
						settings.touchpadSensitivity * 100,
						settings.touchpadPanSensitivity * 100,
						settings.touchpadSmoothing * 100
					),
					isSupported: touchSurfaceSupported,
					presentation: presentation
				),
				systemImage: "hand.draw",
				target: .section(MainWindowSection.touchpad.rawValue),
				isCurrentDevice: touchSurfaceSupported
			))
		}

		if motionSupported || hasSavedMotionTuning {
			rows.append(settingRow(
				id: "motion-gesture-tuning",
				trigger: String(localized: "Motion Gesture Tuning"),
				action: String(format: String(localized: "%.0f%% sensitivity"), settings.gestureSensitivity * 100),
				detail: ConfigurationOverviewBuilder.availabilityDetail(
					String(format: String(localized: "%.2f s cooldown"), settings.gestureCooldown),
					isSupported: motionSupported,
					presentation: presentation
				),
				systemImage: "gyroscope",
				target: .section(MainWindowSection.gestures.rawValue),
				isCurrentDevice: motionSupported
			))
			rows.append(settingRow(
				id: "gyro-aiming",
				trigger: String(localized: "Gyro Aiming"),
				action: settings.gyroAimingEnabled ? String(localized: "Enabled") : String(localized: "Disabled"),
				detail: ConfigurationOverviewBuilder.availabilityDetail(
					String(
						format: String(localized: "%@ · sensitivity %.0f%% · deadzone %.0f%%"),
						localizedDisplayName(settings.gyroActivationMode.displayName),
						settings.gyroAimingSensitivity * 100,
						settings.gyroAimingDeadzone * 100
					),
					isSupported: motionSupported,
					presentation: presentation
				),
				systemImage: "scope",
				target: .section(MainWindowSection.gestures.rawValue),
				isCurrentDevice: motionSupported
			))
		}

		if presentation.isOuraRing || settings.ouraMotion != .default {
			rows.append(settingRow(
				id: "oura-motion",
				trigger: String(localized: "Oura Motion"),
				action: localizedDisplayName(profile.ouraMotionOutputMode.displayName),
				detail: ConfigurationOverviewBuilder.availabilityDetail(
					String(
						format: String(localized: "%@ · sensitivity %.0f%% · deadzone %.0f%%"),
						localizedDisplayName(settings.ouraMotion.orientation.displayName),
						settings.ouraMotion.sensitivity * 100,
						settings.ouraMotion.deadzone * 100
					),
					isSupported: presentation.isOuraRing,
					presentation: presentation
				),
				systemImage: "circle.dotted.circle",
				target: .section(MainWindowSection.ring.rawValue),
				isCurrentDevice: presentation.isOuraRing
			))
		}

		if presentation.isAppleTVRemote || hasSavedAppleTVTuning {
			rows.append(settingRow(
				id: "apple-tv-edge-input",
				trigger: String(localized: "Clickpad Edge Input"),
				action: settings.appleTVRemoteCircularScrollEnabled
					? localizedDisplayName(settings.appleTVRemoteCircularInputMode.displayName)
					: String(localized: "Disabled"),
				detail: ConfigurationOverviewBuilder.availabilityDetail(
					String(format: String(localized: "%.0f%% sensitivity"), settings.appleTVRemoteCircularScrollSensitivity * 100),
					isSupported: presentation.isAppleTVRemote,
					presentation: presentation
				),
				systemImage: "circle.dashed",
				target: .section(MainWindowSection.touchpad.rawValue),
				isCurrentDevice: presentation.isAppleTVRemote
			))
		}

		if !profile.linkedApps.isEmpty {
			rows.append(settingRow(
				id: "profile-app-links",
				trigger: String(localized: "Profile Auto-Switch"),
				action: String(format: String(localized: "%lld linked apps"), profile.linkedApps.count),
				detail: profile.linkedApps.sorted().joined(separator: ", "),
				systemImage: "app.badge.checkmark",
				target: .linkedApps(profileId: profile.id)
			))
		}
		if !profile.linkedControllers.isEmpty {
			rows.append(settingRow(
				id: "profile-controller-links",
				trigger: String(localized: "Controller Auto-Switch"),
				action: String(format: String(localized: "%lld linked controllers"), profile.linkedControllers.count),
				detail: profile.linkedControllers.map(\.displayName).joined(separator: ", "),
				systemImage: "gamecontroller.fill",
				target: .linkedControllers(profileId: profile.id)
			))
		}

		let touchpadSupported = presentation.isPlayStation || presentation.isSteamController
		if touchpadSupported || profile.touchpadInputMode != .wholePad {
			rows.append(settingRow(
				id: "touchpad-mode",
				trigger: String(localized: "Touchpad Input"),
				action: localizedDisplayName(profile.touchpadInputMode.displayName),
				detail: ConfigurationOverviewBuilder.availabilityDetail(
					String(localized: "Active touchpad control set"),
					isSupported: touchpadSupported,
					presentation: presentation
				),
				systemImage: "rectangle.and.hand.point.up.left",
				target: .section(MainWindowSection.buttons.rawValue),
				isCurrentDevice: touchpadSupported
			))
		}
		if !profile.touchpadRegionTriggerModes.isEmpty {
			rows.append(settingRow(
				id: "legacy-touchpad-trigger-modes",
				trigger: String(localized: "Legacy Touchpad Modes"),
				action: String(format: String(localized: "%lld saved regions"), profile.touchpadRegionTriggerModes.count),
				detail: ConfigurationOverviewBuilder.availabilityDetail(
					String(localized: "Pending profile migration"),
					isSupported: touchpadSupported,
					presentation: presentation
				),
				systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
				target: .section(MainWindowSection.touchpad.rawValue),
				isCurrentDevice: touchpadSupported
			))
		}
		return rows
	}

	private static func keyboardRow(_ profile: Profile) -> ConfigurationOverviewRow {
		let settings = profile.onScreenKeyboardSettings
		let counts = String(
			format: String(localized: "%lld quick texts · %lld apps · %lld websites"),
			settings.quickTexts.count,
			settings.appBarItems.count,
			settings.websiteLinks.count
		)
		return settingRow(
			id: "keyboard-settings",
			trigger: String(localized: "On-Screen Keyboard"),
			action: profile.inheritedOnScreenKeyboardProfileId == nil
				? String(localized: "Profile-owned")
				: String(localized: "Inherited from another profile"),
			detail: counts,
			systemImage: "keyboard",
			target: .section(MainWindowSection.keyboard.rawValue)
		)
	}

	private static func settingRow(
		id: String,
		trigger: String,
		action: String,
		detail: String?,
		systemImage: String,
		target: ConfigurationOverviewTarget,
		isCurrentDevice: Bool = true
	) -> ConfigurationOverviewRow {
		ConfigurationOverviewRow(
			id: id,
			category: .settings,
			trigger: trigger,
			action: action,
			detail: detail,
			source: .profile,
			systemImage: systemImage,
			target: target,
			isCurrentDevice: isCurrentDevice
		)
	}

	static func localizedDisplayName(_ value: String) -> String {
		String(localized: String.LocalizationValue(value))
	}

	private static func modifierDescription(_ flags: ModifierFlags) -> String {
		var parts: [String] = []
		if flags.command { parts.append(ModifierFlags.label(for: flags.commandSide) + "⌘") }
		if flags.option { parts.append(ModifierFlags.label(for: flags.optionSide) + "⌥") }
		if flags.control { parts.append(ModifierFlags.label(for: flags.controlSide) + "⌃") }
		if flags.shift { parts.append(ModifierFlags.label(for: flags.shiftSide) + "⇧") }
		return parts.isEmpty ? String(localized: "No modifier") : parts.joined(separator: " + ")
	}
}
