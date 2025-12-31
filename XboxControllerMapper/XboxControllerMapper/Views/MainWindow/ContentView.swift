import SwiftUI
import UniformTypeIdentifiers

/// Main window content view
struct ContentView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var appMonitor: AppMonitor
    @EnvironmentObject var mappingEngine: MappingEngine

    @State private var selectedButton: ControllerButton?
    @State private var configuringButton: ControllerButton?
    @State private var showingChordSheet = false
    @State private var showingSettingsSheet = false
    @State private var selectedTab = 0
    @State private var uiScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0 // Track last scale for gesture

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
        .frame(minWidth: 900, minHeight: 650)
        .sheet(item: $configuringButton) { button in
            ButtonMappingSheet(
                button: button,
                mapping: Binding(
                    get: { profileManager.activeProfile?.buttonMappings[button] },
                    set: { _ in }
                )
            )
        }
        .sheet(isPresented: $showingChordSheet) {
            ChordMappingSheet()
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsSheet()
        }
        // Add keyboard shortcuts for scaling
        .background(
            Button("Zoom In") { uiScale = min(uiScale + 0.1, 2.0) }
                .keyboardShortcut("+", modifiers: .command)
                .hidden()
        )
        .background(
            Button("Zoom Out") { uiScale = max(uiScale - 0.1, 0.5) }
                .keyboardShortcut("-", modifiers: .command)
                .hidden()
        )
        .background(
            Button("Reset Zoom") { uiScale = 1.0 }
                .keyboardShortcut("0", modifiers: .command)
                .hidden()
        )
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let delta = value / lastScale
                    lastScale = value
                    uiScale = min(max(uiScale * delta, 0.5), 2.0)
                }
                .onEnded { _ in
                    lastScale = 1.0
                }
        )
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
        VStack(spacing: 0) {
            ZStack {
                ControllerVisualView(
                    selectedButton: $selectedButton,
                    onButtonTap: { button in
                        // Async dispatch to avoid layout recursion if triggered during layout pass
                        DispatchQueue.main.async {
                            selectedButton = button
                            configuringButton = button
                        }
                    }
                )
                .scaleEffect(uiScale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Mapped Chords Display
            if let profile = profileManager.activeProfile, !profile.chordMappings.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chord Actions")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(profile.chordMappings) { chord in
                                HStack(spacing: 8) {
                                    HStack(spacing: 2) {
                                        ForEach(Array(chord.buttons).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { button in
                                            ButtonIconView(button: button)
                                        }
                                    }
                                    
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    Text(chord.actionDisplayString)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                }
                .padding(.top, 8)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
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
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var profileToExport: Profile?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Profiles")
                    .font(.headline)

                Spacer()

                Menu {
                    Button("New Profile") {
                        showingNewProfileAlert = true
                    }
                    Button("Import Profile...") {
                        isImporting = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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
                            
                            Button("Export...") {
                                profileToExport = profile
                                isExporting = true
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
            .scrollContentBackground(.hidden) // Optional: cleaner look
            // Prevent arrow keys from changing selection by disabling focus
            // Note: This might prevent keyboard navigation entirely for the list, which is what is requested.
            .focusable(false)
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
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let profile = try profileManager.importProfile(from: url)
                    profileManager.setActiveProfile(profile)
                } catch {
                    print("Import failed: \(error)")
                }
            case .failure(let error):
                print("Import failed: \(error)")
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: ProfileDocument(profile: profileToExport),
            contentType: .json,
            defaultFilename: profileToExport?.name ?? "Profile"
        ) { result in
            if case .failure(let error) = result {
                print("Export failed: \(error)")
            }
        }
    }
}

struct ProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var profile: Profile?

    init(profile: Profile?) {
        self.profile = profile
    }

    init(configuration: ReadConfiguration) throws {
        // Not used for export-only
        let data = try configuration.file.regularFileContents
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.profile = try? decoder.decode(Profile.self, from: data!)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let profile = profile else { throw CocoaError(.fileWriteUnknown) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(profile)
        return FileWrapper(regularFileWithContents: data)
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
            HStack(spacing: 4) {
                ForEach(Array(chord.buttons).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { button in
                    ButtonIconView(button: button)
                }
            }

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

                // Visual Controller Layout
                VStack(spacing: 10) {
                    // Top Row: Triggers & Bumpers
                    HStack(spacing: 120) {
                        VStack(spacing: 8) {
                            toggleButton(.leftTrigger)
                            toggleButton(.leftBumper)
                        }
                        
                        VStack(spacing: 8) {
                            toggleButton(.rightTrigger)
                            toggleButton(.rightBumper)
                        }
                    }
                    
                    // Middle Row: Sticks, D-Pad, Face Buttons, System
                    HStack(alignment: .top, spacing: 40) {
                        // Left Column: Stick & D-Pad
                        VStack(spacing: 25) {
                            toggleButton(.leftThumbstick)
                             
                            // D-Pad Cross
                            VStack(spacing: 2) {
                                toggleButton(.dpadUp)
                                HStack(spacing: 25) {
                                    toggleButton(.dpadLeft)
                                    toggleButton(.dpadRight)
                                }
                                toggleButton(.dpadDown)
                            }
                        }
                        
                        // Center Column: System Buttons
                        VStack(spacing: 15) {
                            toggleButton(.xbox)
                            HStack(spacing: 25) {
                                toggleButton(.view)
                                toggleButton(.menu)
                            }
                            toggleButton(.share)
                        }
                        .padding(.top, 15)
                        
                        // Right Column: Face Buttons & Stick
                        VStack(spacing: 25) {
                            // Face Buttons Diamond
                            VStack(spacing: 2) {
                                toggleButton(.y)
                                HStack(spacing: 25) {
                                    toggleButton(.x)
                                    toggleButton(.b)
                                }
                                toggleButton(.a)
                            }
                            
                            toggleButton(.rightThumbstick)
                        }
                    }
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
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
        .frame(width: 600)
    }
    
    @ViewBuilder
    private func toggleButton(_ button: ControllerButton) -> some View {
        let scale: CGFloat = 1.3
        
        Button(action: {
            if selectedButtons.contains(button) {
                selectedButtons.remove(button)
            } else {
                selectedButtons.insert(button)
            }
        }) {
            ButtonIconView(button: button, isPressed: selectedButtons.contains(button))
                .scaleEffect(scale)
                .frame(width: buttonWidth(for: button) * scale, height: buttonHeight(for: button) * scale)
                .opacity(selectedButtons.contains(button) ? 1.0 : 0.7)
                .overlay {
                    if selectedButtons.contains(button) {
                        selectionBorder(for: button)
                            .scaleEffect(scale)
                    }
                }
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func selectionBorder(for button: ControllerButton) -> some View {
        let isCircle: Bool = {
            switch button.category {
            case .face, .special, .thumbstick, .dpad: return true
            default: return false
            }
        }()
        
        if isCircle {
            Circle()
                .stroke(Color.accentColor, lineWidth: 3)
                .shadow(color: Color.accentColor.opacity(0.8), radius: 4)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.accentColor, lineWidth: 3)
                .shadow(color: Color.accentColor.opacity(0.8), radius: 4)
        }
    }

    private func buttonWidth(for button: ControllerButton) -> CGFloat {
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return 28
        case .bumper, .trigger: return 42
        }
    }
    
    private func buttonHeight(for button: ControllerButton) -> CGFloat {
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return 28
        case .bumper, .trigger: return 22
        }
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
