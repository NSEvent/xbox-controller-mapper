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
    @State private var editingChord: ChordMapping?
    @State private var showingSettingsSheet = false
    @State private var selectedTab = 0
    @State private var lastScale: CGFloat = 1.0 // Track last scale for gesture
    @State private var isMagnifying = false // Track active magnification to prevent tap conflicts

    var body: some View {
        HSplitView {
            // Sidebar: Profile management
            ProfileSidebar()
                .frame(minWidth: 200, maxWidth: 260)
                .background(Color.black.opacity(0.2)) // Subtle darkening for sidebar

            // Main content
            VStack(spacing: 0) {
                // Toolbar
                toolbar
                    .zIndex(1) // Keep above content

                // Tab content
                TabView(selection: $selectedTab) {
                    // Controller Visual
                    controllerTab
                        .tabItem { Text("Buttons") }
                        .tag(0)

                    // Chords
                    chordsTab
                        .tabItem { Text("Chords") }
                        .tag(1)

                    // Macros Tab
                    macroListTab
                        .tabItem { Text("Macros") }
                        .tag(7)

                    // Joystick Settings
                    joystickSettingsTab
                        .tabItem { Text("Joysticks") }
                        .tag(2)

                    // On-Screen Keyboard Settings
                    keyboardSettingsTab
                        .tabItem { Text("Keyboard") }
                        .tag(3)

                    // Touchpad Settings (only shown when controller has touchpad)
                    if controllerService.threadSafeIsDualSense {
                        touchpadSettingsTab
                            .tabItem { Text("Touchpad") }
                            .tag(4)
                    }

                    // LED Settings (only shown for DualSense)
                    if controllerService.threadSafeIsDualSense {
                        ledSettingsTab
                            .tabItem { Text("LEDs") }
                            .tag(5)
                    }

                    // Microphone Settings (only shown for DualSense)
                    if controllerService.threadSafeIsDualSense {
                        microphoneSettingsTab
                            .tabItem { Text("Microphone") }
                            .tag(6)
                    }
                }
                .tabViewStyle(.automatic)
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        // Global Glass Background
        .background(
            ZStack {
                Color.black.opacity(0.75) // Dark tint
                GlassVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            }
            .ignoresSafeArea()
        )
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
        .sheet(item: $editingChord) { chord in
            ChordMappingSheet(editingChord: chord)
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsSheet()
        }
        // Add keyboard shortcuts for scaling
        .background(
            Button("Zoom In") { profileManager.setUiScale(min(profileManager.uiScale + 0.1, 2.0)) }
                .keyboardShortcut("+", modifiers: .command)
                .hidden()
        )
        .background(
            Button("Zoom Out") { profileManager.setUiScale(max(profileManager.uiScale - 0.1, 0.5)) }
                .keyboardShortcut("-", modifiers: .command)
                .hidden()
        )
        .background(
            Button("Reset Zoom") { profileManager.setUiScale(1.0) }
                .keyboardShortcut("0", modifiers: .command)
                .hidden()
        )
        .highPriorityGesture(
            MagnificationGesture()
                .onChanged { value in
                    isMagnifying = true
                    let delta = value / lastScale
                    lastScale = value
                    profileManager.uiScale = min(max(profileManager.uiScale * delta, 0.5), 2.0)
                }
                .onEnded { _ in
                    lastScale = 1.0
                    profileManager.setUiScale(profileManager.uiScale)
                    // Delay resetting isMagnifying to prevent tap events that fire at gesture end
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isMagnifying = false
                    }
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
                    .shadow(color: (controllerService.isConnected ? Color.green : Color.red).opacity(0.6), radius: 4)

                Text(controllerService.isConnected ? controllerService.controllerName : "No Controller")
                    .font(.caption.bold())
                    .foregroundColor(controllerService.isConnected ? .white : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

            Spacer()

            Spacer()

            // Enable/disable toggle
            Toggle(isOn: $mappingEngine.isEnabled) {
                Text(mappingEngine.isEnabled ? "MAPPING ACTIVE" : "DISABLED")
                    .font(.caption.bold())
                    .foregroundColor(mappingEngine.isEnabled ? .accentColor : .secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Transparent toolbar to let glass show through
    }

    // MARK: - Controller Tab

    private var controllerTab: some View {
        VStack(spacing: 0) {
            InputLogView()
                .padding(.top, 8)
            
            ZStack {
                ControllerVisualView(
                    selectedButton: $selectedButton,
                    onButtonTap: { button in
                        // Ignore taps during magnification gestures to prevent accidental triggers
                        guard !isMagnifying else { return }
                        // Async dispatch to avoid layout recursion if triggered during layout pass
                        DispatchQueue.main.async {
                            selectedButton = button
                            configuringButton = button
                        }
                    }
                )
                .scaleEffect(profileManager.uiScale)
                .allowsHitTesting(!isMagnifying)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Mapped Chords Display
            if let profile = profileManager.activeProfile, !profile.chordMappings.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.1))
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("ACTIVE CHORDS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    FlowLayout(data: profile.chordMappings, spacing: 10) { chord in
                        HStack(spacing: 10) {
                            HStack(spacing: 2) {
                                ForEach(Array(chord.buttons).sorted(by: { $0.category.chordDisplayOrder < $1.category.chordDisplayOrder }), id: \.self) { button in
                                    ButtonIconView(button: button, isDualSense: controllerService.threadSafeIsDualSense)
                                }
                            }

                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.3))

                            if let macroId = chord.macroId,
                               let macro = profile.macros.first(where: { $0.id == macroId }) {
                                Text("Macro: \(macro.name)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.purple)
                                    .lineLimit(1)
                            } else {
                                Text(chord.hint ?? chord.actionDisplayString)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .tooltipIfPresent(chord.hint != nil ? chord.actionDisplayString : nil)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(GlassCardBackground())
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                .padding(.top, 12)
            }
        }
    }


    // MARK: - Chords Tab

    private var chordsTab: some View {
        Form {
            Section {
                Button(action: { showingChordSheet = true }) {
                    Label("Add New Chord", systemImage: "plus")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)

                if let profile = profileManager.activeProfile, !profile.chordMappings.isEmpty {
                    ChordListView(
                        chords: profile.chordMappings,
                        isDualSense: controllerService.threadSafeIsDualSense,
                        onEdit: { chord in
                            editingChord = chord
                        },
                        onDelete: { chord in
                            profileManager.removeChord(chord)
                        },
                        onMove: { source, destination in
                            profileManager.moveChords(from: source, to: destination)
                        }
                    )
                    .equatable()
                } else {
                    Text("No chords configured")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                }
            } header: {
                Text("Chord Mappings")
                    .foregroundColor(.secondary)
            } footer: {
                Text("Chords let you map multiple button presses to a single action.")
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }

    // MARK: - Joystick Settings Tab

    private var joystickSettingsTab: some View {
        JoystickSettingsView()
            .scrollContentBackground(.hidden)
    }

    // MARK: - Touchpad Settings Tab

    private var touchpadSettingsTab: some View {
        TouchpadSettingsView()
            .scrollContentBackground(.hidden)
    }

    // MARK: - LED Settings Tab

    private var ledSettingsTab: some View {
        LEDSettingsView()
            .scrollContentBackground(.hidden)
    }

    // MARK: - Microphone Settings Tab

    private var microphoneSettingsTab: some View {
        MicrophoneSettingsView()
            .scrollContentBackground(.hidden)
    }

    private var keyboardSettingsTab: some View {
        OnScreenKeyboardSettingsView()
            .scrollContentBackground(.hidden)
    }
    
    // MARK: - Macro List Tab
    
    private var macroListTab: some View {
        MacroListView()
            .scrollContentBackground(.hidden)
    }
}

// MARK: - Profile Sidebar

struct ProfileSidebar: View {
    @EnvironmentObject var profileManager: ProfileManager

    @State private var showingNewProfileAlert = false
    @State private var newProfileName = ""
    @State private var showingRenameProfileAlert = false
    @State private var renameProfileName = ""
    @State private var profileToRename: Profile?
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var profileToExport: Profile?
    @State private var hoveredProfileId: UUID?
    @State private var profileToLink: Profile?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PROFILES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.accentColor)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            // Profile list
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(profileManager.profiles) { profile in
                        ProfileListRow(profile: profile, isHovered: hoveredProfileId == profile.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                profileManager.setActiveProfile(profile)
                            }
                            .onHover { isHovered in
                                hoveredProfileId = isHovered ? profile.id : nil
                            }
                            .background(
                                GlassCardBackground(
                                    isActive: profile.id == profileManager.activeProfileId,
                                    isHovered: hoveredProfileId == profile.id
                                )
                            )
                            .padding(.horizontal, 12)
                            .contextMenu {
                                Button("Duplicate") {
                                    _ = profileManager.duplicateProfile(profile)
                                }

                                Button("Rename") {
                                    profileToRename = profile
                                    renameProfileName = profile.name
                                    showingRenameProfileAlert = true
                                }
                                
                                Button("Linked Apps...") {
                                    profileToLink = profile
                                }

                                Menu("Set Icon") {
                                    ForEach(ProfileIcon.grouped, id: \.name) { group in
                                        Menu(group.name) {
                                            ForEach(group.icons) { icon in
                                                Button {
                                                    profileManager.setProfileIcon(profile, icon: icon.rawValue)
                                                } label: {
                                                    Label(icon.displayName, systemImage: icon.rawValue)
                                                }
                                            }
                                        }
                                    }

                                    Divider()

                                    Button("Remove Icon") {
                                        profileManager.setProfileIcon(profile, icon: nil)
                                    }
                                    .disabled(profile.icon == nil)
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
                .padding(.vertical, 8)
            }
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
        .alert("Rename Profile", isPresented: $showingRenameProfileAlert) {
            TextField("Profile name", text: $renameProfileName)
            Button("Cancel", role: .cancel) {
                renameProfileName = ""
                profileToRename = nil
            }
            Button("Rename") {
                if !renameProfileName.isEmpty, let profile = profileToRename {
                    profileManager.renameProfile(profile, to: renameProfileName)
                }
                renameProfileName = ""
                profileToRename = nil
            }
        }
        .sheet(item: $profileToLink) { profile in
            LinkedAppsSheet(profile: profile)
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
                    // Import failed, profile not loaded
                }
            case .failure:
                #if DEBUG
                print("File import failed")
                #endif
                // File selection failed
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: ProfileDocument(profile: profileToExport),
            contentType: .json,
            defaultFilename: profileToExport?.name ?? "Profile"
        ) { result in
            // Export completed, success or failure handled by system
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
    let isHovered: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                Text("\(profile.buttonMappings.count) mappings")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            if let iconName = profile.icon {
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundColor(.accentColor)
            } else if profile.isDefault {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.5), radius: 2)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Chord List

struct ChordListView: View, Equatable {
    let chords: [ChordMapping]
    let isDualSense: Bool
    let onEdit: (ChordMapping) -> Void
    let onDelete: (ChordMapping) -> Void
    let onMove: (IndexSet, Int) -> Void

    static func == (lhs: ChordListView, rhs: ChordListView) -> Bool {
        lhs.chords == rhs.chords && lhs.isDualSense == rhs.isDualSense
    }

    var body: some View {
        ForEach(chords) { chord in
            ChordRow(
                chord: chord,
                isDualSense: isDualSense,
                onEdit: { onEdit(chord) },
                onDelete: { onDelete(chord) }
            )
            .background(GlassCardBackground())
            .padding(.bottom, 4)
        }
        .onMove(perform: onMove)
    }
}

// MARK: - Chord Row

struct ChordRow: View {
    let chord: ChordMapping
    let isDualSense: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void
    
    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.white.opacity(0.3))
                .font(.caption)
                .frame(width: 20)

            HStack(spacing: 4) {
                ForEach(Array(chord.buttons).sorted(by: { $0.category.chordDisplayOrder < $1.category.chordDisplayOrder }), id: \.self) { button in
                    ButtonIconView(button: button, isDualSense: isDualSense)
                }
            }

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.3))

            if let macroId = chord.macroId,
               let profile = profileManager.activeProfile,
               let macro = profile.macros.first(where: { $0.id == macroId }) {
                Text("Macro: \(macro.name)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.purple.opacity(0.9))
            } else {
                Text(chord.hint ?? chord.actionDisplayString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .tooltipIfPresent(chord.hint != nil ? chord.actionDisplayString : nil)
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Glass Aesthetic Components

/// A view that wraps NSVisualEffectView for SwiftUI
struct GlassVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// A standardized glass tile background for cards and rows
struct GlassCardBackground: View {
    var isActive: Bool = false
    var isHovered: Bool = false
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            if isActive {
                Color.accentColor.opacity(0.2)
            } else {
                Color.black.opacity(0.4)
            }
            
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderColor, lineWidth: isActive ? 1.5 : 1)
        }
        .cornerRadius(cornerRadius)
        .shadow(color: isActive ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.2), radius: isActive ? 8 : 4)
    }
    
    private var borderColor: Color {
        if isActive { return Color.accentColor.opacity(0.8) }
        if isHovered { return Color.white.opacity(0.3) }
        return Color.white.opacity(0.1)
    }
}

// MARK: - Chord Mapping Sheet

struct ChordMappingSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss

    var editingChord: ChordMapping?

    private var isDualSense: Bool {
        controllerService.threadSafeIsDualSense
    }

    @State private var selectedButtons: Set<ControllerButton> = []
    @State private var keyCode: CGKeyCode?
    @State private var modifiers = ModifierFlags()
    @State private var hint: String = ""
    @State private var showingKeyboard = false
    
    // Macro support
    @State private var mappingType: MappingType = .singleKey
    @State private var selectedMacroId: UUID?

    enum MappingType: Int {
        case singleKey = 0
        case macro = 1
    }

    private var isEditing: Bool { editingChord != nil }

    /// Whether the current button combination already exists as a chord (excluding the one being edited)
    private var chordAlreadyExists: Bool {
        guard selectedButtons.count >= 2,
              let profile = profileManager.activeProfile else { return false }
        return profile.chordMappings.contains { chord in
            chord.buttons == selectedButtons && chord.id != editingChord?.id
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(isEditing ? "Edit Chord" : "Add Chord")
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
                    
                    // Middle Row: D-Pad, System, Face Buttons, Sticks
                    HStack(alignment: .top, spacing: 40) {
                        // Left Column: D-Pad & L3 Stick
                        VStack(spacing: 25) {
                            // D-Pad Cross (aligned with face buttons)
                            VStack(spacing: 2) {
                                toggleButton(.dpadUp)
                                HStack(spacing: 25) {
                                    toggleButton(.dpadLeft)
                                    toggleButton(.dpadRight)
                                }
                                toggleButton(.dpadDown)
                            }

                            toggleButton(.leftThumbstick)
                        }
                        
                        // Center Column: System Buttons
                        VStack(spacing: 15) {
                            toggleButton(.xbox)
                            HStack(spacing: 25) {
                                toggleButton(.view)
                                toggleButton(.menu)
                            }
                            // Show mic mute for DualSense, share for Xbox
                            if isDualSense {
                                toggleButton(.micMute)
                            } else {
                                toggleButton(.share)
                            }
                            // Touchpad button only for DualSense
                            if isDualSense {
                                toggleButton(.touchpadButton)
                            }
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
                HStack {
                    Text("Action:")
                        .font(.subheadline)

                    Spacer()
                    
                    Picker("", selection: $mappingType) {
                        Text("Single Key").tag(MappingType.singleKey)
                        Text("Macro").tag(MappingType.macro)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .padding(.trailing, 8)

                    if mappingType == .singleKey {
                        Button(action: { showingKeyboard.toggle() }) {
                            HStack(spacing: 6) {
                                Image(systemName: showingKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                                Text(showingKeyboard ? "Hide Keyboard" : "Show Keyboard")
                            }
                            .font(.callout)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }

                if mappingType == .singleKey {
                    if showingKeyboard {
                        KeyboardVisualView(selectedKeyCode: $keyCode, modifiers: $modifiers)
                    } else {
                        KeyCaptureField(keyCode: $keyCode, modifiers: $modifiers)

                        Text("Click to type a shortcut, or show keyboard to select visually")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // MACRO SELECTION
                    if let profile = profileManager.activeProfile, !profile.macros.isEmpty {
                        Picker("Select Macro", selection: $selectedMacroId) {
                            Text("Select a Macro...").tag(nil as UUID?)
                            ForEach(profile.macros) { macro in
                                Text(macro.name).tag(macro.id as UUID?)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 8) {
                            Text("No macros defined in this profile.")
                                .foregroundColor(.secondary)
                                .italic()
                                
                            Text("Go to the Macros tab to create a new macro.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                    }
                }

                // Hint field
                HStack {
                    Text("Hint:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("e.g. Copy, Paste, Switch App...", text: $hint)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button(isEditing ? "Save" : "Add") {
                    let hintValue = hint.isEmpty ? nil : hint
                    
                    // Determine values based on type
                    let finalKeyCode = mappingType == .singleKey ? keyCode : nil
                    let finalModifiers = mappingType == .singleKey ? modifiers : ModifierFlags()
                    let finalMacroId = mappingType == .macro ? selectedMacroId : nil
                    
                    if let existingChord = editingChord {
                        var updatedChord = existingChord
                        updatedChord.buttons = selectedButtons
                        updatedChord.keyCode = finalKeyCode
                        updatedChord.modifiers = finalModifiers
                        updatedChord.macroId = finalMacroId
                        updatedChord.hint = hintValue
                        profileManager.updateChord(updatedChord)
                    } else {
                        let chord = ChordMapping(
                            buttons: selectedButtons,
                            keyCode: finalKeyCode,
                            modifiers: finalModifiers,
                            macroId: finalMacroId,
                            hint: hintValue
                        )
                        profileManager.addChord(chord)
                    }
                    dismiss()
                }
                .disabled(selectedButtons.count < 2 || (mappingType == .singleKey && keyCode == nil && !modifiers.hasAny) || (mappingType == .macro && selectedMacroId == nil))
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 850)
        .onAppear {
            if let chord = editingChord {
                selectedButtons = chord.buttons
                keyCode = chord.keyCode
                modifiers = chord.modifiers
                hint = chord.hint ?? ""
                
                if let macroId = chord.macroId {
                    mappingType = .macro
                    selectedMacroId = macroId
                } else {
                    mappingType = .singleKey
                }
            }
        }
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
            ButtonIconView(button: button, isPressed: selectedButtons.contains(button), isDualSense: isDualSense)
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
    
    private enum SelectionShape {
        case circle, square, roundedRect
    }

    @ViewBuilder
    private func selectionBorder(for button: ControllerButton) -> some View {
        let borderColor: Color = chordAlreadyExists ? .gray : .accentColor
        let shape: SelectionShape = {
            switch button {
            case .micMute:
                return .circle  // Mic mute is circular
            case .touchpadButton:
                return .square  // Touchpad click is square
            default:
                switch button.category {
                case .face, .special, .thumbstick, .dpad:
                    return .circle
                default:
                    return .roundedRect
                }
            }
        }()

        switch shape {
        case .circle:
            Circle()
                .stroke(borderColor, lineWidth: 3)
                .shadow(color: borderColor.opacity(0.8), radius: 4)
        case .square:
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: 3)
                .shadow(color: borderColor.opacity(0.8), radius: 4)
                .aspectRatio(1, contentMode: .fit)
        case .roundedRect:
            RoundedRectangle(cornerRadius: 5)
                .stroke(borderColor, lineWidth: 3)
                .shadow(color: borderColor.opacity(0.8), radius: 4)
        }
    }

    private func buttonWidth(for button: ControllerButton) -> CGFloat {
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return 28
        case .bumper, .trigger: return 42
        case .touchpad: return 48
        }
    }

    private func buttonHeight(for button: ControllerButton) -> CGFloat {
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return 28
        case .bumper, .trigger: return 22
        case .touchpad: return 24
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

                SliderRow(
                    label: "Double-Tap Boost",
                    value: Binding(
                        get: { settings.scrollBoostMultiplier },
                        set: { updateSettings(\.scrollBoostMultiplier, $0) }
                    ),
                    range: 1...4,
                    description: "Speed multiplier after double-tap up/down"
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
                    description: "Reduce jitter"
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
    let inputLogService = InputLogService()
    let mappingEngine = MappingEngine(
        controllerService: controllerService,
        profileManager: profileManager,
        appMonitor: appMonitor,
        inputLogService: inputLogService
    )

    return ContentView()
        .environmentObject(controllerService)
        .environmentObject(profileManager)
        .environmentObject(appMonitor)
        .environmentObject(mappingEngine)
        .environmentObject(inputLogService)
}
