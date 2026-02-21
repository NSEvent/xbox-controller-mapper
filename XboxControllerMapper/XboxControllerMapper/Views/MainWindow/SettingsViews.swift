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
                    ForEach(StickMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
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

                SliderRow(
                    label: "Deadzone",
                    value: Binding(
                        get: { settings.mouseDeadzone },
                        set: { updateSettings(\.mouseDeadzone, $0) }
                    ),
                    range: 0...0.5,
                    description: settings.leftStickMode == .wasdKeys || settings.leftStickMode == .arrowKeys
                        ? "Activation threshold for keys"
                        : "Ignore small movements"
                )

                Toggle("Invert Y Axis", isOn: Binding(
                    get: { settings.invertMouseY },
                    set: { updateSettings(\.invertMouseY, $0) }
                ))
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

                        Toggle("⌥", isOn: Binding(
                            get: { settings.focusModeModifier.option },
                            set: {
                                var new = settings.focusModeModifier
                                new.option = $0
                                updateSettings(\.focusModeModifier, new)
                            }
                        ))
                        .toggleStyle(.button)

                        Toggle("⌃", isOn: Binding(
                            get: { settings.focusModeModifier.control },
                            set: {
                                var new = settings.focusModeModifier
                                new.control = $0
                                updateSettings(\.focusModeModifier, new)
                            }
                        ))
                        .toggleStyle(.button)

                        Toggle("⇧", isOn: Binding(
                            get: { settings.focusModeModifier.shift },
                            set: {
                                var new = settings.focusModeModifier
                                new.shift = $0
                                updateSettings(\.focusModeModifier, new)
                            }
                        ))
                        .toggleStyle(.button)
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
                    ForEach(StickMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
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

                SliderRow(
                    label: "Deadzone",
                    value: Binding(
                        get: { settings.scrollDeadzone },
                        set: { updateSettings(\.scrollDeadzone, $0) }
                    ),
                    range: 0...0.5,
                    description: settings.rightStickMode == .wasdKeys || settings.rightStickMode == .arrowKeys
                        ? "Activation threshold for keys"
                        : "Ignore small movements"
                )

                Toggle("Invert Y Axis", isOn: Binding(
                    get: { settings.invertScrollY },
                    set: { updateSettings(\.invertScrollY, $0) }
                ))
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

// MARK: - LED Settings View

struct LEDSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService

    var settings: DualSenseLEDSettings {
        profileManager.activeProfile?.dualSenseLEDSettings ?? .default
    }

    var body: some View {
        Form {
            if controllerService.isBluetoothConnection {
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("LED control requires USB connection on macOS. Settings will be applied when you connect via USB.")
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
                    LightBarColorPicker(
                        color: Binding(
                            get: { settings.lightBarColor.color },
                            set: { updateColor($0) }
                        )
                    )
                    .frame(height: 44)
                    .disabled(controllerService.partyModeEnabled)
                    .opacity(controllerService.partyModeEnabled ? 0.5 : 1.0)

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

            Section("Mute Button LED") {
                Picker("Mode", selection: Binding(
                    get: { settings.muteButtonLED },
                    set: { updateSettings(\.muteButtonLED, $0) }
                )) {
                    ForEach(MuteButtonLEDMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(controllerService.partyModeEnabled)
            }

            Section("Player LEDs") {
                HStack(spacing: 12) {
                    ForEach(0..<5) { index in
                        playerLEDToggle(index: index)
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(controllerService.partyModeEnabled)
                .opacity(controllerService.partyModeEnabled ? 0.5 : 1.0)

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
                .disabled(controllerService.partyModeEnabled)
            }

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
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var description: String? = nil

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

    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var isRefreshingDatabase = false
    @State private var databaseStatus: String?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            // App icon and info
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                Text("ControllerKeys")
                    .font(.title2.bold())

                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            Form {
                Toggle("Launch at Login", isOn: $launchAtLogin)

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
            }
            .formStyle(.grouped)

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
        .frame(width: 380, height: 400)
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
