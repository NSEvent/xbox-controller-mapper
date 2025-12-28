import SwiftUI

/// Main window content view
struct ContentView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var appMonitor: AppMonitor
    @EnvironmentObject var mappingEngine: MappingEngine

    @State private var selectedButton: ControllerButton?
    @State private var showingMappingSheet = false
    @State private var showingChordSheet = false
    @State private var showingSettingsSheet = false
    @State private var selectedTab = 0

    var body: some View {
        HSplitView {
            // Sidebar: Profile management
            ProfileSidebar()
                .frame(minWidth: 180, maxWidth: 220)

            // Main content
            VStack(spacing: 0) {
                // Toolbar
                toolbar

                Divider()

                // Tab content
                TabView(selection: $selectedTab) {
                    // Controller Visual
                    controllerTab
                        .tag(0)

                    // Chords
                    chordsTab
                        .tag(1)

                    // Joystick Settings
                    joystickSettingsTab
                        .tag(2)
                }
                .tabViewStyle(.automatic)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $showingMappingSheet) {
            if let button = selectedButton {
                ButtonMappingSheet(
                    button: button,
                    mapping: Binding(
                        get: { profileManager.activeProfile?.buttonMappings[button] },
                        set: { _ in }
                    )
                )
            }
        }
        .sheet(isPresented: $showingChordSheet) {
            ChordMappingSheet()
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsSheet()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            // Connection status
            HStack(spacing: 8) {
                Circle()
                    .fill(controllerService.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(controllerService.isConnected ? controllerService.controllerName : "No Controller")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Buttons").tag(0)
                Text("Chords").tag(1)
                Text("Joysticks").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            Spacer()

            // Enable/disable toggle
            Toggle(isOn: $mappingEngine.isEnabled) {
                Text(mappingEngine.isEnabled ? "Enabled" : "Disabled")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Controller Tab

    private var controllerTab: some View {
        VStack(spacing: 20) {
            Spacer()

            ControllerVisualView(
                selectedButton: $selectedButton,
                onButtonTap: { button in
                    selectedButton = button
                    showingMappingSheet = true
                }
            )

            // Legend
            HStack(spacing: 20) {
                LegendItem(color: .gray.opacity(0.6), label: "Unmapped")
                LegendItem(color: .blue.opacity(0.8), label: "Mapped")
                LegendItem(color: .green, label: "Pressed")
                LegendItem(color: .accentColor, label: "Selected")
            }
            .font(.caption)

            Spacer()
        }
        .padding()
    }

    // MARK: - Chords Tab

    private var chordsTab: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Chord Mappings")
                    .font(.headline)

                Spacer()

                Button(action: { showingChordSheet = true }) {
                    Label("Add Chord", systemImage: "plus")
                }
            }
            .padding(.horizontal)
            .padding(.top)

            if let profile = profileManager.activeProfile, !profile.chordMappings.isEmpty {
                List {
                    ForEach(profile.chordMappings) { chord in
                        ChordRow(chord: chord) {
                            profileManager.removeChord(chord)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("No Chords Configured")
                        .font(.headline)

                    Text("Chords let you map multiple button presses to a single action")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Add Chord") {
                        showingChordSheet = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Joystick Settings Tab

    private var joystickSettingsTab: some View {
        JoystickSettingsView()
    }
}

// MARK: - Profile Sidebar

struct ProfileSidebar: View {
    @EnvironmentObject var profileManager: ProfileManager

    @State private var showingNewProfileAlert = false
    @State private var newProfileName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Profiles")
                    .font(.headline)

                Spacer()

                Button(action: { showingNewProfileAlert = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            // Profile list
            List(selection: Binding(
                get: { profileManager.activeProfileId },
                set: { id in
                    if let id = id, let profile = profileManager.profiles.first(where: { $0.id == id }) {
                        profileManager.setActiveProfile(profile)
                    }
                }
            )) {
                ForEach(profileManager.profiles) { profile in
                    ProfileListRow(profile: profile)
                        .tag(profile.id)
                        .contextMenu {
                            Button("Duplicate") {
                                _ = profileManager.duplicateProfile(profile)
                            }

                            Button("Rename") {
                                // Would show rename sheet
                            }

                            Divider()

                            Button("Delete", role: .destructive) {
                                profileManager.deleteProfile(profile)
                            }
                            .disabled(profileManager.profiles.count <= 1)
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .alert("New Profile", isPresented: $showingNewProfileAlert) {
            TextField("Profile name", text: $newProfileName)
            Button("Cancel", role: .cancel) {
                newProfileName = ""
            }
            Button("Create") {
                if !newProfileName.isEmpty {
                    let profile = profileManager.createProfile(name: newProfileName)
                    profileManager.setActiveProfile(profile)
                    newProfileName = ""
                }
            }
        }
    }
}

struct ProfileListRow: View {
    let profile: Profile

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body)

                Text("\(profile.buttonMappings.count) mappings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if profile.isDefault {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Legend Item

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
        }
    }
}

// MARK: - Chord Row

struct ChordRow: View {
    let chord: ChordMapping
    var onDelete: () -> Void

    var body: some View {
        HStack {
            Text(chord.buttonsDisplayString)
                .font(.body)

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)

            Text(chord.actionDisplayString)
                .font(.body)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Chord Mapping Sheet

struct ChordMappingSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedButtons: Set<ControllerButton> = []
    @State private var keyCode: CGKeyCode?
    @State private var modifiers = ModifierFlags()

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Chord")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Select buttons (2 or more):")
                    .font(.subheadline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 8) {
                    ForEach(ControllerButton.allCases) { button in
                        Toggle(isOn: Binding(
                            get: { selectedButtons.contains(button) },
                            set: { selected in
                                if selected {
                                    selectedButtons.insert(button)
                                } else {
                                    selectedButtons.remove(button)
                                }
                            }
                        )) {
                            Text(button.shortLabel)
                                .font(.caption)
                        }
                        .toggleStyle(.button)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Action:")
                    .font(.subheadline)

                KeyCaptureField(keyCode: $keyCode, modifiers: $modifiers)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Add") {
                    let chord = ChordMapping(
                        buttons: selectedButtons,
                        keyCode: keyCode,
                        modifiers: modifiers
                    )
                    profileManager.addChord(chord)
                    dismiss()
                }
                .disabled(selectedButtons.count < 2 || (keyCode == nil && !modifiers.hasAny))
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Joystick Settings View

struct JoystickSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager

    var settings: JoystickSettings {
        profileManager.activeProfile?.joystickSettings ?? .default
    }

    var body: some View {
        Form {
            Section("Left Joystick (Mouse)") {
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

            Section("Right Joystick (Scroll)") {
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
        .formStyle(.grouped)
        .padding()
    }

    private func updateSettings<T>(_ keyPath: WritableKeyPath<JoystickSettings, T>, _ value: T) {
        var newSettings = settings
        newSettings[keyPath: keyPath] = value
        profileManager.updateJoystickSettings(newSettings)
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

    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.headline)

            Form {
                Toggle("Launch at Login", isOn: $launchAtLogin)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 350, height: 200)
    }
}

#Preview {
    let controllerService = ControllerService()
    let profileManager = ProfileManager()
    let appMonitor = AppMonitor()
    let mappingEngine = MappingEngine(
        controllerService: controllerService,
        profileManager: profileManager,
        appMonitor: appMonitor
    )

    return ContentView()
        .environmentObject(controllerService)
        .environmentObject(profileManager)
        .environmentObject(appMonitor)
        .environmentObject(mappingEngine)
}
