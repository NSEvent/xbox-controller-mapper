import SwiftUI
import UniformTypeIdentifiers

/// Main window content view
struct ContentView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var appMonitor: AppMonitor
    @EnvironmentObject var mappingEngine: MappingEngine
    @EnvironmentObject var inputLogService: InputLogService
    @EnvironmentObject var usageStatsService: UsageStatsService
    @State private var selectedButton: ControllerButton?
    @State private var configuringButton: ControllerButton?
    @State private var showingChordSheet = false
    @State private var editingChord: ChordMapping?
    @State private var showingSequenceSheet = false
    @State private var editingSequence: SequenceMapping?
    @State private var showingSettingsSheet = false
    @State private var selectedTab = 0
    @State private var lastScale: CGFloat = 1.0 // Track last scale for gesture
    @State private var isMagnifying = false // Track active magnification to prevent tap conflicts
    @State private var selectedLayerId: UUID? = nil // nil = base layer
    @State private var showingAddLayerSheet = false
    @State private var editingLayerId: UUID? = nil
    @State private var isSwapMode: Bool = false
    @State private var swapFirstButton: ControllerButton? = nil
    @State private var showingGestureSheet = false
    @State private var editingGestureType: MotionGestureType?
    @State private var scrollKeyMonitor: Any?
    @AppStorage(MainWindowSection.hiddenDefaultsKey) private var hiddenSectionTags = ""
    @AppStorage(WindowBackgroundDefaults.opacityKey) private var windowBackgroundOpacity: Double = WindowBackgroundDefaults.defaultOpacity
    private var clampedWindowBackgroundOpacity: Double {
        min(max(windowBackgroundOpacity, 0.0), 1.0)
    }
    private var actionFeedbackEnabled: Binding<Bool> {
        Binding(
            get: { ActionFeedbackIndicator.isEnabled },
            set: { ActionFeedbackIndicator.isEnabled = $0 }
        )
    }
    private var streamOverlayEnabled: Binding<Bool> {
        Binding(
            get: { StreamOverlayManager.isEnabled },
            set: { newValue in
                StreamOverlayManager.isEnabled = newValue
                if newValue {
                    StreamOverlayManager.shared.show(
                        controllerService: controllerService,
                        inputLogService: inputLogService
                    )
                } else {
                    StreamOverlayManager.shared.hide()
                }
            }
        )
    }
    var body: some View {
        HSplitView {
            // Sidebar: Profile management
            ProfileSidebar()
                .frame(minWidth: 200, maxWidth: 260)
                .background(Color.black.opacity(0.2)) // Subtle darkening for sidebar

            // Main content
            VStack(spacing: 0) {
                // Toolbar
                ContentToolbar(showingSettingsSheet: $showingSettingsSheet)
                    .zIndex(1) // Keep above content

                // Custom tab bar + content
                CustomTabBar(selectedTab: $selectedTab, tabs: customTabs)

                // Tab content (driven by custom tab bar, no native TabView)
                Group {
                    switch selectedTab {
                    case 0:
                        ButtonMappingsTab(
                            selectedButton: $selectedButton,
                            configuringButton: $configuringButton,
                            selectedLayerId: $selectedLayerId,
                            isSwapMode: $isSwapMode,
                            swapFirstButton: $swapFirstButton,
                            showingAddLayerSheet: $showingAddLayerSheet,
                            editingLayerId: $editingLayerId,
                            editingChord: $editingChord,
                            editingSequence: $editingSequence,
                            isMagnifying: $isMagnifying,
                            actionFeedbackEnabled: actionFeedbackEnabled,
                            streamOverlayEnabled: streamOverlayEnabled
                        )
                    case 1:
                        ChordsTab(
                            showingChordSheet: $showingChordSheet,
                            editingChord: $editingChord
                        )
                    case 9:
                        SequencesTab(
                            showingSequenceSheet: $showingSequenceSheet,
                            editingSequence: $editingSequence
                        )
                    case 11:
                        GesturesTab(editingGestureType: $editingGestureType)
                    case 7:
                        MacroListView()
                            .scrollContentBackground(.hidden)
                    case 10:
                        ScriptListView()
                            .scrollContentBackground(.hidden)
                    case 12:
                        CommandWheelSettingsView()
                            .scrollContentBackground(.hidden)
                    case 14:
                        InputSettingsView()
                            .scrollContentBackground(.hidden)
                    case 2:
                        JoystickSettingsView()
                            .scrollContentBackground(.hidden)
                    case 4:
                        TouchpadSettingsView()
                            .scrollContentBackground(.hidden)
                    case 5:
                        LEDSettingsView()
                            .scrollContentBackground(.hidden)
                    case 6:
                        MicrophoneSettingsView()
                            .scrollContentBackground(.hidden)
                    case 3:
                        OnScreenKeyboardSettingsView()
                            .scrollContentBackground(.hidden)
                    case 8:
                        StatsView()
                    case 13:
                        HistoryView()
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        // Global Glass Background
        //
        // NSVisualEffectView with `.behindWindow` blending samples desktop/app
        // content behind the window. To let the user dampen how much of that
        // bleeds through, layer a dark tint ON TOP of the visual effect — its
        // opacity is user-configurable. 0.0 = pure liquid glass, 1.0 = fully
        // opaque dark background.
        .background(
            ZStack {
                GlassVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(white: 0.2).opacity(clampedWindowBackgroundOpacity)
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
                    set: { _ in } // Read-only: ButtonMappingSheet saves directly via ProfileManager (see saveMapping())
                ),
					isDualSense: controllerService.threadSafeIsPlayStation,
					isNintendo: controllerService.threadSafeIsNintendo,
					isSteamController: controllerService.threadSafeIsSteamController,
					isAppleTVRemote: controllerService.threadSafeIsAppleTVRemote,
					selectedLayerId: selectedLayerId
				)
        }
        .sheet(isPresented: $showingChordSheet) {
            ChordMappingSheet()
        }
        .sheet(item: $editingChord) { chord in
            ChordMappingSheet(editingChord: chord)
        }
        .sheet(isPresented: $showingSequenceSheet) {
            SequenceMappingSheet()
        }
        .sheet(item: $editingSequence) { sequence in
            SequenceMappingSheet(editingSequence: sequence)
        }
        .sheet(item: $editingGestureType) { gestureType in
            GestureMappingSheet(
                gestureType: gestureType,
                existingMapping: profileManager.gestureMapping(for: gestureType)
            )
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsSheet()
        }
        // Add keyboard shortcuts for scaling
        .background(
            Button("Zoom In") { profileManager.setUiScale(min(profileManager.uiScale + 0.1, 2.0)) }
                .keyboardShortcut("+", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        )
        .background(
            Button("Zoom Out") { profileManager.setUiScale(max(profileManager.uiScale - 0.1, 0.5)) }
                .keyboardShortcut("-", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        )
        .background(
            Button("Reset Zoom") { profileManager.setUiScale(1.0) }
                .keyboardShortcut("0", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        )
        .background(
            Button("Previous Tab") { switchTab(direction: -1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        )
        .background(
            Button("Next Tab") { switchTab(direction: 1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        )
        .background(
            Button("Previous Tab Alt") { switchTab(direction: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .hidden()
                .accessibilityHidden(true)
        )
        .background(
            Button("Next Tab Alt") { switchTab(direction: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .hidden()
                .accessibilityHidden(true)
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
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        isMagnifying = false
                    }
                }
        )
        .onAppear { installScrollKeyMonitor() }
        .onAppear { selectFirstVisibleTabIfNeeded() }
        .onChange(of: hiddenSectionTags) { _, _ in
            selectFirstVisibleTabIfNeeded()
        }
        .onChange(of: controllerService.threadSafeIsPlayStation) { _, _ in
            selectFirstVisibleTabIfNeeded()
        }
        .onChange(of: controllerService.threadSafeIsDualSense) { _, _ in
            selectFirstVisibleTabIfNeeded()
        }
			.onChange(of: controllerService.threadSafeIsSteamController) { _, _ in
				selectFirstVisibleTabIfNeeded()
			}
			.onChange(of: controllerService.threadSafeIsAppleTVRemote) { _, _ in
				selectFirstVisibleTabIfNeeded()
			}
			.onChange(of: controllerService.threadSafeHasMotion) { _, _ in
            selectFirstVisibleTabIfNeeded()
        }
        .onDisappear {
            if let monitor = scrollKeyMonitor {
                NSEvent.removeMonitor(monitor)
                scrollKeyMonitor = nil
            }
        }
    }

    // MARK: - Tab Navigation

    /// Tab definitions for the custom tab bar.
    private var customTabs: [CustomTabItem] {
        let hiddenSections = MainWindowSection.hiddenSections(from: hiddenSectionTags)
        return MainWindowSection.visibleSections(
            hiddenSections: hiddenSections,
            isPlayStation: controllerService.threadSafeIsPlayStation,
            isDualSense: controllerService.threadSafeIsDualSense,
            isSteamController: controllerService.threadSafeIsSteamController,
			isAppleTVRemote: controllerService.threadSafeIsAppleTVRemote,
            hasMotion: controllerService.threadSafeHasMotion
        )
        .map(\.tabItem)
    }

    /// Ordered list of visible tab tags matching the TabView order.
    private var orderedTabTags: [Int] {
        customTabs.map(\.tag)
    }

    private func switchTab(direction: Int) {
        let tags = orderedTabTags
        guard let currentIndex = tags.firstIndex(of: selectedTab) else {
            selectFirstVisibleTabIfNeeded()
            return
        }
        let nextIndex = (currentIndex + direction + tags.count) % tags.count
        selectedTab = tags[nextIndex]
    }

    private func selectFirstVisibleTabIfNeeded() {
        guard !orderedTabTags.contains(selectedTab),
              let firstVisibleTag = orderedTabTags.first else {
            return
        }
        selectedTab = firstVisibleTag
    }

    // MARK: - Scroll Key Navigation (Home/End/PageUp/PageDown)

    private func installScrollKeyMonitor() {
        scrollKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't intercept when text is being edited or keys are being captured
            if let firstResponder = NSApp.keyWindow?.firstResponder,
               firstResponder is NSTextView || firstResponder is KeyCaptureNSView {
                return event
            }

            switch event.keyCode {
            case KeyCodeMapping.home:
                Self.scrollToEdge(top: true)
                return nil
            case KeyCodeMapping.end:
                Self.scrollToEdge(top: false)
                return nil
            case KeyCodeMapping.pageUp:
                Self.scrollByPage(up: true)
                return nil
            case KeyCodeMapping.pageDown:
                Self.scrollByPage(up: false)
                return nil
            default:
                return event
            }
        }
    }

    private static func scrollToEdge(top: Bool) {
        guard let scrollView = findMainScrollView() else { return }
        let clipView = scrollView.contentView

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            if top {
                clipView.scroll(to: .zero)
            } else {
                let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clipView.bounds.height)
                clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: maxY))
            }
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    private static func scrollByPage(up: Bool) {
        guard let scrollView = findMainScrollView() else { return }
        let clipView = scrollView.contentView
        let pageHeight = clipView.bounds.height * 0.9

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            var newOrigin = clipView.bounds.origin
            if up {
                newOrigin.y = max(0, newOrigin.y - pageHeight)
            } else {
                let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clipView.bounds.height)
                newOrigin.y = min(maxY, newOrigin.y + pageHeight)
            }
            clipView.scroll(to: newOrigin)
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    /// Finds the largest visible, scrollable NSScrollView in the key window.
    private static func findMainScrollView() -> NSScrollView? {
        guard let contentView = NSApp.keyWindow?.contentView else { return nil }
        var best: NSScrollView?
        var bestArea: CGFloat = 0

        func search(_ view: NSView) {
            if let sv = view as? NSScrollView,
               !sv.isHidden,
               sv.visibleRect.width > 100, sv.visibleRect.height > 100,
               let docView = sv.documentView,
               docView.frame.height > sv.contentView.bounds.height + 1 {
                let area = sv.visibleRect.width * sv.visibleRect.height
                if area > bestArea {
                    best = sv
                    bestArea = area
                }
            }
            for child in view.subviews {
                search(child)
            }
        }

        search(contentView)
        return best
    }
}

// MARK: - Mapping Active Toggle

struct MappingActiveToggle: View {
    @Binding var isEnabled: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(isEnabled ? "MAPPING ACTIVE" : "DISABLED")
                .font(.caption.bold())
                .foregroundColor(isEnabled ? .accentColor : .secondary)

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isEnabled.toggle()
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mapping")
        .accessibilityValue(isEnabled ? "Active" : "Disabled")
        .accessibilityAddTraits(.isToggle)
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

// MARK: - Glass Aesthetic Components

enum WindowBackgroundDefaults {
    static let opacityKey = "windowBackgroundOpacity"
    static let defaultOpacity: Double = 0.6
}

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
    var isMuted: Bool = false
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            if isActive {
                Color.accentColor.opacity(0.2)
            } else if isHovered {
                Color.accentColor.opacity(0.08)
            } else if isMuted {
                Color.black.opacity(0.16)
            } else {
                Color.black.opacity(0.4)
            }

            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderColor, lineWidth: isActive ? 1.5 : 1)
        }
        .cornerRadius(cornerRadius)
        .shadow(
            color: isActive ? Color.accentColor.opacity(0.3) : Color.black.opacity(isMuted ? 0.08 : 0.2),
            radius: isActive ? 8 : (isMuted ? 1 : 4)
        )
    }

    private var borderColor: Color {
        if isActive { return Color.accentColor.opacity(0.8) }
        if isHovered { return Color.white.opacity(0.3) }
        if isMuted { return Color.white.opacity(0.06) }
        return Color.white.opacity(0.1)
    }
}

// MARK: - UUID Identifiable Extension

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
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
        .environmentObject(AppleTVRemoteMicBridge())
}

// MARK: - Main Window Sections

enum MainWindowSection: Int, CaseIterable, Identifiable {
    case buttons = 0
    case chords = 1
    case joysticks = 2
    case keyboard = 3
    case touchpad = 4
    case leds = 5
    case microphone = 6
    case macros = 7
    case stats = 8
    case sequences = 9
    case scripts = 10
    case gestures = 11
    case wheel = 12
    case history = 13
    case input = 14

    static let hiddenDefaultsKey = "hiddenMainWindowSectionTags"

    static let displayOrder: [MainWindowSection] = [
        .buttons,
        .chords,
        .sequences,
        .gestures,
        .macros,
        .scripts,
        .wheel,
        .input,
        .joysticks,
        .touchpad,
        .leds,
        .microphone,
        .keyboard,
        .stats,
        .history
    ]

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .buttons: return "Buttons"
        case .chords: return "Chords"
        case .joysticks: return "Joysticks"
        case .keyboard: return "Keyboard"
        case .touchpad: return "Touchpad"
        case .leds: return "LEDs"
        case .microphone: return "Microphone"
        case .macros: return "Macros"
        case .stats: return "Stats"
        case .sequences: return "Sequences"
        case .scripts: return "Scripts"
        case .gestures: return "Gestures"
        case .wheel: return "Wheel"
        case .history: return "History"
        case .input: return "Input"
        }
    }

    var isGlobal: Bool {
        switch self {
        case .keyboard, .stats, .history:
            return true
        default:
            return false
        }
    }

    var navGroup: MainWindowNavGroup {
        switch self {
        case .buttons, .chords, .sequences, .gestures:
            return .map
        case .macros, .scripts, .wheel, .keyboard:
            return .automate
        case .input, .joysticks, .touchpad, .leds, .microphone:
            return .hardware
        case .stats, .history:
            return .activity
        }
    }

    var systemImage: String {
        switch self {
        case .buttons: return "gamecontroller.fill"
        case .chords: return "link"
        case .sequences: return "point.3.connected.trianglepath.dotted"
        case .gestures: return "gyroscope"
        case .macros: return "play.rectangle.on.rectangle"
        case .scripts: return "curlybraces"
        case .wheel: return "circle.grid.cross"
        case .input: return "speedometer"
        case .keyboard: return "keyboard"
        case .joysticks: return "circle.circle"
        case .touchpad: return "rectangle.and.hand.point.up.left"
        case .leds: return "lightbulb.fill"
        case .microphone: return "mic.fill"
        case .stats: return "chart.bar.xaxis"
        case .history: return "clock.arrow.circlepath"
        }
    }

    var tabItem: CustomTabItem {
        CustomTabItem(
            tag: rawValue,
            label: label,
            group: navGroup,
            systemImage: systemImage,
            isGlobal: isGlobal
        )
    }

    func isAvailable(
        isPlayStation: Bool,
        isDualSense: Bool,
        isSteamController: Bool,
		isAppleTVRemote: Bool,
        hasMotion: Bool
    ) -> Bool {
        switch self {
        case .touchpad:
			return isPlayStation || isSteamController || isAppleTVRemote
        case .leds:
            return isPlayStation
        case .gestures:
            return hasMotion
        case .microphone:
            return isDualSense || isAppleTVRemote
        default:
            return true
        }
    }

    static func hiddenSections(from rawValue: String) -> Set<MainWindowSection> {
        Set(rawValue
            .split(separator: ",")
            .compactMap { Int(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .compactMap(MainWindowSection.init(rawValue:))
        )
    }

    static func encodedHiddenSections(_ sections: Set<MainWindowSection>) -> String {
        sections
            .map(\.rawValue)
            .sorted()
            .map { String($0) }
            .joined(separator: ",")
    }

    static func visibleSections(
        hiddenSections: Set<MainWindowSection>,
        isPlayStation: Bool,
        isDualSense: Bool,
        isSteamController: Bool,
		isAppleTVRemote: Bool,
        hasMotion: Bool
    ) -> [MainWindowSection] {
        displayOrder.filter { section in
            section.isAvailable(
                isPlayStation: isPlayStation,
                isDualSense: isDualSense,
                isSteamController: isSteamController,
				isAppleTVRemote: isAppleTVRemote,
                hasMotion: hasMotion
            )
                && !hiddenSections.contains(section)
        }
    }
}

// MARK: - Custom Tab Bar

enum MainWindowNavGroup: String, CaseIterable, Identifiable {
    case map = "Map"
    case automate = "Automate"
    case hardware = "Hardware"
    case activity = "Activity"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .map: return "slider.horizontal.3"
        case .automate: return "bolt.fill"
        case .hardware: return "switch.2"
        case .activity: return "waveform.path.ecg"
        }
    }
}

struct CustomTabItem: Identifiable {
    let tag: Int
    let label: String
    let group: MainWindowNavGroup
    let systemImage: String
    var isGlobal: Bool = false
    var id: Int { tag }
}

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    let tabs: [CustomTabItem]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ForEach(availableGroups) { group in
                    groupButton(group)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(tabsForActiveGroup) { tab in
                    tabButton(tab)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .background(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.08))
    }

    private var activeGroup: MainWindowNavGroup? {
        tabs.first(where: { $0.tag == selectedTab })?.group ?? tabs.first?.group
    }

    private var availableGroups: [MainWindowNavGroup] {
        MainWindowNavGroup.allCases.filter { group in
            tabs.contains { $0.group == group }
        }
    }

    private var tabsForActiveGroup: [CustomTabItem] {
        guard let activeGroup else { return [] }
        return tabs.filter { $0.group == activeGroup }
    }

    @ViewBuilder
    private func groupButton(_ group: MainWindowNavGroup) -> some View {
        let isSelected = activeGroup == group
        let count = tabs.filter { $0.group == group }.count

        Button {
            guard let firstTab = tabs.first(where: { $0.group == group }) else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedTab = firstTab.tag
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: group.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 15)
                Text(group.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .white.opacity(0.45))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(isSelected ? 0.16 : 0.08))
                    .clipShape(Capsule())
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.54))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.11) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.12) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabButton(_ tab: CustomTabItem) -> some View {
        let isSelected = selectedTab == tab.tag

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab.tag
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                Text(tab.label)
            }
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor.opacity(tab.isGlobal ? 0.28 : 0.62))
                        }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
