import SwiftUI

// MARK: - Joystick Settings View

struct JoystickSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var focusCursorHighlightEnabled: Bool = FocusModeIndicator.isEnabled

    var settings: JoystickSettings {
        profileManager.activeProfile?.joystickSettings ?? .default
    }

    var body: some View {
        Form {
            Section("Left Joystick") {
                Picker("Mode", selection: Binding(
                    get: { settings.leftStickMode },
                    set: { updateSettings(\.leftStickMode, $0) }
                )) {
                    ForEach(StickMode.visibleModes, id: \.self) { mode in
                        Text(LocalizedStringKey(mode.displayName)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if settings.leftStickMode == .mouse {
                    SliderRow(
                        label: "Sensitivity",
                        value: Binding(
                            get: { settings.mouseSensitivity },
                            set: { updateSettings(\.mouseSensitivity, $0) }
                        ),
                        range: 0...1,
                        description: "How fast the cursor moves"
                    )

                    SliderRow(
                        label: "Acceleration",
                        value: Binding(
                            get: { settings.mouseAcceleration },
                            set: { updateSettings(\.mouseAcceleration, $0) }
                        ),
                        range: 0...1,
                        description: "0 = linear, 1 = max curve"
                    )
                }

                if settings.leftStickMode == .scroll {
                    SliderRow(
                        label: "Sensitivity",
                        value: Binding(
                            get: { settings.scrollSensitivity },
                            set: { updateSettings(\.scrollSensitivity, $0) }
                        ),
                        range: 0...1,
                        description: "How fast scrolling occurs"
                    )

                    SliderRow(
                        label: "Acceleration",
                        value: Binding(
                            get: { settings.scrollAcceleration },
                            set: { updateSettings(\.scrollAcceleration, $0) }
                        ),
                        range: 0...1,
                        description: "0 = linear, 1 = max curve"
                    )
                }

                if settings.leftStickMode == .custom {
                    JoystickCustomDirectionPanel(
                        side: .left,
                        horizontalSliceSize: Binding(
                            get: { settings.leftStickCustomHorizontalSliceSize },
                            set: { updateSettings(\.leftStickCustomHorizontalSliceSize, $0) }
                        ),
                        verticalSliceSize: Binding(
                            get: { settings.leftStickCustomVerticalSliceSize },
                            set: { updateSettings(\.leftStickCustomVerticalSliceSize, $0) }
                        ),
                        deadzone: Binding(
                            get: { settings.leftStickCustomDeadzone },
                            set: { updateSettings(\.leftStickCustomDeadzone, $0) }
                        ),
                        invertY: Binding(
                            get: { settings.invertMouseY },
                            set: { updateSettings(\.invertMouseY, $0) }
                        )
                    )
                } else {
                    SliderRow(
                        label: "Deadzone",
                        value: Binding(
                            get: { settings.mouseDeadzone },
                            set: { updateSettings(\.mouseDeadzone, $0) }
                        ),
                        range: 0...0.5,
                        description: "Ignore small movements"
                    )

                    Toggle("Invert Y Axis", isOn: Binding(
                        get: { settings.invertMouseY },
                        set: { updateSettings(\.invertMouseY, $0) }
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

            Section("Right Joystick") {
                Picker("Mode", selection: Binding(
                    get: { settings.rightStickMode },
                    set: { updateSettings(\.rightStickMode, $0) }
                )) {
                    ForEach(StickMode.visibleModes, id: \.self) { mode in
                        Text(LocalizedStringKey(mode.displayName)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if settings.rightStickMode == .mouse {
                    SliderRow(
                        label: "Sensitivity",
                        value: Binding(
                            get: { settings.mouseSensitivity },
                            set: { updateSettings(\.mouseSensitivity, $0) }
                        ),
                        range: 0...1,
                        description: "How fast the cursor moves"
                    )

                    SliderRow(
                        label: "Acceleration",
                        value: Binding(
                            get: { settings.mouseAcceleration },
                            set: { updateSettings(\.mouseAcceleration, $0) }
                        ),
                        range: 0...1,
                        description: "0 = linear, 1 = max curve"
                    )
                }

                if settings.rightStickMode == .scroll {
                    SliderRow(
                        label: "Sensitivity",
                        value: Binding(
                            get: { settings.scrollSensitivity },
                            set: { updateSettings(\.scrollSensitivity, $0) }
                        ),
                        range: 0...1,
                        description: "How fast scrolling occurs"
                    )

                    SliderRow(
                        label: "Acceleration",
                        value: Binding(
                            get: { settings.scrollAcceleration },
                            set: { updateSettings(\.scrollAcceleration, $0) }
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

                if settings.rightStickMode == .custom {
                    JoystickCustomDirectionPanel(
                        side: .right,
                        horizontalSliceSize: Binding(
                            get: { settings.rightStickCustomHorizontalSliceSize },
                            set: { updateSettings(\.rightStickCustomHorizontalSliceSize, $0) }
                        ),
                        verticalSliceSize: Binding(
                            get: { settings.rightStickCustomVerticalSliceSize },
                            set: { updateSettings(\.rightStickCustomVerticalSliceSize, $0) }
                        ),
                        deadzone: Binding(
                            get: { settings.rightStickCustomDeadzone },
                            set: { updateSettings(\.rightStickCustomDeadzone, $0) }
                        ),
                        invertY: Binding(
                            get: { settings.invertScrollY },
                            set: { updateSettings(\.invertScrollY, $0) }
                        )
                    )
                } else {
                    SliderRow(
                        label: "Deadzone",
                        value: Binding(
                            get: { settings.scrollDeadzone },
                            set: { updateSettings(\.scrollDeadzone, $0) }
                        ),
                        range: 0...0.5,
                        description: "Ignore small movements"
                    )

                    Toggle("Invert Y Axis", isOn: Binding(
                        get: { settings.invertScrollY },
                        set: { updateSettings(\.invertScrollY, $0) }
                    ))
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

// MARK: - Touchpad Settings View

struct TouchpadSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager

    var settings: JoystickSettings {
        profileManager.activeProfile?.joystickSettings ?? .default
    }

    var body: some View {
        Form {
            Section("Touchpad (DualSense)") {
                Toggle(isOn: Binding(
                    get: { settings.disableTouchpadAsMouse },
                    set: { updateSettings(\.disableTouchpadAsMouse, $0) }
                )) {
                    VStack(alignment: .leading) {
                        Text("Disable Touchpad as Mouse")
                        Text("Stop single-finger swipes from moving the cursor. Two-finger gestures, taps, region clicks, and swipe typing still work. Applies to DualSense, DualSense Edge, and DualShock 4.")
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
                    range: 0...0.005,
                    description: "Ignore tiny jitter"
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

                SliderRow(
                    label: "Two-Finger Pan",
                    value: Binding(
                        get: { settings.touchpadPanSensitivity },
                        set: { updateSettings(\.touchpadPanSensitivity, $0) }
                    ),
                    range: 0...1,
                    description: "Scroll speed for two-finger pan"
                )

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

            // Region Mappings have been promoted to first-class buttons in the
            // Buttons tab (see the "TOUCHPAD REGIONS" section above the controller
            // diagram). Configure each quadrant the same way you configure any
            // other controller button. The legacy in-place grid is gone; the
            // toggle below stays here because it's a global touchpad-input
            // policy, not a per-quadrant binding.
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

// MARK: - LED Settings View

struct LEDSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService

    var settings: DualSenseLEDSettings {
        profileManager.activeProfile?.dualSenseLEDSettings ?? .default
    }

    private var isDualShock: Bool {
        controllerService.threadSafeIsDualShock
    }

    var body: some View {
        Form {
            if isDualShock {
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("DualShock 4 supports light bar color only. Player LEDs, mute LED, and brightness controls are DualSense features.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else if controllerService.isBluetoothConnection {
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Over Bluetooth, only the light bar color is supported. Player LEDs, mute LED, and brightness require USB.")
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

                    if !isDualShock {
                        Picker("Brightness", selection: Binding(
                            get: { settings.lightBarBrightness },
                            set: { updateSettings(\.lightBarBrightness, $0) }
                        )) {
                            ForEach(LightBarBrightness.allCases, id: \.self) { brightness in
                                Text(brightness.displayName).tag(brightness)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(controllerService.partyModeEnabled || controllerService.isBluetoothConnection)
                    }
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
                .disabled(controllerService.partyModeEnabled || controllerService.isBluetoothConnection)
            }

            Section("Player LEDs") {
                HStack(spacing: 12) {
                    ForEach(0..<5) { index in
                        playerLEDToggle(index: index)
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(controllerService.partyModeEnabled || controllerService.isBluetoothConnection)
                .opacity((controllerService.partyModeEnabled || controllerService.isBluetoothConnection) ? 0.5 : 1.0)

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
                .disabled(controllerService.partyModeEnabled || controllerService.isBluetoothConnection)
            }
            } // end if !isDualShock

            Section("Party Mode") {
                Toggle("Enable Party Mode", isOn: Binding(
                    get: { controllerService.partyModeEnabled },
                    set: { controllerService.setPartyMode($0, savedSettings: settings) }
                ))

                if controllerService.partyModeEnabled {
                    Text("Rainbow lightbar, cycling player LEDs, breathing mute button")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        profileManager.updateDualSenseLEDSettings(newSettings)
        applySettingsToController()
    }

    private func updateColor(_ color: Color) {
        var newSettings = settings
        newSettings.lightBarColor = CodableColor(color: color)
        profileManager.updateDualSenseLEDSettings(newSettings)
        applySettingsToController()
    }

    private func applySettingsToController() {
        if !controllerService.partyModeEnabled {
            controllerService.applyLEDSettings(settings)
        }
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

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var controllerService: ControllerService

    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("hideFromDock") private var hideFromDock = false
    @AppStorage(MainWindowSection.hiddenDefaultsKey) private var hiddenSectionTags = ""
    @AppStorage(ButtonMappingsTabSection.hiddenDefaultsKey) private var hiddenButtonSectionTags = ""
    @AppStorage("universalControlRelayHost") private var relayRemoteHost = "kmacstudio"
    @AppStorage("universalControlRelayPort") private var relayRemotePort = 38383

    @State private var isRefreshingDatabase = false
    @State private var databaseStatus: String?
    @State private var relayPairingCodeInput = ""
    @State private var relaySecretStatus: String?
    @State private var relaySecretStatusIsError = false
    @State private var relaySecretAlertMessage = ""
    @State private var showingRelaySecretAlert = false
    @State private var isCheckingRelaySecret = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ControllerKeys")
                        .font(.title2.bold())

                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.top, 2)

            Form {
                Toggle("Launch at Login", isOn: $launchAtLogin)

                Toggle(isOn: $hideFromDock) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide Dock Icon")
                        Text("Run as a menu bar app. The dock icon only appears while the main window is open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: hideFromDock) { _, _ in
                    // The DockVisibilityController owns the activation policy and
                    // ties it to window visibility. Just notify it that the
                    // preference flipped; it'll recompute and apply.
                    DockVisibilityController.shared.preferenceChanged()
                    NotificationCenter.default.post(name: .hideFromDockPreferenceDidChange, object: nil)
                    if !hideFromDock {
                        // Switching back to always-show — re-activate so the dock
                        // icon appears immediately even if no window is key.
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }

                Section {
                    ForEach(ButtonMappingsTabSection.allCases) { section in
                        Toggle(isOn: visibleButtonSectionBinding(for: section)) {
                            Text(section.label)
                        }
                    }

                    Button("Show All Button Sections") {
                        hiddenButtonSectionTags = ""
                    }
                } header: {
                    Text("Button Map Canvas")
                }

                ForEach(MainWindowNavGroup.allCases) { group in
                    Section {
                        ForEach(mainWindowSections(in: group)) { section in
                            Toggle(isOn: visibleSectionBinding(for: section)) {
                                HStack(spacing: 8) {
                                    Image(systemName: section.systemImage)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(section.label)
                                        if !section.isAvailable(
                                            isPlayStation: controllerService.threadSafeIsPlayStation,
                                            isDualSense: controllerService.threadSafeIsDualSense
                                        ) {
                                            Text(unavailableReason(for: section))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .disabled(!section.isAvailable(
                                isPlayStation: controllerService.threadSafeIsPlayStation,
                                isDualSense: controllerService.threadSafeIsDualSense
                            ) || isLastVisibleSection(section))
                        }
                    } header: {
                        Label(group.rawValue, systemImage: group.systemImage)
                    }
                }

                Section {
                    Button("Show All Main Sections") {
                        hiddenSectionTags = ""
                    }
                }

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Controller Database")
                                .font(.body)
                            Text("Maps generic controllers to Xbox layout")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isRefreshingDatabase {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Refresh") {
                                refreshDatabase()
                            }
                        }
                    }
                    if let status = databaseStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(status.contains("Error") ? .red : .secondary)
                    }
                } header: {
                    Text("Third-Party Controllers")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { ControllerService.isKeepAliveEnabled },
                        set: { newValue in
                            ControllerService.isKeepAliveEnabled = newValue
                            if newValue {
                                controllerService.startKeepAliveTimer()
                            } else {
                                controllerService.stopKeepAliveTimer()
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prevent Controller Sleep")
                            Text("Sends periodic signals to keep PlayStation controllers awake over Bluetooth")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Bluetooth")
                }

                Section {
					VStack(alignment: .leading, spacing: 12) {
						HStack(alignment: .top, spacing: 12) {
							VStack(alignment: .leading, spacing: 3) {
								Text("Pair a Remote Mac")
									.font(.body)
								Text("Start pairing, then enter the six-digit code shown on the other Mac.")
									.font(.caption)
									.foregroundStyle(.secondary)
									.fixedSize(horizontal: false, vertical: true)
							}

							Spacer(minLength: 12)

							Button {
								startRelayPairing()
							} label: {
								Label("Start", systemImage: "link")
							}
							.disabled(isCheckingRelaySecret)
						}

						HStack(alignment: .bottom, spacing: 8) {
							VStack(alignment: .leading, spacing: 4) {
								Text("Code")
									.font(.caption)
									.foregroundStyle(.secondary)

								ZStack {
									RoundedRectangle(cornerRadius: 5)
										.fill(Color(nsColor: .controlBackgroundColor))
									RoundedRectangle(cornerRadius: 5)
										.stroke(Color(nsColor: .separatorColor), lineWidth: 1)

									TextField("", text: relayPairingCodeBinding)
										.font(.system(size: 13, weight: .semibold, design: .monospaced))
										.multilineTextAlignment(.center)
										.textFieldStyle(.plain)
										.lineLimit(1)
										.frame(width: 68, height: 18)
										.clipped()
										.accessibilityLabel("Six-digit pairing code")
								}
								.frame(width: 88, height: 24)
							}

							Button {
								confirmRelayPairing()
							} label: {
								Label("Confirm", systemImage: "checkmark")
							}
							.disabled(isCheckingRelaySecret || relayPairingCodeInput.count != 6)

							if isCheckingRelaySecret {
								ProgressView()
									.controlSize(.small)
							}

							Spacer(minLength: 8)

							Button {
								resetRelayPairing()
							} label: {
								Label("Reset", systemImage: "arrow.counterclockwise")
							}
							.disabled(isCheckingRelaySecret)
						}
					}

                    DisclosureGroup("Advanced") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Remote Mac host")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                TextField("Optional hostname or Tailscale IP", text: $relayRemoteHost)
                                    .textFieldStyle(.roundedBorder)
                                    .disableAutocorrection(true)

                                TextField("Port", value: $relayRemotePort, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 84)
                            }
                        }
                    }

                    if let relaySecretStatus {
                        Label(
                            relaySecretStatus,
                            systemImage: relaySecretStatusIsError ? "xmark.circle.fill" : "checkmark.circle.fill"
                        )
                            .font(.caption)
                            .foregroundStyle(relaySecretStatusIsError ? .red : .secondary)
							.fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Remote Mouse Pairing")
                }
            }
            .formStyle(.grouped)
            .alert("Remote Mouse Pairing", isPresented: $showingRelaySecretAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(relaySecretAlertMessage)
            }

            Text("\u{00A9} 2026 Kevin Tang. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520, height: 720)
    }

    private func mainWindowSections(in group: MainWindowNavGroup) -> [MainWindowSection] {
        MainWindowSection.displayOrder.filter { $0.navGroup == group }
    }

    private func setRelaySecretStatus(_ message: String, isError: Bool, showAlert: Bool = true) {
        relaySecretStatus = message
        relaySecretStatusIsError = isError
        relaySecretAlertMessage = message
        showingRelaySecretAlert = showAlert
    }

	private var relayPairingCodeBinding: Binding<String> {
		Binding(
			get: { relayPairingCodeInput },
			set: { relayPairingCodeInput = String($0.filter { $0.isNumber }.prefix(6)) }
		)
	}

	private func startRelayPairing() {
		isCheckingRelaySecret = true
		relayPairingCodeInput = ""
		setRelaySecretStatus("Searching for ControllerKeys on LAN and tailnet...", isError: false, showAlert: false)
		UniversalControlMouseRelay.shared.startRelayCodePairing { success, message in
			isCheckingRelaySecret = false
			setRelaySecretStatus(message, isError: !success)
		}
	}

	private func confirmRelayPairing() {
		isCheckingRelaySecret = true
		UniversalControlMouseRelay.shared.completeRelayCodePairing(code: relayPairingCodeInput) { success, message in
			isCheckingRelaySecret = false
			if success {
				relayPairingCodeInput = ""
			}
			setRelaySecretStatus(message, isError: !success)
		}
	}

	private func resetRelayPairing() {
		UniversalControlMouseRelay.shared.resetRelayPairingSecret()
		relayPairingCodeInput = ""
		setRelaySecretStatus(
			"Reset. Pair again before using remote mouse.",
			isError: false
		)
	}

    private func visibleSectionBinding(for section: MainWindowSection) -> Binding<Bool> {
        Binding(
            get: {
                !MainWindowSection.hiddenSections(from: hiddenSectionTags).contains(section)
            },
            set: { isVisible in
                var hiddenSections = MainWindowSection.hiddenSections(from: hiddenSectionTags)
                if isVisible {
                    hiddenSections.remove(section)
                } else if !isLastVisibleSection(section) {
                    hiddenSections.insert(section)
                }
                hiddenSectionTags = MainWindowSection.encodedHiddenSections(hiddenSections)
            }
        )
    }

    private func isLastVisibleSection(_ section: MainWindowSection) -> Bool {
        let hiddenSections = MainWindowSection.hiddenSections(from: hiddenSectionTags)
        let visibleSections = MainWindowSection.visibleSections(
            hiddenSections: hiddenSections,
            isPlayStation: controllerService.threadSafeIsPlayStation,
            isDualSense: controllerService.threadSafeIsDualSense
        )
        return visibleSections.count == 1 && visibleSections.first == section
    }

    private func visibleButtonSectionBinding(for section: ButtonMappingsTabSection) -> Binding<Bool> {
        Binding(
            get: {
                !ButtonMappingsTabSection.hiddenSections(from: hiddenButtonSectionTags).contains(section)
            },
            set: { isVisible in
                var hiddenSections = ButtonMappingsTabSection.hiddenSections(from: hiddenButtonSectionTags)
                if isVisible {
                    hiddenSections.remove(section)
                } else {
                    hiddenSections.insert(section)
                }
                hiddenButtonSectionTags = ButtonMappingsTabSection.encodedHiddenSections(hiddenSections)
            }
        )
    }

    private func unavailableReason(for section: MainWindowSection) -> String {
        switch section {
        case .touchpad, .leds, .gestures:
            return "Requires a PlayStation controller"
        case .microphone:
            return "Requires a DualSense controller"
        default:
            return ""
        }
    }

    private func refreshDatabase() {
        isRefreshingDatabase = true
        databaseStatus = nil
        Task {
            do {
                let count = try await GameControllerDatabase.shared.refreshFromGitHub()
                databaseStatus = "Updated: \(count) controller mappings loaded"
            } catch {
                databaseStatus = "Error: \(error.localizedDescription)"
            }
            isRefreshingDatabase = false
        }
    }
}
