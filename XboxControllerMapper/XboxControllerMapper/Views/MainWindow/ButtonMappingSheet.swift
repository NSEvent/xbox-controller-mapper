import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Sheet for configuring a button mapping
struct ButtonMappingSheet: View {
    let button: ControllerButton
    @Binding var mapping: KeyMapping?
    var isDualSense: Bool = false

    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var appMonitor: AppMonitor

    @Environment(\.dismiss) private var dismiss

    // Local state for editing
    @State private var keyCode: CGKeyCode?
    @State private var modifiers = ModifierFlags()
    @State private var isHoldModifier = false

    @State private var enableLongHold = false
    @State private var longHoldKeyCode: CGKeyCode?
    @State private var longHoldModifiers = ModifierFlags()
    @State private var longHoldThreshold: Double = 0.5
    @State private var longHoldHint: String = ""

    @State private var enableDoubleTap = false
    @State private var doubleTapKeyCode: CGKeyCode?
    @State private var doubleTapModifiers = ModifierFlags()
    @State private var doubleTapThreshold: Double = 0.4
    @State private var doubleTapHint: String = ""

    @State private var enableRepeat = false
    @State private var repeatRate: Double = 5.0  // Actions per second

    // Track if user manually overrode the hold setting
    @State private var userHasInteractedWithHold = false
    
    // Prevent auto-logic from running during initial load
    @State private var isLoading = true

    // Hint
    @State private var hint: String = ""

    // Keyboard visual state
    @State private var showingKeyboardForPrimary = false
    @State private var showingKeyboardForLongHold = false
    @State private var showingKeyboardForDoubleTap = false

    // Macro support
    @State private var mappingType: MappingType = .singleKey
    @State private var selectedMacroId: UUID?

    // System command support
    @State private var systemCommandCategory: SystemCommandCategory = .shell
    @State private var appBundleIdentifier: String = ""
    @State private var shellCommandText: String = ""
    @State private var shellRunInTerminal: Bool = true
    @State private var linkURL: String = ""

    // Long hold type support
    @State private var longHoldMappingType: MappingType = .singleKey
    @State private var longHoldMacroId: UUID?
    @State private var longHoldSystemCommandCategory: SystemCommandCategory = .shell
    @State private var longHoldAppBundleIdentifier: String = ""
    @State private var longHoldShellCommandText: String = ""
    @State private var longHoldShellRunInTerminal: Bool = true
    @State private var longHoldLinkURL: String = ""

    // Double tap type support
    @State private var doubleTapMappingType: MappingType = .singleKey
    @State private var doubleTapMacroId: UUID?
    @State private var doubleTapSystemCommandCategory: SystemCommandCategory = .shell
    @State private var doubleTapAppBundleIdentifier: String = ""
    @State private var doubleTapShellCommandText: String = ""
    @State private var doubleTapShellRunInTerminal: Bool = true
    @State private var doubleTapLinkURL: String = ""

    enum MappingType: Int {
        case singleKey = 0
        case macro = 1
        case systemCommand = 2
    }

    private var showingAnyKeyboard: Bool {
        showingKeyboardForPrimary || showingKeyboardForLongHold || showingKeyboardForDoubleTap
    }

    /// Check if the primary action is a mouse click - disables double tap/long hold
    private var primaryIsMouseClick: Bool {
        guard let code = keyCode else { return false }
        return KeyCodeMapping.isMouseButton(code)
    }

    /// Check if the primary action is on-screen keyboard - disables double tap/long hold/repeat
    private var primaryIsOnScreenKeyboard: Bool {
        guard let code = keyCode else { return false }
        return KeyCodeMapping.isSpecialAction(code)
    }

    /// Check if the primary action disables advanced features (mouse click or special action)
    private var primaryDisablesAdvancedFeatures: Bool {
        primaryIsMouseClick || primaryIsOnScreenKeyboard
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    primaryMappingSection
                    longHoldSection
                    doubleTapSection
                }
                .padding(20)
            }

            Divider()

            // Footer
            footer
        }
        .frame(width: showingAnyKeyboard ? 750 : 500, height: showingAnyKeyboard ? 700 : 550)
        .animation(.easeInOut(duration: 0.2), value: showingKeyboardForPrimary)
        .animation(.easeInOut(duration: 0.2), value: showingKeyboardForLongHold)
        .animation(.easeInOut(duration: 0.2), value: showingKeyboardForDoubleTap)
        .onAppear {
            loadCurrentMapping()
            // Allow state updates to settle before enabling auto-logic
            DispatchQueue.main.async {
                isLoading = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            ButtonIconView(button: button, isPressed: false, isDualSense: isDualSense)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Configure \(button.displayName(forDualSense: isDualSense))")
                    .font(.headline)

                if let currentMapping = mapping {
                    HStack(spacing: 4) {
                        Text("Current:")
                        
                        if let macroId = currentMapping.macroId,
                           let profile = profileManager.activeProfile,
                           let macro = profile.macros.first(where: { $0.id == macroId }) {
                            Text("Macro: \(macro.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            MappingLabelView(
                                mapping: currentMapping,
                                horizontal: true,
                                font: .caption,
                                foregroundColor: .secondary
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    Text("No mapping configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Primary Mapping Section

    private var primaryMappingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Primary Action")
                    .font(.headline)

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
                    Button(action: { showingKeyboardForPrimary.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: showingKeyboardForPrimary ? "keyboard.chevron.compact.down" : "keyboard")
                            Text(showingKeyboardForPrimary ? "Hide Keyboard" : "Show Keyboard")
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

            VStack(alignment: .leading, spacing: 8) {
                if mappingType == .singleKey {
                    // Current selection display
                    HStack {
                        Text("Selected:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(currentMappingDisplay)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        if keyCode != nil || modifiers.hasAny {
                            Button("Clear") {
                                keyCode = nil
                                modifiers = ModifierFlags()
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    }

                    if showingKeyboardForPrimary {
                        KeyboardVisualView(selectedKeyCode: $keyCode, modifiers: $modifiers)
                    } else {
                        KeyCaptureField(keyCode: $keyCode, modifiers: $modifiers)

                        Text("Click to type a shortcut, or show keyboard to select visually")
                            .font(.caption)
                            .foregroundColor(.secondary)
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

                    // Show hold option if any mapping is configured
                    if keyCode != nil || modifiers.hasAny {
                        Divider()

                        Toggle("Hold action while button is held", isOn: Binding(
                            get: { isHoldModifier },
                            set: { newValue in
                                isHoldModifier = newValue
                                userHasInteractedWithHold = true
                                // Disable repeat and long hold when enabling hold modifier (mutually exclusive)
                                if newValue {
                                    enableRepeat = false
                                    enableLongHold = false
                                    longHoldKeyCode = nil
                                    longHoldModifiers = ModifierFlags()
                                }
                            }
                        ))
                        .font(.caption)
                        .disabled(enableRepeat)

                        Text(holdDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Repeat section (moved inside Primary Action)
                        repeatContent
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
                    systemCommandContent
                }
            }
            .onChange(of: keyCode) { _, newValue in
                guard !isLoading else { return }

                if let code = newValue, KeyCodeMapping.isMouseButton(code) || KeyCodeMapping.isSpecialAction(code) {
                    // Mouse clicks and special actions: auto-enable hold and disable long hold/double tap/repeat
                    if !userHasInteractedWithHold {
                        isHoldModifier = true
                    }
                    // Clear long hold, double tap, and repeat
                    enableLongHold = false
                    enableDoubleTap = false
                    enableRepeat = false
                    longHoldKeyCode = nil
                    longHoldModifiers = ModifierFlags()
                    doubleTapKeyCode = nil
                    doubleTapModifiers = ModifierFlags()
                } else if !userHasInteractedWithHold {
                    if newValue != nil {
                        // Auto-disable hold modifier for regular keys
                        isHoldModifier = false
                    } else if modifiers.hasAny {
                        // Auto-enable hold modifier for modifier-only mappings
                        isHoldModifier = true
                    }
                }
            }
            .onChange(of: modifiers) { _, newValue in
                guard !isLoading else { return }
                guard !userHasInteractedWithHold else { return }

                if keyCode == nil && newValue.hasAny {
                    // Auto-enable hold for modifier-only mappings
                    isHoldModifier = true
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var currentMappingDisplay: String {
        var parts: [String] = []
        if modifiers.command { parts.append("⌘") }
        if modifiers.option { parts.append("⌥") }
        if modifiers.shift { parts.append("⇧") }
        if modifiers.control { parts.append("⌃") }
        if let keyCode = keyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    private var holdDescription: String {
        if let code = keyCode, KeyCodeMapping.isMouseButton(code) {
            return "When enabled, the mouse button stays pressed for dragging"
        } else if keyCode == nil && modifiers.hasAny {
            return "When enabled, the modifier stays pressed while the button is held"
        } else {
            return "When enabled, the key action stays active while the button is held"
        }
    }

    // MARK: - System Command Section

    @ViewBuilder
    private var systemCommandContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category picker
            Picker("Category", selection: $systemCommandCategory) {
                ForEach(SystemCommandCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            // Category-specific content
            switch systemCommandCategory {
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
                }
            case .app:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Bundle Identifier (e.g. com.apple.calculator)", text: $appBundleIdentifier)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)

                        Button("Browse...") { browseForApp(target: .primary) }
                    }

                    if !appBundleIdentifier.isEmpty {
                        appPreviewRow(for: appBundleIdentifier)
                    }
                }
            case .link:
                TextField("URL (e.g. https://google.com)", text: $linkURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }

            // Hint field for system commands
            HStack {
                Text("Hint:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("e.g. Launch Safari, Say Hello...", text: $hint)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }
        }
    }

    private enum BrowseTarget {
        case primary, longHold, doubleTap
    }

    private func browseForApp(target: BrowseTarget = .primary) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                switch target {
                case .primary:
                    appBundleIdentifier = bundleId
                case .longHold:
                    longHoldAppBundleIdentifier = bundleId
                case .doubleTap:
                    doubleTapAppBundleIdentifier = bundleId
                }
            }
        }
    }

    @ViewBuilder
    private func appPreviewRow(for bundleId: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.green)
            }
        } else {
            Text("App not found")
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    /// Builds the SystemCommand from current UI state, or nil if invalid
    private func buildSystemCommand() -> SystemCommand? {
        switch systemCommandCategory {
        case .shell:
            guard !shellCommandText.isEmpty else { return nil }
            return .shellCommand(command: shellCommandText, inTerminal: shellRunInTerminal)
        case .app:
            guard !appBundleIdentifier.isEmpty else { return nil }
            return .launchApp(bundleIdentifier: appBundleIdentifier)
        case .link:
            guard !linkURL.isEmpty else { return nil }
            return .openLink(url: linkURL)
        }
    }

    private func buildLongHoldSystemCommand() -> SystemCommand? {
        switch longHoldSystemCommandCategory {
        case .shell:
            guard !longHoldShellCommandText.isEmpty else { return nil }
            return .shellCommand(command: longHoldShellCommandText, inTerminal: longHoldShellRunInTerminal)
        case .app:
            guard !longHoldAppBundleIdentifier.isEmpty else { return nil }
            return .launchApp(bundleIdentifier: longHoldAppBundleIdentifier)
        case .link:
            guard !longHoldLinkURL.isEmpty else { return nil }
            return .openLink(url: longHoldLinkURL)
        }
    }

    private func buildDoubleTapSystemCommand() -> SystemCommand? {
        switch doubleTapSystemCommandCategory {
        case .shell:
            guard !doubleTapShellCommandText.isEmpty else { return nil }
            return .shellCommand(command: doubleTapShellCommandText, inTerminal: doubleTapShellRunInTerminal)
        case .app:
            guard !doubleTapAppBundleIdentifier.isEmpty else { return nil }
            return .launchApp(bundleIdentifier: doubleTapAppBundleIdentifier)
        case .link:
            guard !doubleTapLinkURL.isEmpty else { return nil }
            return .openLink(url: doubleTapLinkURL)
        }
    }

    // MARK: - Long Hold Section

    /// Whether long hold should be disabled (mouse click, special action, or hold modifier enabled)
    private var longHoldDisabled: Bool {
        primaryDisablesAdvancedFeatures || (mappingType == .singleKey && (isHoldModifier || enableRepeat))
    }

    private var longHoldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Enable Long Hold Action", isOn: $enableLongHold)
                    .font(.headline)
                    .disabled(longHoldDisabled)

                Spacer()

                if enableLongHold && !longHoldDisabled && longHoldMappingType == .singleKey {
                    Button(action: { showingKeyboardForLongHold.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: showingKeyboardForLongHold ? "keyboard.chevron.compact.down" : "keyboard")
                            Text(showingKeyboardForLongHold ? "Hide" : "Show Keyboard")
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

            if primaryDisablesAdvancedFeatures {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Long hold is not available for \(primaryIsMouseClick ? "mouse clicks" : "on-screen keyboard").")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else if mappingType == .singleKey && isHoldModifier {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Long hold is not available when \"Hold action\" is enabled.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else if mappingType == .singleKey && enableRepeat {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Long hold is not available when \"Repeat Action\" is enabled.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else if enableLongHold {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Hold Duration:")
                            .font(.subheadline)

                        Slider(value: $longHoldThreshold, in: 0.2...2.0, step: 0.1)

                        Text("\(longHoldThreshold, specifier: "%.1f")s")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40)
                    }

                    Picker("", selection: $longHoldMappingType) {
                        Text("Key").tag(MappingType.singleKey)
                        Text("Macro").tag(MappingType.macro)
                        Text("System").tag(MappingType.systemCommand)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    if longHoldMappingType == .singleKey {
                        // Current selection display
                        HStack {
                            Text("Long Hold Action:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(longHoldMappingDisplay)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        if showingKeyboardForLongHold {
                            KeyboardVisualView(selectedKeyCode: $longHoldKeyCode, modifiers: $longHoldModifiers)
                        } else {
                            KeyCaptureField(keyCode: $longHoldKeyCode, modifiers: $longHoldModifiers)
                        }
                    } else if longHoldMappingType == .macro {
                        longHoldMacroContent
                    } else {
                        longHoldSystemCommandContent
                    }

                    HStack {
                        Text("Hint:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("e.g. Copy, Paste, Switch App...", text: $longHoldHint)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    private var longHoldMappingDisplay: String {
        var parts: [String] = []
        if longHoldModifiers.command { parts.append("⌘") }
        if longHoldModifiers.option { parts.append("⌥") }
        if longHoldModifiers.shift { parts.append("⇧") }
        if longHoldModifiers.control { parts.append("⌃") }
        if let keyCode = longHoldKeyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    @ViewBuilder
    private var longHoldMacroContent: some View {
        if let profile = profileManager.activeProfile, !profile.macros.isEmpty {
            Picker("Select Macro", selection: $longHoldMacroId) {
                Text("None").tag(nil as UUID?)
                ForEach(profile.macros) { macro in
                    Text(macro.name).tag(macro.id as UUID?)
                }
            }
        } else {
            Text("No macros defined in this profile.")
                .foregroundColor(.secondary)
                .italic()
                .font(.caption)
        }
    }

    @ViewBuilder
    private var longHoldSystemCommandContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Category", selection: $longHoldSystemCommandCategory) {
                ForEach(SystemCommandCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            switch longHoldSystemCommandCategory {
            case .shell:
                TextField("Command", text: $longHoldShellCommandText)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                Toggle("Run silently (no terminal window)", isOn: Binding(
                    get: { !longHoldShellRunInTerminal },
                    set: { longHoldShellRunInTerminal = !$0 }
                ))
                    .font(.caption)
            case .app:
                HStack {
                    TextField("Bundle Identifier", text: $longHoldAppBundleIdentifier)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                    Button("Browse...") { browseForApp(target: .longHold) }
                }
                if !longHoldAppBundleIdentifier.isEmpty {
                    appPreviewRow(for: longHoldAppBundleIdentifier)
                }
            case .link:
                TextField("URL (e.g. https://google.com)", text: $longHoldLinkURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Double Tap Section

    private var doubleTapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Enable Double Tap Action", isOn: $enableDoubleTap)
                    .font(.headline)
                    .disabled(primaryDisablesAdvancedFeatures)

                Spacer()

                if enableDoubleTap && !primaryDisablesAdvancedFeatures && doubleTapMappingType == .singleKey {
                    Button(action: { showingKeyboardForDoubleTap.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: showingKeyboardForDoubleTap ? "keyboard.chevron.compact.down" : "keyboard")
                            Text(showingKeyboardForDoubleTap ? "Hide" : "Show Keyboard")
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

            if primaryDisablesAdvancedFeatures {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text(primaryIsMouseClick
                         ? "Double tap is not available when the primary action is a mouse click. Press the button twice quickly to double-click, or three times for triple-click."
                         : "Double tap is not available when the primary action is the on-screen keyboard.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else if enableDoubleTap {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tap Window:")
                            .font(.subheadline)

                        Slider(value: $doubleTapThreshold, in: 0.2...0.6, step: 0.05)

                        Text("\(doubleTapThreshold, specifier: "%.2f")s")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 45)
                    }

                    Text("Two taps within this time window trigger the double-tap action")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: $doubleTapMappingType) {
                        Text("Key").tag(MappingType.singleKey)
                        Text("Macro").tag(MappingType.macro)
                        Text("System").tag(MappingType.systemCommand)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    if doubleTapMappingType == .singleKey {
                        // Current selection display
                        HStack {
                            Text("Double Tap Action:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(doubleTapMappingDisplay)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        if showingKeyboardForDoubleTap {
                            KeyboardVisualView(selectedKeyCode: $doubleTapKeyCode, modifiers: $doubleTapModifiers)
                        } else {
                            KeyCaptureField(keyCode: $doubleTapKeyCode, modifiers: $doubleTapModifiers)
                        }
                    } else if doubleTapMappingType == .macro {
                        doubleTapMacroContent
                    } else {
                        doubleTapSystemCommandContent
                    }

                    HStack {
                        Text("Hint:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("e.g. Copy, Paste, Switch App...", text: $doubleTapHint)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    private var doubleTapMappingDisplay: String {
        var parts: [String] = []
        if doubleTapModifiers.command { parts.append("⌘") }
        if doubleTapModifiers.option { parts.append("⌥") }
        if doubleTapModifiers.shift { parts.append("⇧") }
        if doubleTapModifiers.control { parts.append("⌃") }
        if let keyCode = doubleTapKeyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    @ViewBuilder
    private var doubleTapMacroContent: some View {
        if let profile = profileManager.activeProfile, !profile.macros.isEmpty {
            Picker("Select Macro", selection: $doubleTapMacroId) {
                Text("None").tag(nil as UUID?)
                ForEach(profile.macros) { macro in
                    Text(macro.name).tag(macro.id as UUID?)
                }
            }
        } else {
            Text("No macros defined in this profile.")
                .foregroundColor(.secondary)
                .italic()
                .font(.caption)
        }
    }

    @ViewBuilder
    private var doubleTapSystemCommandContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Category", selection: $doubleTapSystemCommandCategory) {
                ForEach(SystemCommandCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            switch doubleTapSystemCommandCategory {
            case .shell:
                TextField("Command", text: $doubleTapShellCommandText)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                Toggle("Run silently (no terminal window)", isOn: Binding(
                    get: { !doubleTapShellRunInTerminal },
                    set: { doubleTapShellRunInTerminal = !$0 }
                ))
                    .font(.caption)
            case .app:
                HStack {
                    TextField("Bundle Identifier", text: $doubleTapAppBundleIdentifier)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                    Button("Browse...") { browseForApp(target: .doubleTap) }
                }
                if !doubleTapAppBundleIdentifier.isEmpty {
                    appPreviewRow(for: doubleTapAppBundleIdentifier)
                }
            case .link:
                TextField("URL (e.g. https://google.com)", text: $doubleTapLinkURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Repeat Content

    @ViewBuilder
    private var repeatContent: some View {
        Divider()
            .padding(.vertical, 4)

        Toggle("Repeat Action While Held", isOn: Binding(
            get: { enableRepeat },
            set: { newValue in
                enableRepeat = newValue
                // Disable hold modifier when enabling repeat (mutually exclusive)
                if newValue {
                    isHoldModifier = false
                    enableLongHold = false
                    longHoldKeyCode = nil
                    longHoldModifiers = ModifierFlags()
                    userHasInteractedWithHold = true
                }
            }
        ))
        .font(.caption)
        .disabled(primaryDisablesAdvancedFeatures || isHoldModifier)

        if primaryDisablesAdvancedFeatures {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Repeat is not available for \(primaryIsMouseClick ? "mouse clicks" : "on-screen keyboard").")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if isHoldModifier {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Repeat is not available when \"Hold action\" is enabled.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if enableRepeat {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Repeat Rate:")
                        .font(.caption)

                    Slider(value: $repeatRate, in: 5...50, step: 1)

                    Text("\(Int(repeatRate))/s")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 35)
                }

                Text("The action will be triggered \(Int(repeatRate)) times per second while the button is held")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Clear Mapping") {
                clearMapping()
            }
            .foregroundColor(.red)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                saveMapping()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func loadCurrentMapping() {
        guard let profile = profileManager.activeProfile else { return }

        if let existingMapping = profile.buttonMappings[button] {
            hint = existingMapping.hint ?? ""

            if let systemCommand = existingMapping.systemCommand {
                mappingType = .systemCommand
                loadSystemCommandState(systemCommand)
            } else if let macroId = existingMapping.macroId {
                mappingType = .macro
                selectedMacroId = macroId
            } else {
                mappingType = .singleKey
                keyCode = existingMapping.keyCode
                modifiers = existingMapping.modifiers
                isHoldModifier = existingMapping.isHoldModifier
            }

            // Long hold, double tap, and repeat apply to all primary mapping types
            if let longHold = existingMapping.longHoldMapping {
                enableLongHold = true
                longHoldThreshold = longHold.threshold
                longHoldHint = longHold.hint ?? ""
                if let systemCommand = longHold.systemCommand {
                    longHoldMappingType = .systemCommand
                    loadLongHoldSystemCommandState(systemCommand)
                } else if let macroId = longHold.macroId {
                    longHoldMappingType = .macro
                    longHoldMacroId = macroId
                } else {
                    longHoldMappingType = .singleKey
                    longHoldKeyCode = longHold.keyCode
                    longHoldModifiers = longHold.modifiers
                }
            }

            if let doubleTap = existingMapping.doubleTapMapping {
                enableDoubleTap = true
                doubleTapThreshold = doubleTap.threshold
                doubleTapHint = doubleTap.hint ?? ""
                if let systemCommand = doubleTap.systemCommand {
                    doubleTapMappingType = .systemCommand
                    loadDoubleTapSystemCommandState(systemCommand)
                } else if let macroId = doubleTap.macroId {
                    doubleTapMappingType = .macro
                    doubleTapMacroId = macroId
                } else {
                    doubleTapMappingType = .singleKey
                    doubleTapKeyCode = doubleTap.keyCode
                    doubleTapModifiers = doubleTap.modifiers
                }
            }

            if let repeatConfig = existingMapping.repeatMapping, repeatConfig.enabled {
                enableRepeat = true
                repeatRate = repeatConfig.ratePerSecond
            }
        }
    }

    private func saveMapping() {
        var newMapping: KeyMapping

        if mappingType == .systemCommand {
            guard let command = buildSystemCommand() else { return }
            newMapping = KeyMapping(systemCommand: command, hint: hint.isEmpty ? nil : hint)
        } else if mappingType == .macro {
            guard let macroId = selectedMacroId else { return }
            newMapping = KeyMapping(macroId: macroId, hint: hint.isEmpty ? nil : hint)
        } else {
            newMapping = KeyMapping(
                keyCode: keyCode,
                modifiers: modifiers,
                isHoldModifier: isHoldModifier,
                hint: hint.isEmpty ? nil : hint
            )

            if enableRepeat {
                newMapping.repeatMapping = RepeatMapping(
                    enabled: true,
                    interval: 1.0 / repeatRate
                )
            }
        }

        // Long hold and double tap apply to all primary mapping types
        if enableLongHold && !longHoldDisabled {
            let longHoldValid: Bool
            switch longHoldMappingType {
            case .singleKey:
                longHoldValid = longHoldKeyCode != nil || longHoldModifiers.hasAny
            case .macro:
                longHoldValid = longHoldMacroId != nil
            case .systemCommand:
                longHoldValid = buildLongHoldSystemCommand() != nil
            }
            if longHoldValid {
                newMapping.longHoldMapping = LongHoldMapping(
                    keyCode: longHoldMappingType == .singleKey ? longHoldKeyCode : nil,
                    modifiers: longHoldMappingType == .singleKey ? longHoldModifiers : ModifierFlags(),
                    threshold: longHoldThreshold,
                    macroId: longHoldMappingType == .macro ? longHoldMacroId : nil,
                    systemCommand: longHoldMappingType == .systemCommand ? buildLongHoldSystemCommand() : nil,
                    hint: longHoldHint.isEmpty ? nil : longHoldHint
                )
            }
        }

        if enableDoubleTap && !primaryDisablesAdvancedFeatures {
            let doubleTapValid: Bool
            switch doubleTapMappingType {
            case .singleKey:
                doubleTapValid = doubleTapKeyCode != nil || doubleTapModifiers.hasAny
            case .macro:
                doubleTapValid = doubleTapMacroId != nil
            case .systemCommand:
                doubleTapValid = buildDoubleTapSystemCommand() != nil
            }
            if doubleTapValid {
                newMapping.doubleTapMapping = DoubleTapMapping(
                    keyCode: doubleTapMappingType == .singleKey ? doubleTapKeyCode : nil,
                    modifiers: doubleTapMappingType == .singleKey ? doubleTapModifiers : ModifierFlags(),
                    threshold: doubleTapThreshold,
                    macroId: doubleTapMappingType == .macro ? doubleTapMacroId : nil,
                    systemCommand: doubleTapMappingType == .systemCommand ? buildDoubleTapSystemCommand() : nil,
                    hint: doubleTapHint.isEmpty ? nil : doubleTapHint
                )
            }
        }

        profileManager.setMapping(newMapping, for: button)

        mapping = newMapping
        dismiss()
    }

    private func loadSystemCommandState(_ command: SystemCommand) {
        systemCommandCategory = command.category
        switch command {
        case .launchApp(let bundleId):
            appBundleIdentifier = bundleId
        case .shellCommand(let cmd, let inTerminal):
            shellCommandText = cmd
            shellRunInTerminal = inTerminal
        case .openLink(let url):
            linkURL = url
        }
    }

    private func loadLongHoldSystemCommandState(_ command: SystemCommand) {
        longHoldSystemCommandCategory = command.category
        switch command {
        case .launchApp(let bundleId):
            longHoldAppBundleIdentifier = bundleId
        case .shellCommand(let cmd, let inTerminal):
            longHoldShellCommandText = cmd
            longHoldShellRunInTerminal = inTerminal
        case .openLink(let url):
            longHoldLinkURL = url
        }
    }

    private func loadDoubleTapSystemCommandState(_ command: SystemCommand) {
        doubleTapSystemCommandCategory = command.category
        switch command {
        case .launchApp(let bundleId):
            doubleTapAppBundleIdentifier = bundleId
        case .shellCommand(let cmd, let inTerminal):
            doubleTapShellCommandText = cmd
            doubleTapShellRunInTerminal = inTerminal
        case .openLink(let url):
            doubleTapLinkURL = url
        }
    }

    private func clearMapping() {
        profileManager.removeMapping(for: button)

        mapping = nil
        dismiss()
    }
}

#Preview {
    ButtonMappingSheet(button: .a, mapping: .constant(nil))
        .environmentObject(ProfileManager())
        .environmentObject(AppMonitor())
}
