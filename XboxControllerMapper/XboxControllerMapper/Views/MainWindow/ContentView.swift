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
    @State private var selectedLayerId: UUID? = nil // nil = base layer
    @State private var showingAddLayerSheet = false
    @State private var editingLayerId: UUID? = nil
    @State private var actionFeedbackEnabled: Bool = ActionFeedbackIndicator.isEnabled
    @State private var isSwapMode: Bool = false
    @State private var swapFirstButton: ControllerButton? = nil
    @State private var hoveredChordId: UUID? = nil

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

                    // On-Screen Keyboard Settings
                    keyboardSettingsTab
                        .tabItem { Text("Keyboard") }
                        .tag(3)

                    // Joystick Settings
                    joystickSettingsTab
                        .tabItem { Text("Joysticks") }
                        .tag(2)

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
                Color.black.opacity(0.92) // Dark tint
                GlassVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            }
            .ignoresSafeArea()
        )
        .sheet(item: $configuringButton) { button in
            ButtonMappingSheet(
                button: button,
                mapping: Binding(
                    get: {
                        // Get mapping from layer if editing a layer, otherwise from base
                        if let layerId = selectedLayerId,
                           let layer = profileManager.activeProfile?.layers.first(where: { $0.id == layerId }) {
                            return layer.buttonMappings[button]
                        }
                        return profileManager.activeProfile?.buttonMappings[button]
                    },
                    set: { _ in }
                ),
                isDualSense: controllerService.threadSafeIsDualSense,
                selectedLayerId: selectedLayerId
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

            Button {
                showingSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
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

            // Layer Tab Bar
            layerTabBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            GeometryReader { geometry in
                // Base size of ControllerVisualView content
                let baseWidth: CGFloat = 920
                let baseHeight: CGFloat = 580

                // Calculate scale to fit available space (allow both up and down scaling)
                let scaleX = geometry.size.width / baseWidth
                let scaleY = geometry.size.height / baseHeight
                let autoScale = min(scaleX, scaleY)

                // Combine with user's manual zoom setting
                let finalScale = autoScale * profileManager.uiScale

                ControllerVisualView(
                    selectedButton: $selectedButton,
                    selectedLayerId: selectedLayerId,
                    swapFirstButton: swapFirstButton,
                    isSwapMode: isSwapMode,
                    onButtonTap: { button in
                        // Ignore taps during magnification gestures to prevent accidental triggers
                        guard !isMagnifying else { return }
                        // Async dispatch to avoid layout recursion if triggered during layout pass
                        DispatchQueue.main.async {
                            if isSwapMode {
                                handleSwapButtonTap(button)
                            } else {
                                selectedButton = button
                                configuringButton = button
                            }
                        }
                    }
                )
                .scaleEffect(finalScale)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(!isMagnifying)
            }
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

                            if let systemCommand = chord.systemCommand {
                                Text(chord.hint ?? systemCommand.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                                    .lineLimit(1)
                                    .tooltipIfPresent(chord.hint != nil ? systemCommand.displayName : nil)
                            } else if let macroId = chord.macroId,
                               let macro = profile.macros.first(where: { $0.id == macroId }) {
                                Text(chord.hint ?? macro.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.purple)
                                    .lineLimit(1)
                                    .tooltipIfPresent(chord.hint != nil ? macro.name : nil)
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
                        .background(GlassCardBackground(isHovered: hoveredChordId == chord.id))
                        .cornerRadius(10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingChord = chord
                        }
                        .onHover { isHovered in
                            hoveredChordId = isHovered ? chord.id : nil
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                .padding(.top, 12)
            }
        }
        .sheet(isPresented: $showingAddLayerSheet) {
            AddLayerSheet()
        }
        .sheet(item: $editingLayerId) { layerId in
            if let profile = profileManager.activeProfile,
               let layer = profile.layers.first(where: { $0.id == layerId }) {
                EditLayerSheet(layer: layer)
            }
        }
        .onChange(of: controllerService.activeButtons) { _, activeButtons in
            guard let profile = profileManager.activeProfile else { return }

            // Check if any layer activator is being held
            for layer in profile.layers {
                if let activator = layer.activatorButton, activeButtons.contains(activator) {
                    selectedLayerId = layer.id
                    return
                }
            }

            // No layer activator held - return to base layer
            selectedLayerId = nil
        }
    }

    // MARK: - Layer Tab Bar

    private var layerTabBar: some View {
        HStack(spacing: 8) {
            // Base Layer tab (always present)
            Button {
                selectedLayerId = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.caption)
                    Text("Base Layer")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedLayerId == nil ? Color.accentColor : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .foregroundColor(selectedLayerId == nil ? .white : .secondary)

            // Layer tabs
            if let profile = profileManager.activeProfile {
                ForEach(profile.layers) { layer in
                    Button {
                        selectedLayerId = layer.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(layer.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            // Activator button badge (or "No Activator" if unassigned)
                            if let activator = layer.activatorButton {
                                Text(activator.shortLabel(forDualSense: controllerService.threadSafeIsDualSense))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.8))
                                    .cornerRadius(4)
                            } else {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedLayerId == layer.id ? Color.accentColor : Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(selectedLayerId == layer.id ? .white : .secondary)
                    .contextMenu {
                        Button("Rename...") {
                            editingLayerId = layer.id
                        }
                        Button("Delete", role: .destructive) {
                            profileManager.deleteLayer(layer)
                            if selectedLayerId == layer.id {
                                selectedLayerId = nil
                            }
                        }
                    }
                }
            }

            // Add Layer button (if under max)
            if let profile = profileManager.activeProfile, profile.layers.count < ProfileManager.maxLayers {
                Button {
                    showingAddLayerSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption)
                        Text("Add Layer")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Swap mode toggle
            Toggle(isOn: $isSwapMode) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10))
                    Text(swapFirstButton != nil ? "Select 2nd" : "Swap")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSwapMode ? Color.orange : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundColor(isSwapMode ? .white : .secondary)
            .onChange(of: isSwapMode) { _, newValue in
                if !newValue {
                    swapFirstButton = nil
                }
            }

            // Action feedback toggle (styled like layer tabs)
            Toggle(isOn: $actionFeedbackEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 10))
                    Text("Cursor Hints")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(actionFeedbackEnabled ? Color.accentColor : Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundColor(actionFeedbackEnabled ? .white : .secondary)
            .onChange(of: actionFeedbackEnabled) { _, newValue in
                ActionFeedbackIndicator.isEnabled = newValue
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

    // MARK: - Swap Mode

    private func handleSwapButtonTap(_ button: ControllerButton) {
        if let firstButton = swapFirstButton {
            // Second button selected - perform the swap
            if let layerId = selectedLayerId {
                profileManager.swapLayerMappings(button1: firstButton, button2: button, in: layerId)
            } else {
                profileManager.swapMappings(button1: firstButton, button2: button)
            }
            // Exit swap mode
            swapFirstButton = nil
            isSwapMode = false
        } else {
            // First button selected
            swapFirstButton = button
        }
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
    @State private var showingCommunityProfiles = false

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
                    Button("Import Community Profile...") {
                        showingCommunityProfiles = true
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
        .sheet(isPresented: $showingCommunityProfiles) {
            CommunityProfilesSheet()
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

// MARK: - Community Profiles Sheet

struct CommunityProfilesSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss

    @State private var availableProfiles: [CommunityProfileInfo] = []
    @State private var selectedProfiles: Set<String> = []
    @State private var alreadyImportedProfiles: Set<String> = []
    @State private var isLoading = true
    @State private var isDownloading = false
    @State private var errorMessage: String?
    @State private var downloadedCount = 0

    // Preview state
    @State private var previewingProfileId: String?
    @State private var previewedProfile: Profile?
    @State private var isLoadingPreview = false
    @State private var previewCache: [String: Profile] = [:]

    // Count of new profiles to import (excludes already imported)
    private var newProfilesToImportCount: Int {
        selectedProfiles.subtracting(alreadyImportedProfiles).count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Community Profiles")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding()

            Divider()

            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading profiles...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        loadProfiles()
                    }
                }
                .padding()
                Spacer()
            } else if availableProfiles.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No community profiles available")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                HStack(spacing: 0) {
                    // Left: Profile list
                    VStack(spacing: 0) {
                        List(availableProfiles) { profileInfo in
                            CommunityProfileRow(
                                profileInfo: profileInfo,
                                isSelected: selectedProfiles.contains(profileInfo.id),
                                isAlreadyImported: alreadyImportedProfiles.contains(profileInfo.id),
                                isPreviewing: previewingProfileId == profileInfo.id,
                                onToggleSelect: {
                                    // Don't allow unchecking already-imported profiles
                                    if alreadyImportedProfiles.contains(profileInfo.id) {
                                        return
                                    }
                                    if selectedProfiles.contains(profileInfo.id) {
                                        selectedProfiles.remove(profileInfo.id)
                                    } else {
                                        selectedProfiles.insert(profileInfo.id)
                                    }
                                },
                                onPreview: {
                                    loadPreview(for: profileInfo)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        }
                        .listStyle(.plain)
                    }
                    .frame(width: 220)

                    Divider()

                    // Right: Preview panel
                    CommunityProfilePreview(
                        profile: previewedProfile,
                        profileName: availableProfiles.first { $0.id == previewingProfileId }?.displayName,
                        isLoading: isLoadingPreview
                    )
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()

            // Footer
            HStack {
                if !availableProfiles.isEmpty {
                    let allNewSelected = selectedProfiles.subtracting(alreadyImportedProfiles).count == availableProfiles.count - alreadyImportedProfiles.count
                    Button(allNewSelected ? "Deselect All" : "Select All") {
                        if allNewSelected {
                            // Deselect all except already-imported
                            selectedProfiles = alreadyImportedProfiles
                        } else {
                            // Select all
                            selectedProfiles = Set(availableProfiles.map { $0.id })
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                Spacer()

                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Downloading \(downloadedCount)/\(newProfilesToImportCount)...")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    Button("Import \(newProfilesToImportCount) Profile\(newProfilesToImportCount == 1 ? "" : "s")") {
                        downloadSelectedProfiles()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newProfilesToImportCount == 0)
                }
            }
            .padding()
        }
        .frame(width: 700, height: 500)
        .onAppear {
            loadProfiles()
        }
    }

    private func loadProfiles() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let profiles = try await profileManager.fetchCommunityProfiles()
                await MainActor.run {
                    availableProfiles = profiles

                    // Mark and pre-select profiles that have already been imported
                    let existingProfileNames = Set(profileManager.profiles.map { $0.name })
                    for profile in profiles {
                        if existingProfileNames.contains(profile.displayName) {
                            selectedProfiles.insert(profile.id)
                            alreadyImportedProfiles.insert(profile.id)
                        }
                    }

                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func loadPreview(for profileInfo: CommunityProfileInfo) {
        previewingProfileId = profileInfo.id

        // Check cache first
        if let cached = previewCache[profileInfo.id] {
            previewedProfile = cached
            return
        }

        isLoadingPreview = true
        previewedProfile = nil

        Task {
            do {
                let profile = try await profileManager.fetchProfileForPreview(from: profileInfo.downloadURL)
                await MainActor.run {
                    previewCache[profileInfo.id] = profile
                    // Only update if still previewing the same profile
                    if previewingProfileId == profileInfo.id {
                        previewedProfile = profile
                    }
                    isLoadingPreview = false
                }
            } catch {
                await MainActor.run {
                    isLoadingPreview = false
                }
            }
        }
    }

    private func downloadSelectedProfiles() {
        isDownloading = true
        downloadedCount = 0

        // Only download profiles that aren't already imported
        let profilesToDownload = availableProfiles.filter {
            selectedProfiles.contains($0.id) && !alreadyImportedProfiles.contains($0.id)
        }

        Task {
            var lastImportedProfile: Profile?

            for profileInfo in profilesToDownload {
                do {
                    // Use cached profile if available, otherwise download
                    let profile: Profile
                    if let cached = previewCache[profileInfo.id] {
                        profile = await MainActor.run {
                            profileManager.importFetchedProfile(cached)
                        }
                    } else {
                        profile = try await profileManager.downloadProfile(from: profileInfo.downloadURL)
                    }
                    lastImportedProfile = profile
                    await MainActor.run {
                        downloadedCount += 1
                    }
                } catch {
                    #if DEBUG
                    print("Failed to download profile \(profileInfo.name): \(error)")
                    #endif
                }
            }

            await MainActor.run {
                isDownloading = false
                if let profile = lastImportedProfile {
                    profileManager.setActiveProfile(profile)
                }
                dismiss()
            }
        }
    }
}

// MARK: - Community Profile Row

struct CommunityProfileRow: View {
    let profileInfo: CommunityProfileInfo
    let isSelected: Bool
    let isAlreadyImported: Bool
    let isPreviewing: Bool
    let onToggleSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox - disabled for already-imported profiles
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isAlreadyImported ? .secondary : (isSelected ? .accentColor : .secondary))
            }
            .buttonStyle(.plain)
            .disabled(isAlreadyImported)

            // Profile name (clickable for preview)
            Text(profileInfo.displayName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(isAlreadyImported ? .secondary : .primary)

            // Already imported indicator
            if isAlreadyImported {
                Text("Imported")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }

            // Preview indicator
            if isPreviewing {
                Image(systemName: "eye.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isPreviewing ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onToggleSelect()
            onPreview()
        }
        .onTapGesture(count: 1) {
            onPreview()
        }
    }
}

// MARK: - Community Profile Preview

struct CommunityProfilePreview: View {
    let profile: Profile?
    let profileName: String?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Loading preview...")
                Spacer()
            } else if let profile = profile {
                // Header
                HStack {
                    Text(profileName ?? profile.name)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(profile.buttonMappings.count) mappings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !profile.chordMappings.isEmpty {
                        Text("• \(profile.chordMappings.count) chords")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Mappings list
                ScrollView {
                    VStack(spacing: 6) {
                        // Button mappings
                        ForEach(ControllerButton.allCases.filter { profile.buttonMappings[$0] != nil }, id: \.self) { button in
                            if let mapping = profile.buttonMappings[button], !mapping.isEmpty {
                                PreviewMappingRow(button: button, mapping: mapping, profile: profile)
                            }
                        }

                        // Chord mappings
                        if !profile.chordMappings.isEmpty {
                            Divider()
                                .padding(.vertical, 12)

                            HStack {
                                Text("CHORDS")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                            VStack(spacing: 8) {
                                ForEach(profile.chordMappings) { chord in
                                    PreviewChordRow(chord: chord, profile: profile)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                // Empty state - no profile selected
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "gamecontroller")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.secondary.opacity(0.3))

                    VStack(spacing: 4) {
                        Text("Preview")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("Click a profile to see its mappings")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.4))
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.opacity(0.15))
    }
}

// MARK: - Preview Mapping Row

struct PreviewMappingRow: View {
    @EnvironmentObject var controllerService: ControllerService

    let button: ControllerButton
    let mapping: KeyMapping
    let profile: Profile

    var body: some View {
        HStack(spacing: 12) {
            ButtonIconView(button: button, isPressed: false, isDualSense: controllerService.threadSafeIsDualSense)
                .frame(width: 28, height: 28)

            // Show mappings with hint + actual shortcut side by side
            HStack(spacing: 16) {
                // Primary mapping
                if let systemCommand = mapping.systemCommand {
                    PreviewMappingLabel(text: systemCommand.displayName, shortcut: nil, icon: "SYS", color: .green)
                } else if let macroId = mapping.macroId,
                          let macro = profile.macros.first(where: { $0.id == macroId }) {
                    PreviewMappingLabel(
                        text: mapping.hint ?? macro.name,
                        shortcut: mapping.hint != nil ? "Macro: \(macro.name)" : nil,
                        icon: "▶",
                        color: .purple
                    )
                } else if !mapping.isEmpty {
                    PreviewMappingLabel(
                        text: mapping.hint ?? mapping.displayString,
                        shortcut: mapping.hint != nil ? mapping.displayString : nil,
                        icon: mapping.isHoldModifier ? "▼" : nil,
                        color: mapping.isHoldModifier ? .purple : .primary
                    )
                }

                // Long hold
                if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
                    PreviewMappingLabel(
                        text: longHold.hint ?? longHold.displayString,
                        shortcut: longHold.hint != nil ? longHold.displayString : nil,
                        icon: "⏱",
                        color: .orange
                    )
                }

                // Double tap
                if let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty {
                    PreviewMappingLabel(
                        text: doubleTap.hint ?? doubleTap.displayString,
                        shortcut: doubleTap.hint != nil ? doubleTap.displayString : nil,
                        icon: "2×",
                        color: .cyan
                    )
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }
}

struct PreviewMappingLabel: View {
    let text: String
    let shortcut: String?
    let icon: String?
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Text(icon)
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(color)
                    .cornerRadius(2)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color == .primary ? .primary : color)
                .lineLimit(1)

            // Show actual shortcut to the right if there's a hint
            if let shortcut = shortcut {
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Preview Chord Row

struct PreviewChordRow: View {
    @EnvironmentObject var controllerService: ControllerService

    let chord: ChordMapping
    let profile: Profile

    var body: some View {
        HStack(spacing: 12) {
            // Button icons - match main chord list spacing
            HStack(spacing: 4) {
                ForEach(Array(chord.buttons).sorted(by: { $0.category.chordDisplayOrder < $1.category.chordDisplayOrder }), id: \.self) { button in
                    ButtonIconView(button: button, isPressed: false, isDualSense: controllerService.threadSafeIsDualSense)
                }
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // Action with hint + actual shortcut shown inline
            if let systemCommand = chord.systemCommand {
                chordActionLabel(
                    text: chord.hint ?? systemCommand.displayName,
                    shortcut: chord.hint != nil ? systemCommand.displayName : nil,
                    color: .green.opacity(0.9)
                )
            } else if let macroId = chord.macroId,
                      let macro = profile.macros.first(where: { $0.id == macroId }) {
                chordActionLabel(
                    text: chord.hint ?? macro.name,
                    shortcut: chord.hint != nil ? "Macro: \(macro.name)" : nil,
                    color: .purple.opacity(0.9)
                )
            } else {
                chordActionLabel(
                    text: chord.hint ?? chord.actionDisplayString,
                    shortcut: chord.hint != nil ? chord.actionDisplayString : nil,
                    color: .primary
                )
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func chordActionLabel(text: String, shortcut: String?, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)

            if let shortcut = shortcut {
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
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
        List {
            ForEach(chords) { chord in
                ChordRow(
                    chord: chord,
                    isDualSense: isDualSense,
                    onEdit: { onEdit(chord) },
                    onDelete: { onDelete(chord) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                .background(GlassCardBackground())
            }
            .onMove(perform: onMove)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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

            if let systemCommand = chord.systemCommand {
                Text(chord.hint ?? systemCommand.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.green.opacity(0.9))
                    .tooltipIfPresent(chord.hint != nil ? systemCommand.displayName : nil)
            } else if let macroId = chord.macroId,
               let profile = profileManager.activeProfile,
               let macro = profile.macros.first(where: { $0.id == macroId }) {
                Text(chord.hint ?? macro.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.purple.opacity(0.9))
                    .tooltipIfPresent(chord.hint != nil ? macro.name : nil)
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

    private var isDualSenseEdge: Bool {
        controllerService.threadSafeIsDualSenseEdge
    }

    @State private var selectedButtons: Set<ControllerButton> = []
    @State private var keyCode: CGKeyCode?
    @State private var modifiers = ModifierFlags()
    @State private var hint: String = ""
    @State private var showingKeyboard = false
    
    // Macro support
    @State private var mappingType: MappingType = .singleKey
    @State private var selectedMacroId: UUID?

    // System command support
    @State private var systemCommandCategory: SystemCommandCategory = .shell
    @State private var appBundleIdentifier: String = ""
    @State private var appNewWindow: Bool = false
    @State private var shellCommandText: String = ""
    @State private var shellRunInTerminal: Bool = true
    @State private var linkURL: String = ""
    @State private var showingAppPicker = false
    @State private var showingBookmarkPicker = false

    enum MappingType: Int {
        case singleKey = 0
        case macro = 1
        case systemCommand = 2
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

    private var canSave: Bool {
        selectedButtons.count >= 2 &&
        (mappingType != .singleKey || keyCode != nil || modifiers.hasAny) &&
        (mappingType != .macro || selectedMacroId != nil) &&
        (mappingType != .systemCommand || buildChordSystemCommand() != nil)
    }

    private func saveChord() {
        guard canSave else { return }

        let hintValue = hint.isEmpty ? nil : hint
        let finalKeyCode = mappingType == .singleKey ? keyCode : nil
        let finalModifiers = mappingType == .singleKey ? modifiers : ModifierFlags()
        let finalMacroId = mappingType == .macro ? selectedMacroId : nil
        let finalSystemCommand: SystemCommand? = mappingType == .systemCommand ? buildChordSystemCommand() : nil

        if let existingChord = editingChord {
            var updatedChord = existingChord
            updatedChord.buttons = selectedButtons
            updatedChord.keyCode = finalKeyCode
            updatedChord.modifiers = finalModifiers
            updatedChord.macroId = finalMacroId
            updatedChord.systemCommand = finalSystemCommand
            updatedChord.hint = hintValue
            profileManager.updateChord(updatedChord)
        } else {
            let chord = ChordMapping(
                buttons: selectedButtons,
                keyCode: finalKeyCode,
                modifiers: finalModifiers,
                macroId: finalMacroId,
                systemCommand: finalSystemCommand,
                hint: hintValue
            )
            profileManager.addChord(chord)
        }
        dismiss()
    }

    var body: some View {
        ScrollView {
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

                    // Edge Controls (function buttons and paddles)
                    if isDualSenseEdge {
                        VStack(spacing: 8) {
                            Text("EDGE CONTROLS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            // Function buttons row (above touchpad area)
                            HStack(spacing: 40) {
                                toggleButton(.leftFunction)
                                Text("Fn")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                toggleButton(.rightFunction)
                            }

                            // Paddles row (back of controller)
                            HStack(spacing: 40) {
                                toggleButton(.leftPaddle)
                                Text("Paddles")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                toggleButton(.rightPaddle)
                            }
                        }
                        .padding(.top, 20)
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
                        Text("Key").tag(MappingType.singleKey)
                        Text("Macro").tag(MappingType.macro)
                        Text("System").tag(MappingType.systemCommand)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
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
                } else if mappingType == .macro {
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
                } else {
                    // SYSTEM COMMAND SELECTION
                    chordSystemCommandContent
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
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "Save" : "Add") {
                    saveChord()
                }
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
    .onSubmit { saveChord() }
    .frame(width: 850)
        .onAppear {
            if let chord = editingChord {
                selectedButtons = chord.buttons
                keyCode = chord.keyCode
                modifiers = chord.modifiers
                hint = chord.hint ?? ""

                if let systemCommand = chord.systemCommand {
                    mappingType = .systemCommand
                    loadChordSystemCommandState(systemCommand)
                } else if let macroId = chord.macroId {
                    mappingType = .macro
                    selectedMacroId = macroId
                } else {
                    mappingType = .singleKey
                }
            }
        }
    }

    // MARK: - System Command Helpers

    @ViewBuilder
    private var chordSystemCommandContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Category", selection: $systemCommandCategory) {
                ForEach(SystemCommandCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            switch systemCommandCategory {
            case .app:
                AppSelectionButton(bundleId: appBundleIdentifier, showingPicker: $showingAppPicker)
                    .sheet(isPresented: $showingAppPicker) {
                        SystemActionAppPickerSheet(
                            currentBundleIdentifier: appBundleIdentifier.isEmpty ? nil : appBundleIdentifier
                        ) { app in
                            appBundleIdentifier = app.bundleIdentifier
                        }
                    }
                Toggle("Open in new window (Cmd+N)", isOn: $appNewWindow)
                    .font(.caption)
            case .shell:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Command (e.g. say \"Hello\")", text: $shellCommandText)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Toggle("Run silently (no terminal window)", isOn: Binding(
                        get: { !shellRunInTerminal },
                        set: { shellRunInTerminal = !$0 }
                    ))
                        .font(.caption)

                    Text(shellRunInTerminal
                        ? "Opens a terminal window and executes the command"
                        : "Runs silently in the background (no visible output)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if shellRunInTerminal {
                        Divider()
                        TerminalAppPickerRow()
                    }
                }
            case .link:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("URL (e.g. https://google.com)", text: $linkURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Button {
                        showingBookmarkPicker = true
                    } label: {
                        Label("Browse Bookmarks", systemImage: "book")
                            .font(.subheadline)
                    }
                    .sheet(isPresented: $showingBookmarkPicker) {
                        BookmarkPickerSheet { url in
                            linkURL = url
                        }
                    }

                    Text("Opens the URL in your default browser")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func buildChordSystemCommand() -> SystemCommand? {
        switch systemCommandCategory {
        case .app:
            guard !appBundleIdentifier.isEmpty else { return nil }
            return .launchApp(bundleIdentifier: appBundleIdentifier, newWindow: appNewWindow)
        case .shell:
            guard !shellCommandText.isEmpty else { return nil }
            return .shellCommand(command: shellCommandText, inTerminal: shellRunInTerminal)
        case .link:
            guard !linkURL.isEmpty else { return nil }
            return .openLink(url: linkURL)
        }
    }

    private func loadChordSystemCommandState(_ command: SystemCommand) {
        systemCommandCategory = command.category
        switch command {
        case .launchApp(let bundleId, let newWindow):
            appBundleIdentifier = bundleId
            appNewWindow = newWindow
        case .shellCommand(let cmd, let inTerminal):
            shellCommandText = cmd
            shellRunInTerminal = inTerminal
        case .openLink(let url):
            linkURL = url
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
        case .paddle: return 36
        }
    }

    private func buttonHeight(for button: ControllerButton) -> CGFloat {
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return 28
        case .bumper, .trigger: return 22
        case .touchpad: return 24
        case .paddle: return 24
        }
    }
}

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

// MARK: - UUID Identifiable Extension

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

// MARK: - Add Layer Sheet

struct AddLayerSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss

    @State private var layerName: String = ""
    @State private var selectedActivator: ControllerButton? = .leftBumper

    /// Buttons that are already used as layer activators
    private var usedActivators: Set<ControllerButton> {
        Set(profileManager.activeProfile?.layers.compactMap { $0.activatorButton } ?? [])
    }

    /// Available activator buttons (exclude already-used ones)
    private var availableButtons: [ControllerButton] {
        // Good candidates for layer activators: bumpers, triggers, share, view, menu
        var candidates: [ControllerButton] = [
            .leftBumper, .rightBumper, .leftTrigger, .rightTrigger,
            .share, .view, .menu, .xbox,
            .leftThumbstick, .rightThumbstick
        ]
        // Add Edge-specific buttons when Edge controller is connected
        if controllerService.threadSafeIsDualSenseEdge {
            candidates.append(contentsOf: [.leftFunction, .rightFunction, .leftPaddle, .rightPaddle])
        }
        return candidates.filter { !usedActivators.contains($0) }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Layer")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Layer Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("e.g., Combat Mode", text: $layerName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Activator Button (Optional)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Hold this button to activate the layer's mappings")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Activator", selection: $selectedActivator) {
                        Text("None (assign later)").tag(nil as ControllerButton?)
                        ForEach(availableButtons, id: \.self) { button in
                            Text(button.displayName(forDualSense: controllerService.threadSafeIsDualSense))
                                .tag(button as ControllerButton?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.horizontal)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Layer") {
                    guard !layerName.isEmpty else { return }
                    _ = profileManager.createLayer(name: layerName, activatorButton: selectedActivator)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(layerName.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            // Select first available activator
            if let first = availableButtons.first {
                selectedActivator = first
            }
        }
    }
}

// MARK: - Edit Layer Sheet

struct EditLayerSheet: View {
    let layer: Layer

    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss

    @State private var layerName: String = ""
    @State private var selectedActivator: ControllerButton? = .leftBumper

    /// Buttons that are already used as layer activators (excluding current layer)
    private var usedActivators: Set<ControllerButton> {
        Set(profileManager.activeProfile?.layers
            .filter { $0.id != layer.id }
            .compactMap { $0.activatorButton } ?? [])
    }

    /// Available activator buttons (exclude already-used ones, but include current)
    private var availableButtons: [ControllerButton] {
        var candidates: [ControllerButton] = [
            .leftBumper, .rightBumper, .leftTrigger, .rightTrigger,
            .share, .view, .menu, .xbox,
            .leftThumbstick, .rightThumbstick
        ]
        // Add Edge-specific buttons when Edge controller is connected
        if controllerService.threadSafeIsDualSenseEdge {
            candidates.append(contentsOf: [.leftFunction, .rightFunction, .leftPaddle, .rightPaddle])
        }
        return candidates.filter { !usedActivators.contains($0) }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Layer")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Layer Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("Layer name", text: $layerName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Activator Button")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Activator", selection: $selectedActivator) {
                        Text("None (assign later)").tag(nil as ControllerButton?)
                        ForEach(availableButtons, id: \.self) { button in
                            Text(button.displayName(forDualSense: controllerService.threadSafeIsDualSense))
                                .tag(button as ControllerButton?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.horizontal)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    guard !layerName.isEmpty else { return }
                    var updatedLayer = layer
                    updatedLayer.name = layerName
                    updatedLayer.activatorButton = selectedActivator
                    profileManager.updateLayer(updatedLayer)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(layerName.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            layerName = layer.name
            selectedActivator = layer.activatorButton
        }
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
