import SwiftUI

// MARK: - Joystick Settings View

struct JoystickSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var focusCursorHighlightEnabled: Bool = FocusModeIndicator.isEnabled
    @State private var overrideLayerId: UUID?

    var settings: JoystickSettings {
        profileManager.activeProfile?.joystickSettings ?? .default
    }

    var body: some View {
        Form {
            Section("Left Joystick") {
                Picker("Mode", selection: Binding(
                    get: { settings.leftStick.mode },
                    set: { updateSettings(\.leftStick.mode, $0) }
                )) {
                    ForEach(StickMode.visibleModes, id: \.self) { mode in
                        Text(LocalizedStringKey(mode.displayName)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("Profile default. Override per-layer from the stick's dropdown in the Buttons tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.leftStick.mode == .mouse {
                    SliderRow(
                        label: "Sensitivity",
                        value: Binding(
                            get: { settings.leftStick.mouseSensitivity },
                            set: { updateSettings(\.leftStick.mouseSensitivity, $0) }
                        ),
                        range: 0...1,
                        description: "How fast the cursor moves"
                    )

                    SliderRow(
                        label: "Acceleration",
                        value: Binding(
                            get: { settings.leftStick.mouseAcceleration },
                            set: { updateSettings(\.leftStick.mouseAcceleration, $0) }
                        ),
                        range: 0...1,
                        description: "0 = linear, 1 = max curve"
                    )
                }

                if settings.leftStick.mode == .scroll {
                    SliderRow(
                        label: "Sensitivity",
                        value: Binding(
                            get: { settings.leftStick.scrollSensitivity },
                            set: { updateSettings(\.leftStick.scrollSensitivity, $0) }
                        ),
                        range: 0...1,
                        description: "How fast scrolling occurs"
                    )

                    SliderRow(
                        label: "Acceleration",
                        value: Binding(
                            get: { settings.leftStick.scrollAcceleration },
                            set: { updateSettings(\.leftStick.scrollAcceleration, $0) }
                        ),
                        range: 0...1,
                        description: "0 = linear, 1 = max curve"
                    )
                }

                if settings.leftStick.mode == .custom {
                    JoystickCustomDirectionPanel(
                        side: .left,
                        horizontalSliceSize: Binding(
                            get: { settings.leftStick.customHorizontalSliceSize },
                            set: { updateSettings(\.leftStick.customHorizontalSliceSize, $0) }
                        ),
                        verticalSliceSize: Binding(
                            get: { settings.leftStick.customVerticalSliceSize },
                            set: { updateSettings(\.leftStick.customVerticalSliceSize, $0) }
                        ),
                        deadzone: Binding(
                            get: { settings.leftStick.customDeadzone },
                            set: { updateSettings(\.leftStick.customDeadzone, $0) }
                        ),
                        invertY: Binding(
                            get: { settings.leftStick.invertMouseY },
                            set: { updateSettings(\.leftStick.invertMouseY, $0) }
                        )
                    )
                } else {
                    // Deadzone/Invert follow the active mode so they edit the field the
                    // runtime actually reads: scroll mode uses the scroll fields, every
                    // other (movement) mode on the left stick uses the mouse fields.
                    SliderRow(
                        label: "Deadzone",
                        value: Binding(
                            get: { settings.leftStick.mode == .scroll ? settings.leftStick.scrollDeadzone : settings.leftStick.mouseDeadzone },
                            set: {
                                if settings.leftStick.mode == .scroll {
                                    updateSettings(\.leftStick.scrollDeadzone, $0)
                                } else {
                                    updateSettings(\.leftStick.mouseDeadzone, $0)
                                }
                            }
                        ),
                        range: 0...0.5,
                        description: "Ignore small movements"
                    )

                    Toggle("Invert Y Axis", isOn: Binding(
                        get: { settings.leftStick.mode == .scroll ? settings.leftStick.invertScrollY : settings.leftStick.invertMouseY },
                        set: {
                            if settings.leftStick.mode == .scroll {
                                updateSettings(\.leftStick.invertScrollY, $0)
                            } else {
                                updateSettings(\.leftStick.invertMouseY, $0)
                            }
                        }
                    ))
                }
            }

            Section("Focus Mode (Precision)") {
                SliderRow(
                    label: "Focus Speed",
                    value: Binding(
                        get: { settings.focusModeSensitivity },
                        set: { updateSettings(\.focusModeSensitivity, $0) }
                    ),
                    range: 0...0.5,
                    description: "Sensitivity when holding modifier"
                )

                VStack(alignment: .leading) {
                    Text("Activation Modifier")
                    HStack(spacing: 12) {
                        Toggle("⌘", isOn: Binding(
                            get: { settings.focusModeModifier.command },
                            set: {
                                var new = settings.focusModeModifier
                                new.command = $0
                                updateSettings(\.focusModeModifier, new)
                            }
                        ))
                        .toggleStyle(.button)
                        .accessibilityLabel("Command modifier")

                        Toggle("⌥", isOn: Binding(
                            get: { settings.focusModeModifier.option },
                            set: {
                                var new = settings.focusModeModifier
                                new.option = $0
                                updateSettings(\.focusModeModifier, new)
                            }
                        ))
                        .toggleStyle(.button)
                        .accessibilityLabel("Option modifier")

                        Toggle("⌃", isOn: Binding(
                            get: { settings.focusModeModifier.control },
                            set: {
                                var new = settings.focusModeModifier
                                new.control = $0
                                updateSettings(\.focusModeModifier, new)
                            }
                        ))
                        .toggleStyle(.button)
                        .accessibilityLabel("Control modifier")

                        Toggle("⇧", isOn: Binding(
                            get: { settings.focusModeModifier.shift },
                            set: {
                                var new = settings.focusModeModifier
                                new.shift = $0
                                updateSettings(\.focusModeModifier, new)
                            }
                        ))
                        .toggleStyle(.button)
                        .accessibilityLabel("Shift modifier")
                    }
                }

                Toggle("Highlight Focused Cursor", isOn: $focusCursorHighlightEnabled)
                    .onChange(of: focusCursorHighlightEnabled) { _, newValue in
                        FocusModeIndicator.isEnabled = newValue
                    }
            }

            Section("FPS / Pointer-Lock Games") {
                Picker("Relative Mouse Aiming", selection: Binding(
                    get: { settings.pointerLockMouseMode },
                    set: { updateSettings(\.pointerLockMouseMode, $0) }
                )) {
                    ForEach(PointerLockMouseMode.allCases, id: \.self) { mode in
                        Text(LocalizedStringKey(mode.displayName)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("Games that capture the mouse (browser FPS, pointer lock) need relative input to aim 360°. Auto switches while the game hides the cursor, so aiming never stops at screen edges. Always is for per-app game profiles; the cursor won't move outside a game.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Right Joystick") {
                Picker("Mode", selection: Binding(
                    get: { settings.rightStick.mode },
                    set: { updateSettings(\.rightStick.mode, $0) }
                )) {
                    ForEach(StickMode.visibleModes, id: \.self) { mode in
                        Text(LocalizedStringKey(mode.displayName)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("Profile default. Override per-layer from the stick's dropdown in the Buttons tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.rightStick.mode == .mouse {
                    SliderRow(
                        label: "Sensitivity",
                        value: Binding(
                            get: { settings.rightStick.mouseSensitivity },
                            set: { updateSettings(\.rightStick.mouseSensitivity, $0) }
                        ),
                        range: 0...1,
                        description: "How fast the cursor moves"
                    )

                    SliderRow(
                        label: "Acceleration",
                        value: Binding(
                            get: { settings.rightStick.mouseAcceleration },
                            set: { updateSettings(\.rightStick.mouseAcceleration, $0) }
                        ),
                        range: 0...1,
                        description: "0 = linear, 1 = max curve"
                    )
                }

                if settings.rightStick.mode == .scroll {
                    SliderRow(
                        label: "Sensitivity",
                        value: Binding(
                            get: { settings.rightStick.scrollSensitivity },
                            set: { updateSettings(\.rightStick.scrollSensitivity, $0) }
                        ),
                        range: 0...1,
                        description: "How fast scrolling occurs"
                    )

                    SliderRow(
                        label: "Acceleration",
                        value: Binding(
                            get: { settings.rightStick.scrollAcceleration },
                            set: { updateSettings(\.rightStick.scrollAcceleration, $0) }
                        ),
                        range: 0...1,
                        description: "0 = linear, 1 = max curve"
                    )

                    SliderRow(
                        label: "Double-Tap Boost",
                        value: Binding(
                            get: { settings.scrollBoostMultiplier },
                            set: { updateSettings(\.scrollBoostMultiplier, $0) }
                        ),
                        range: 1...4,
                        description: "Speed multiplier after double-tap up/down"
                    )
                }

                if settings.rightStick.mode == .custom {
                    JoystickCustomDirectionPanel(
                        side: .right,
                        horizontalSliceSize: Binding(
                            get: { settings.rightStick.customHorizontalSliceSize },
                            set: { updateSettings(\.rightStick.customHorizontalSliceSize, $0) }
                        ),
                        verticalSliceSize: Binding(
                            get: { settings.rightStick.customVerticalSliceSize },
                            set: { updateSettings(\.rightStick.customVerticalSliceSize, $0) }
                        ),
                        deadzone: Binding(
                            get: { settings.rightStick.customDeadzone },
                            set: { updateSettings(\.rightStick.customDeadzone, $0) }
                        ),
                        invertY: Binding(
                            get: { settings.rightStick.invertScrollY },
                            set: { updateSettings(\.rightStick.invertScrollY, $0) }
                        )
                    )
                } else {
                    // Deadzone/Invert follow the active mode so they edit the field the
                    // runtime actually reads: mouse mode uses the mouse fields, every
                    // other (movement) mode on the right stick uses the scroll fields.
                    SliderRow(
                        label: "Deadzone",
                        value: Binding(
                            get: { settings.rightStick.mode == .mouse ? settings.rightStick.mouseDeadzone : settings.rightStick.scrollDeadzone },
                            set: {
                                if settings.rightStick.mode == .mouse {
                                    updateSettings(\.rightStick.mouseDeadzone, $0)
                                } else {
                                    updateSettings(\.rightStick.scrollDeadzone, $0)
                                }
                            }
                        ),
                        range: 0...0.5,
                        description: "Ignore small movements"
                    )

                    Toggle("Invert Y Axis", isOn: Binding(
                        get: { settings.rightStick.mode == .mouse ? settings.rightStick.invertMouseY : settings.rightStick.invertScrollY },
                        set: {
                            if settings.rightStick.mode == .mouse {
                                updateSettings(\.rightStick.invertMouseY, $0)
                            } else {
                                updateSettings(\.rightStick.invertScrollY, $0)
                            }
                        }
                    ))
                }
            }

            if let layers = profileManager.activeProfile?.layers, !layers.isEmpty {
                Section("Per-Layer Overrides") {
                    Text("Override stick behavior while a layer is held. Any control left on “Inherit” uses the base settings above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Layer", selection: Binding(
                        get: { resolvedOverrideLayer(layers)?.id },
                        set: { overrideLayerId = $0 }
                    )) {
                        ForEach(layers) { layer in
                            Text(layer.name).tag(layer.id as UUID?)
                        }
                    }

                    if let layer = resolvedOverrideLayer(layers) {
                        layerStickOverrideGroup(title: "Left Stick", side: .left, layer: layer)
                        Divider()
                        layerStickOverrideGroup(title: "Right Stick", side: .right, layer: layer)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func updateSettings<T>(_ keyPath: WritableKeyPath<JoystickSettings, T>, _ value: T) {
        var newSettings = settings
        newSettings[keyPath: keyPath] = value
        profileManager.updateJoystickSettings(newSettings)
    }

    /// The layer whose overrides are being edited: the picked one, or the first layer
    /// when nothing valid is selected (so the section always shows a layer).
    private func resolvedOverrideLayer(_ layers: [Layer]) -> Layer? {
        layers.first(where: { $0.id == overrideLayerId }) ?? layers.first
    }

    /// Per-stick override controls for the selected layer: a mode override (with an
    /// explicit "Inherit" option) plus sensitivity/acceleration/deadzone for the
    /// effective mode. Each control inherits the base stick until explicitly set.
    @ViewBuilder
    private func layerStickOverrideGroup(title: String, side: JoystickSide, layer: Layer) -> some View {
        let override = side == .left ? layer.leftStickTuning : layer.rightStickTuning
        let base = settings.stick(side)
        let effectiveMode = override?.mode ?? base.mode

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.bold())
                Spacer()
                if override != nil {
                    Button("Reset to Base") {
                        profileManager.clearLayerStickOverride(side: side, layerId: layer.id)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            Picker("Mode", selection: Binding(
                get: { override?.mode },
                set: { profileManager.setLayerStickOverride(\.mode, $0, side: side, layerId: layer.id) }
            )) {
                Text("Inherit (\(base.mode.displayName))").tag(StickMode?.none)
                ForEach(StickMode.visibleModes, id: \.self) { mode in
                    Text(LocalizedStringKey(mode.displayName)).tag(mode as StickMode?)
                }
            }

            switch effectiveMode {
            case .mouse:
                layerOverrideSlider("Sensitivity", side: side, layer: layer, keyPath: \.mouseSensitivity, base: base.mouseSensitivity, range: 0...1)
                layerOverrideSlider("Acceleration", side: side, layer: layer, keyPath: \.mouseAcceleration, base: base.mouseAcceleration, range: 0...1)
                layerOverrideSlider("Deadzone", side: side, layer: layer, keyPath: \.mouseDeadzone, base: base.mouseDeadzone, range: 0...0.5)
            case .scroll:
                layerOverrideSlider("Sensitivity", side: side, layer: layer, keyPath: \.scrollSensitivity, base: base.scrollSensitivity, range: 0...1)
                layerOverrideSlider("Acceleration", side: side, layer: layer, keyPath: \.scrollAcceleration, base: base.scrollAcceleration, range: 0...1)
                layerOverrideSlider("Deadzone", side: side, layer: layer, keyPath: \.scrollDeadzone, base: base.scrollDeadzone, range: 0...0.5)
            case .none, .custom, .dpad, .wasdKeys, .arrowKeys:
                Text("No tunable sensitivity for \(effectiveMode.displayName) mode.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func layerOverrideSlider(
        _ label: String,
        side: JoystickSide,
        layer: Layer,
        keyPath: WritableKeyPath<StickTuningOverride, Double?>,
        base: Double,
        range: ClosedRange<Double>
    ) -> some View {
        let override = side == .left ? layer.leftStickTuning : layer.rightStickTuning
        let overrideValue = override?[keyPath: keyPath]
        let isOverridden = overrideValue != nil

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(LocalizedStringKey(label))
                    .italic(!isOverridden)
                    .foregroundStyle(isOverridden ? Color.primary : Color.secondary)
                if !isOverridden {
                    Text("· inherited")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(overrideValue ?? base, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(width: 40)
                if isOverridden {
                    Button {
                        profileManager.setLayerStickOverride(keyPath, nil, side: side, layerId: layer.id)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to base (inherit)")
                }
            }

            Slider(
                value: Binding(
                    get: { overrideValue ?? base },
                    set: { profileManager.setLayerStickOverride(keyPath, $0, side: side, layerId: layer.id) }
                ),
                in: range
            )
        }
    }

}

// MARK: - Touchpad Settings View

struct TouchpadSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @State private var cursorAdvancedExpanded = false
    @State private var zoomAdvancedExpanded = false

    var settings: JoystickSettings {
        profileManager.activeProfile?.joystickSettings ?? .default
    }

    private var controllerPresentationState: ControllerPresentationState {
		controllerService.threadSafeControllerPresentationState
    }

    private var isAppleTVRemote: Bool {
		controllerPresentationState.isAppleTVRemote
    }

    var body: some View {
        Form {
			Section(isAppleTVRemote ? "Touch Surface Cursor" : "Touchpad Cursor") {
                Toggle(isOn: Binding(
                    get: { settings.disableTouchpadAsMouse },
                    set: { updateSettings(\.disableTouchpadAsMouse, $0) }
                )) {
                    VStack(alignment: .leading) {
						Text(isAppleTVRemote ? "Disable Touch Surface as Mouse" : "Disable Touchpad as Mouse")
						Text(isAppleTVRemote ? "Stop swipes on the remote touch surface from moving the cursor." : "Stop single-finger swipes from moving the cursor. Two-finger gestures, taps, region clicks, and swipe typing still work.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                SliderRow(
                    label: "Sensitivity",
                    value: Binding(
                        get: { settings.touchpadSensitivity },
                        set: { updateSettings(\.touchpadSensitivity, $0) }
                    ),
                    range: 0...1,
                    description: "Touchpad cursor speed"
                )

                DisclosureGroup("Advanced Cursor Tuning", isExpanded: $cursorAdvancedExpanded) {
                    SliderRow(
                        label: "Acceleration",
                        value: Binding(
                            get: { settings.touchpadAcceleration },
                            set: { updateSettings(\.touchpadAcceleration, $0) }
                        ),
                        range: 0...1,
                        description: "0 = linear, 1 = max curve"
                    )

                    SliderRow(
                        label: "Deadzone",
                        value: Binding(
                            get: { settings.touchpadDeadzone },
                            set: { updateSettings(\.touchpadDeadzone, $0) }
                        ),
                        range: 0...0.03,
                        description: "Ignore tap and click jitter"
                    )

                    SliderRow(
                        label: "Smoothing",
                        value: Binding(
                            get: { settings.touchpadSmoothing },
                            set: { updateSettings(\.touchpadSmoothing, $0) }
                        ),
                        range: 0...1,
                        description: "Reduce mouse jitter"
                    )
                }
            }

			if isAppleTVRemote {
				Section("Clickpad Edge Scroll") {
					Toggle(isOn: Binding(
						get: { settings.appleTVRemoteCircularScrollEnabled },
						set: { updateSettings(\.appleTVRemoteCircularScrollEnabled, $0) }
					)) {
						VStack(alignment: .leading) {
							Text("Edge Scroll")
							Text("Drag around the outer clickpad edge to scroll.")
								.font(.caption)
								.foregroundColor(.secondary)
						}
					}

					SliderRow(
						label: "Scroll Speed",
						value: Binding(
							get: { settings.appleTVRemoteCircularScrollSensitivity },
							set: { updateSettings(\.appleTVRemoteCircularScrollSensitivity, $0) }
						),
						range: 0...1,
						description: "Speed for circular edge scrolling"
					)
					.disabled(!settings.appleTVRemoteCircularScrollEnabled)
				}
			}

			if !isAppleTVRemote {
				Section("Scroll & Zoom") {
					SliderRow(
						label: "Two-Finger Pan",
						value: Binding(
							get: { settings.touchpadPanSensitivity },
							set: { updateSettings(\.touchpadPanSensitivity, $0) }
						),
						range: 0...1,
						description: "Scroll speed for two-finger pan"
					)

					Toggle("Reverse Horizontal Scroll", isOn: Binding(
						get: { settings.touchpadInvertScrollX },
						set: { updateSettings(\.touchpadInvertScrollX, $0) }
					))

					Toggle("Reverse Vertical Scroll", isOn: Binding(
						get: { settings.touchpadInvertScrollY },
						set: { updateSettings(\.touchpadInvertScrollY, $0) }
					))

					DisclosureGroup("Zoom Details", isExpanded: $zoomAdvancedExpanded) {
						SliderRow(
							label: "Pan to Zoom Ratio",
							value: Binding(
								get: { settings.touchpadZoomToPanRatio },
								set: { updateSettings(\.touchpadZoomToPanRatio, $0) }
							),
							range: 0.5...5.0,
							description: "Low = easier to zoom, High = easier to pan"
						)

						Toggle(isOn: Binding(
							get: { settings.touchpadUseNativeZoom },
							set: { updateSettings(\.touchpadUseNativeZoom, $0) }
						)) {
							VStack(alignment: .leading) {
								Text("Native Zoom Gestures")
								Text("Use macOS magnify gestures instead of Cmd+Plus/Minus")
									.font(.caption)
									.foregroundColor(.secondary)
							}
						}
					}
				}
			}

            // Region Mappings have been promoted to first-class buttons in the
            // Buttons tab (see the "TOUCHPAD REGIONS" section above the controller
            // diagram). Configure each quadrant the same way you configure any
            // other controller button. The legacy in-place grid is gone; the
            // toggle below stays here because it's a global touchpad-input
            // policy, not a per-quadrant binding.
			if !isAppleTVRemote {
				Section("Region Behavior") {
					Toggle(isOn: Binding(
						get: { settings.requireActiveTouchForRegionClick },
						set: { updateSettings(\.requireActiveTouchForRegionClick, $0) }
					)) {
						VStack(alignment: .leading) {
							Text("Require Active Touch for Region Clicks")
							Text("Only fire region clicks when a finger is on the pad. Prevents stale-position misfires when clicking after lifting off.")
								.font(.caption)
								.foregroundColor(.secondary)
						}
					}
				}
			}
        }
        .formStyle(.grouped)
        .padding()
    }

    private func updateSettings<T>(_ keyPath: WritableKeyPath<JoystickSettings, T>, _ value: T) {
        var newSettings = settings
        newSettings[keyPath: keyPath] = value
        profileManager.updateJoystickSettings(newSettings)
    }
}

// MARK: - Touchpad Region Grid

/// Drag-drop modifier for touchpad region cells. Mirrors the SwappableModifier in
/// ControllerVisualView (glow + scale-up while targeted) but transports a TouchpadRegion.
private struct RegionSwappableModifier: ViewModifier {
    let region: TouchpadRegion
    let onSwap: (TouchpadRegion, TouchpadRegion) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isTargeted ? 1.06 : 1.0)
            .shadow(
                color: Color.accentColor.opacity(isTargeted ? 0.9 : 0),
                radius: isTargeted ? 8 : 0
            )
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
            .draggable(region)
            .dropDestination(for: TouchpadRegion.self) { items, _ in
                guard let source = items.first else { return false }
                onSwap(source, region)
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

extension View {
    fileprivate func swappableRegion(
        _ region: TouchpadRegion,
        onSwap: @escaping (TouchpadRegion, TouchpadRegion) -> Void
    ) -> some View {
        modifier(RegionSwappableModifier(region: region, onSwap: onSwap))
    }
}

struct TouchpadRegionGrid: View {
    @EnvironmentObject var profileManager: ProfileManager

    @State private var editingRegion: TouchpadRegion?

    private var regionMappings: [TouchpadRegionMapping] {
        profileManager.activeProfile?.touchpadRegionMappings ?? []
    }

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                regionCell(.topLeft)
                regionCell(.topRight)
            }
            GridRow {
                regionCell(.bottomLeft)
                regionCell(.bottomRight)
            }
        }
        .frame(minHeight: 180)
        .sheet(item: $editingRegion) { region in
            TouchpadRegionMappingSheet(
                region: region,
                existingMappings: mappings(for: region)
            )
            .environmentObject(profileManager)
        }
    }

    private func mappings(for region: TouchpadRegion) -> [TouchpadRegionMapping] {
        regionMappings.filter { $0.region == region && !$0.isEmpty }
    }

    private func keyMapping(from regionMapping: TouchpadRegionMapping) -> KeyMapping {
        KeyMapping(
            keyCode: regionMapping.keyCode,
            modifiers: regionMapping.modifiers,
            macroId: regionMapping.macroId,
            systemCommand: regionMapping.systemCommand,
            hint: regionMapping.hint
        )
    }

    @ViewBuilder
    private func regionCell(_ region: TouchpadRegion) -> some View {
        let regionMaps = mappings(for: region)
        let hasMapping = !regionMaps.isEmpty
        let touchMap = regionMaps.first { $0.triggerMode == .touch || $0.triggerMode == .both }
        let clickMap = regionMaps.first { $0.triggerMode == .click || $0.triggerMode == .both }

        Button(action: { editingRegion = region }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(region.displayName)
                    .font(.caption2.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 4)
                if hasMapping {
                    if let touch = touchMap {
                        HStack(spacing: 3) {
                            Text("touch")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            MappingLabelView(
                                mapping: keyMapping(from: touch),
                                horizontal: true,
                                font: .caption2
                            )
                        }
                    }
                    if let click = clickMap {
                        HStack(spacing: 3) {
                            Text("click")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            MappingLabelView(
                                mapping: keyMapping(from: click),
                                horizontal: true,
                                font: .caption2
                            )
                        }
                    }
                } else {
                    Text("Tap to map")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(hasMapping ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(hasMapping ? Color.accentColor.opacity(0.4) : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            if hasMapping {
                Button("Edit...") { editingRegion = region }
                Button("Clear", role: .destructive) { removeMapping(for: region) }
            }
        }
        .swappableRegion(region, onSwap: performSwap)
    }

    private func performSwap(from source: TouchpadRegion, to target: TouchpadRegion) {
        profileManager.swapTouchpadRegions(region1: source, region2: target)
    }

    private func removeMapping(for region: TouchpadRegion) {
        guard var profile = profileManager.activeProfile else { return }
        profile.touchpadRegionMappings.removeAll { $0.region == region }
        profileManager.updateTouchpadRegionMappings(profile.touchpadRegionMappings)
    }
}

// MARK: - Microphone Settings View

struct MicrophoneSettingsView: View {
    @EnvironmentObject var controllerService: ControllerService

    var body: some View {
        Form {
            // USB requirement notice (same as LEDs tab)
            if controllerService.isBluetoothConnection {
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Microphone control requires USB connection on macOS. Connect via USB to use the DualSense microphone.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Microphone Control") {
                Toggle("Mute Microphone", isOn: Binding(
                    get: { controllerService.isMicMuted },
                    set: { controllerService.setMicMuted($0) }
                ))
                .disabled(controllerService.isBluetoothConnection)

                Text("Use this to mute or unmute the built-in microphone on your DualSense controller.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Audio Input Test") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Speak into your controller to test the microphone input level:")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    // Audio level meter
                    AudioLevelMeter(level: controllerService.micAudioLevel)
                        .frame(height: 24)

                    HStack {
                        Text("Level:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(controllerService.micAudioLevel * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .disabled(controllerService.isBluetoothConnection || controllerService.isMicMuted)
            .opacity((controllerService.isBluetoothConnection || controllerService.isMicMuted) ? 0.5 : 1.0)

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tips", systemImage: "lightbulb")
                        .font(.headline)

                    Text("• The DualSense microphone appears as \"DualSense Wireless Controller\" in System Settings → Sound → Input")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("• You can select it as your input device in apps like Discord, Zoom, or FaceTime")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("• The mute button on the controller (between the analog sticks) can also toggle mute")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            controllerService.refreshMicMuteState()
            if !controllerService.isBluetoothConnection && !controllerService.isMicMuted {
                controllerService.startMicLevelMonitoring()
            }
        }
        .onDisappear {
            controllerService.stopMicLevelMonitoring()
        }
        .onChange(of: controllerService.isMicMuted) { _, isMuted in
            if isMuted {
                controllerService.stopMicLevelMonitoring()
            } else if !controllerService.isBluetoothConnection {
                controllerService.startMicLevelMonitoring()
            }
        }
    }
}

// MARK: - Audio Level Meter

struct AudioLevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))

                // Level indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(levelColor)
                    .frame(width: max(0, geometry.size.width * CGFloat(level)))

                // Segment markers
                HStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { i in
                        if i > 0 {
                            Rectangle()
                                .fill(Color.black.opacity(0.2))
                                .frame(width: 1)
                        }
                        Spacer()
                    }
                }
            }
        }
        .accessibilityLabel("Microphone audio level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private var levelColor: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Reusable slider row for settings
struct SliderRow: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var description: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(width: 40)
            }

            Slider(value: $value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue("\(value, specifier: "%.2f")")
                .accessibilityHint(description ?? "")

            if let description = description {
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
