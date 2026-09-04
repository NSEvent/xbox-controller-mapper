import SwiftUI
import AppKit

// MARK: - LED Settings View

struct LEDSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
	@EnvironmentObject var mappingEngine: MappingEngine
	let profileId: UUID?
	let layerId: UUID?

	init(profileId: UUID? = nil, layerId: UUID? = nil) {
		self.profileId = profileId
		self.layerId = layerId
	}

	private var profile: Profile? {
		profileId.flatMap { id in profileManager.profiles.first { $0.id == id } }
			?? profileManager.activeProfile
	}

	private var isLayerScoped: Bool { layerId != nil }

	private var previewLayout: ControllerPreviewLayout {
		profile?.controllerPreviewLayout ?? .active
	}

    var settings: DualSenseLEDSettings {
		guard let profile else { return .default }
		guard let layerId else { return profile.dualSenseLEDSettings }
		return profile.layers.first(where: { $0.id == layerId })?.dualSenseLEDSettings
			?? profile.dualSenseLEDSettings
    }

    private var controllerPresentationState: ControllerPresentationState {
		controllerService.threadSafeControllerPresentationState
    }

	private var controllerDescriptor: ControllerVisualDescriptor {
		ControllerVisualDescriptor.resolved(
			previewLayout: previewLayout,
			presentationState: controllerPresentationState
		)
	}

	private var isDualShock: Bool { controllerDescriptor.isDualShock }

	private var supportsPlayerAndMuteLEDs: Bool {
		ControllerLEDPresentationPolicy.supportsPlayerAndMuteLEDs(
			descriptor: controllerDescriptor,
			previewLayout: previewLayout,
			activeConnectionIsBluetooth: controllerService.isBluetoothConnection
		)
	}

    var body: some View {
        Form {
            if isDualShock {
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
						Text("DualShock 4 supports light bar color and brightness. Player and mute LEDs are DualSense features.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
			} else if controllerDescriptor.isDualSense && !supportsPlayerAndMuteLEDs {
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
						Text("Over Bluetooth, player and mute LEDs are unavailable. Light bar color and brightness remain supported.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Light Bar") {
                Toggle("Enabled", isOn: Binding(
                    get: { settings.lightBarEnabled },
                    set: { updateSettings(\.lightBarEnabled, $0) }
                ))
                .disabled(controllerService.partyModeEnabled)

                if settings.lightBarEnabled {
                    Toggle(isOn: Binding(
                        get: { settings.batteryLightBar },
                        set: { newValue in
                            updateSettings(\.batteryLightBar, newValue)
                            if newValue {
                                controllerService.updateBatteryLightBar()
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Battery Level Color")
                            Text("Red when low, yellow at half, green when full")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(controllerService.partyModeEnabled)

                    if !settings.batteryLightBar {
                        LightBarColorPicker(
                            color: Binding(
                                get: { settings.lightBarColor.color },
                                set: { updateColor($0) }
                            )
                        )
                        .frame(height: 44)
                        .disabled(controllerService.partyModeEnabled)
                        .opacity(controllerService.partyModeEnabled ? 0.5 : 1.0)
                        .accessibilityLabel("Light bar color picker")
                    }

					Picker("Brightness", selection: Binding(
							get: { settings.lightBarBrightness },
							set: { updateSettings(\.lightBarBrightness, $0) }
                        )) {
                            ForEach(LightBarBrightness.allCases, id: \.self) { brightness in
                                Text(brightness.displayName).tag(brightness)
                            }
						}
						.pickerStyle(.segmented)
						.disabled(controllerService.partyModeEnabled)
				}
            }

            if !isDualShock {
            Section("Mute Button LED") {
                Picker("Mode", selection: Binding(
                    get: { settings.muteButtonLED },
                    set: { updateSettings(\.muteButtonLED, $0) }
                )) {
                    ForEach(MuteButtonLEDMode.allCases, id: \.self) { mode in
                        Text(LocalizedStringKey(mode.displayName)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
				.disabled(controllerService.partyModeEnabled || !supportsPlayerAndMuteLEDs)
            }

            Section("Player LEDs") {
                HStack(spacing: 12) {
                    ForEach(0..<5) { index in
                        playerLEDToggle(index: index)
                    }
                }
                .frame(maxWidth: .infinity)
				.disabled(controllerService.partyModeEnabled || !supportsPlayerAndMuteLEDs)
				.opacity((controllerService.partyModeEnabled || !supportsPlayerAndMuteLEDs) ? 0.5 : 1.0)

                HStack {
                    Text("Presets:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    playerPresetButton("P1", preset: .player1)
                    playerPresetButton("P2", preset: .player2)
                    playerPresetButton("P3", preset: .player3)
                    playerPresetButton("P4", preset: .player4)
                    playerPresetButton("All", preset: .allOn)
                    playerPresetButton("Off", preset: .default)
                }
				.disabled(controllerService.partyModeEnabled || !supportsPlayerAndMuteLEDs)
            }
            } // end if !isDualShock

			if !isLayerScoped {
			Section("Party Mode") {
				Toggle("Enable Party Mode", isOn: Binding(
					get: { controllerService.partyModeEnabled },
					set: { enabled in
						controllerService.setPartyMode(enabled, savedSettings: settings)
						if !enabled {
							DispatchQueue.main.async {
								mappingEngine.restoreEffectiveLEDSettings()
							}
						}
					}
				))

                if controllerService.partyModeEnabled {
                    Text("Rainbow lightbar, cycling player LEDs, breathing mute button")
                        .font(.caption)
                        .foregroundColor(.secondary)
				}
			}
			}
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            applySettingsToController()
        }
        .onDisappear {
            // Close the color panel when navigating away from this tab
            if NSColorPanel.shared.isVisible {
                NSColorPanel.shared.close()
            }
			mappingEngine.restoreEffectiveLEDSettings()
        }
    }

    @ViewBuilder
    private func playerLEDToggle(index: Int) -> some View {
        let isOn = getPlayerLED(index: index)
        Button(action: {
            togglePlayerLED(index: index)
        }) {
            Circle()
                .fill(isOn ? Color.white : Color.gray.opacity(0.3))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: isOn ? .white.opacity(0.8) : .clear, radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Player LED \(index + 1)")
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private func getPlayerLED(index: Int) -> Bool {
        switch index {
        case 0: return settings.playerLEDs.led1
        case 1: return settings.playerLEDs.led2
        case 2: return settings.playerLEDs.led3
        case 3: return settings.playerLEDs.led4
        case 4: return settings.playerLEDs.led5
        default: return false
        }
    }

    private func togglePlayerLED(index: Int) {
        var newLEDs = settings.playerLEDs
        // Enforce symmetric patterns - LEDs mirror around center
        switch index {
        case 0, 4:
            // Far left and far right are linked
            let newState = !newLEDs.led1
            newLEDs.led1 = newState
            newLEDs.led5 = newState
        case 1, 3:
            // Inner left and inner right are linked
            let newState = !newLEDs.led2
            newLEDs.led2 = newState
            newLEDs.led4 = newState
        case 2:
            // Center LED toggles independently
            newLEDs.led3.toggle()
        default: break
        }
        updateSettings(\.playerLEDs, newLEDs)
    }

    private func applyPlayerPreset(_ preset: PlayerLEDs) {
        updateSettings(\.playerLEDs, preset)
    }

    /// Helper view builder for player LED preset buttons (reduces code duplication)
    @ViewBuilder
    private func playerPresetButton(_ label: String, preset: PlayerLEDs) -> some View {
        Button(label) { applyPlayerPreset(preset) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Player LED preset: \(label)")
    }

    private func updateSettings<T>(_ keyPath: WritableKeyPath<DualSenseLEDSettings, T>, _ value: T) {
        var newSettings = settings
        newSettings[keyPath: keyPath] = value
		persist(newSettings)
        applySettingsToController()
    }

    private func updateColor(_ color: Color) {
        var newSettings = settings
        newSettings.lightBarColor = CodableColor(color: color)
		persist(newSettings)
        applySettingsToController()
    }

	private func persist(_ settings: DualSenseLEDSettings) {
		guard let layerId else {
			profileManager.updateDualSenseLEDSettings(settings)
			return
		}
		guard let profile,
		      var layer = profile.layers.first(where: { $0.id == layerId }) else {
			return
		}
		layer.dualSenseLEDSettings = settings
		profileManager.updateLayer(layer, in: profile)
	}

    private func applySettingsToController() {
		if isEditingEffectiveScope && !controllerService.partyModeEnabled {
            controllerService.applyLEDSettings(settings)
        }
    }

	private var isEditingEffectiveScope: Bool {
		LayerLEDSettingsPolicy.shouldPreviewOnController(
			editingProfileId: profile?.id,
			activeProfileId: profileManager.activeProfileId,
			editingLayerId: layerId,
			activeRuntimeLayerId: mappingEngine.activeRuntimeLayerId,
			isControllerLocked: mappingEngine.isLocked
		)
	}
}

struct LayerLEDSettingsSheet: View {
	@EnvironmentObject private var profileManager: ProfileManager
	@EnvironmentObject private var mappingEngine: MappingEngine
	@Environment(\.dismiss) private var dismiss
	let profileId: UUID
	let layerId: UUID

	private var layerName: String {
		profileManager.profiles.first(where: { $0.id == profileId })?
			.layers.first(where: { $0.id == layerId })?.name
			?? String(localized: "Layer")
	}

	private var profile: Profile? {
		profileManager.profiles.first { $0.id == profileId }
	}

	private var hasOverride: Bool {
		profile?.layers.first(where: { $0.id == layerId })?.dualSenseLEDSettings != nil
	}

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text("Layer LEDs")
						.font(.headline)
					Text(hasOverride
						? String(format: String(localized: "%@ · Override"), layerName)
						: String(format: String(localized: "%@ · Inherited from Base"), layerName))
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				if hasOverride {
					Button("Use Base") { clearOverride() }
						.help("Remove this layer's LED override")
				}
				Button("Done") { dismiss() }
					.keyboardShortcut(.defaultAction)
			}
			.padding()
			Divider()
			LEDSettingsView(profileId: profileId, layerId: layerId)
		}
		.frame(width: 560, height: 650)
	}

	private func clearOverride() {
		guard let profile,
		      var layer = profile.layers.first(where: { $0.id == layerId }) else { return }
		layer.dualSenseLEDSettings = nil
		profileManager.updateLayer(layer, in: profile)
		DispatchQueue.main.async {
			mappingEngine.restoreEffectiveLEDSettings()
		}
	}
}

// MARK: - Light Bar Color Picker

struct LightBarColorPicker: NSViewRepresentable {
    @Binding var color: Color

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let colorWell = NSColorWell()
        colorWell.color = NSColor(color)
        colorWell.target = context.coordinator
        colorWell.action = #selector(Coordinator.colorChanged(_:))
        colorWell.controlSize = .large
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.colorWell = colorWell

        container.addSubview(colorWell)

        NSLayoutConstraint.activate([
            colorWell.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            colorWell.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            colorWell.topAnchor.constraint(equalTo: container.topAnchor),
            colorWell.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.mode = .wheel

        // Observe color panel changes for continuous updates
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.panelColorChanged(_:)),
            name: NSColorPanel.colorDidChangeNotification,
            object: panel
        )

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Only update if not actively selecting to prevent feedback loop
        if !context.coordinator.isSelecting, let colorWell = context.coordinator.colorWell {
            colorWell.color = NSColor(color)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: LightBarColorPicker
        weak var colorWell: NSColorWell?
        private var panelWasVisible = false
        var isSelecting = false

        init(_ parent: LightBarColorPicker) {
            self.parent = parent
            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(checkPanelVisibility),
                name: NSWindow.didUpdateNotification,
                object: NSColorPanel.shared
            )
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            isSelecting = false
            let nsColor = sender.color.usingColorSpace(.deviceRGB) ?? sender.color
            parent.color = Color(red: Double(nsColor.redComponent),
                                 green: Double(nsColor.greenComponent),
                                 blue: Double(nsColor.blueComponent))
        }

        @objc func panelColorChanged(_ notification: Notification) {
            isSelecting = true
            let panel = NSColorPanel.shared
            let nsColor = panel.color.usingColorSpace(.deviceRGB) ?? panel.color
            parent.color = Color(red: Double(nsColor.redComponent),
                                 green: Double(nsColor.greenComponent),
                                 blue: Double(nsColor.blueComponent))
        }

        @objc func checkPanelVisibility() {
            let panel = NSColorPanel.shared
            let isVisible = panel.isVisible

            // Position only when panel first becomes visible
            if isVisible && !panelWasVisible {
                positionPanelNextToColorWell()
            }
            panelWasVisible = isVisible
        }

        private func positionPanelNextToColorWell() {
            guard let colorWell = colorWell,
                  let window = colorWell.window else { return }

            let panel = NSColorPanel.shared

            // Get the color well's frame in screen coordinates
            let wellFrameInWindow = colorWell.convert(colorWell.bounds, to: nil)
            let wellFrameOnScreen = window.convertToScreen(wellFrameInWindow)

            // Position panel to the right of the color well, aligned to top
            let panelSize = panel.frame.size
            let newOrigin = NSPoint(
                x: wellFrameOnScreen.maxX + 10,
                y: wellFrameOnScreen.maxY - panelSize.height
            )
            panel.setFrameOrigin(newOrigin)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
