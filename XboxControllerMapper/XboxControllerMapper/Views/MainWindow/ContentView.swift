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

                // Tab content
                TabView(selection: $selectedTab) {
                    // Controller Visual
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
                    .tabItem { Text("Buttons") }
                    .tag(0)

                    // Chords
                    ChordsTab(
                        showingChordSheet: $showingChordSheet,
                        editingChord: $editingChord
                    )
                    .tabItem { Text("Chords") }
                    .tag(1)

                    // Sequences
                    SequencesTab(
                        showingSequenceSheet: $showingSequenceSheet,
                        editingSequence: $editingSequence
                    )
                    .tabItem { Text("Sequences") }
                    .tag(9)

                    // Gestures (only shown for DualSense - requires gyroscope)
                    if controllerService.threadSafeIsDualSense {
                        GesturesTab(editingGestureType: $editingGestureType)
                            .tabItem { Text("Gestures") }
                            .tag(11)
                    }

                    // Macros Tab
                    MacroListView()
                        .scrollContentBackground(.hidden)
                        .tabItem { Text("Macros") }
                        .tag(7)

                    // Scripts Tab
                    ScriptListView()
                        .scrollContentBackground(.hidden)
                        .tabItem { Text("Scripts") }
                        .tag(10)

                    // On-Screen Keyboard Settings
                    OnScreenKeyboardSettingsView()
                        .scrollContentBackground(.hidden)
                        .tabItem { Text("Keyboard") }
                        .tag(3)

                    // Joystick Settings
                    JoystickSettingsView()
                        .scrollContentBackground(.hidden)
                        .tabItem { Text("Joysticks") }
                        .tag(2)

                    // Touchpad Settings (only shown when controller has touchpad - DualSense/DualShock)
                    if controllerService.threadSafeIsPlayStation {
                        TouchpadSettingsView()
                            .scrollContentBackground(.hidden)
                            .tabItem { Text("Touchpad") }
                            .tag(4)
                    }

                    // LED Settings (only shown for DualSense - DualShock LED control not supported)
                    if controllerService.threadSafeIsDualSense {
                        LEDSettingsView()
                            .scrollContentBackground(.hidden)
                            .tabItem { Text("LEDs") }
                            .tag(5)
                    }

                    // Microphone Settings (only shown for DualSense)
                    if controllerService.threadSafeIsDualSense {
                        MicrophoneSettingsView()
                            .scrollContentBackground(.hidden)
                            .tabItem { Text("Microphone") }
                            .tag(6)
                    }

                    // Stats
                    StatsView()
                        .tabItem { Text("Stats") }
                        .tag(8)
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
                    set: { _ in } // Read-only: ButtonMappingSheet saves directly via ProfileManager (see saveMapping())
                ),
                isDualSense: controllerService.threadSafeIsPlayStation,
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isMagnifying = false
                    }
                }
        )
        .onAppear { installScrollKeyMonitor() }
        .onDisappear {
            if let monitor = scrollKeyMonitor {
                NSEvent.removeMonitor(monitor)
                scrollKeyMonitor = nil
            }
        }
    }

    // MARK: - Tab Navigation

    /// Ordered list of visible tab tags matching the TabView order.
    private var orderedTabTags: [Int] {
        var tags = [0, 1, 9]
        if controllerService.threadSafeIsDualSense {
            tags.append(11)
        }
        tags.append(contentsOf: [7, 10, 3, 2])
        if controllerService.threadSafeIsPlayStation {
            tags.append(4)
        }
        if controllerService.threadSafeIsDualSense {
            tags.append(5)
            tags.append(6)
        }
        tags.append(8)
        return tags
    }

    private func switchTab(direction: Int) {
        let tags = orderedTabTags
        guard let currentIndex = tags.firstIndex(of: selectedTab) else { return }
        let nextIndex = (currentIndex + direction + tags.count) % tags.count
        selectedTab = tags[nextIndex]
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
            } else if isHovered {
                Color.accentColor.opacity(0.08)
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
}
