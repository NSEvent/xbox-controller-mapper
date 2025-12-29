import SwiftUI

/// Sheet for configuring a button mapping
struct ButtonMappingSheet: View {
    let button: ControllerButton
    @Binding var mapping: KeyMapping?

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

    @State private var enableDoubleTap = false
    @State private var doubleTapKeyCode: CGKeyCode?
    @State private var doubleTapModifiers = ModifierFlags()
    @State private var doubleTapThreshold: Double = 0.3

    // Track if user manually overrode the hold setting
    @State private var userHasInteractedWithHold = false
    
    // Prevent auto-logic from running during initial load
    @State private var isLoading = true

    // App override state
    @State private var showingAppPicker = false
    @State private var appOverrides: [(bundleId: String, mapping: KeyMapping)] = []

    // Keyboard visual state
    @State private var showingKeyboardForPrimary = false
    @State private var showingKeyboardForLongHold = false
    @State private var showingKeyboardForDoubleTap = false

    private var showingAnyKeyboard: Bool {
        showingKeyboardForPrimary || showingKeyboardForLongHold || showingKeyboardForDoubleTap
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
                    appOverridesSection
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Configure \(button.displayName)")
                    .font(.headline)

                if let currentMapping = mapping {
                    HStack(spacing: 4) {
                        Text("Current:")
                        MappingLabelView(
                            mapping: currentMapping,
                            horizontal: true,
                            font: .caption,
                            foregroundColor: .secondary
                        )
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

                Button(action: { showingKeyboardForPrimary.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: showingKeyboardForPrimary ? "keyboard.chevron.compact.down" : "keyboard")
                        Text(showingKeyboardForPrimary ? "Hide Keyboard" : "Show Keyboard")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
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

                // Show hold option if any mapping is configured
                if keyCode != nil || modifiers.hasAny {
                    Divider()

                    Toggle("Hold action while button is held", isOn: Binding(
                        get: { isHoldModifier },
                        set: { newValue in
                            isHoldModifier = newValue
                            userHasInteractedWithHold = true
                        }
                    ))
                    .font(.caption)

                    Text(holdDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: keyCode) { _, newValue in
                guard !isLoading else { return }
                guard !userHasInteractedWithHold else { return }
                
                if let code = newValue {
                    if KeyCodeMapping.isMouseButton(code) {
                        // Auto-enable hold for mouse clicks (useful for dragging)
                        isHoldModifier = true
                    } else {
                        // Auto-disable hold modifier for regular keys
                        isHoldModifier = false
                    }
                } else if modifiers.hasAny {
                    // Auto-enable hold modifier for modifier-only mappings
                    isHoldModifier = true
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

    // MARK: - Long Hold Section

    private var longHoldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Enable Long Hold Action", isOn: $enableLongHold)
                    .font(.headline)

                Spacer()

                if enableLongHold {
                    Button(action: { showingKeyboardForLongHold.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: showingKeyboardForLongHold ? "keyboard.chevron.compact.down" : "keyboard")
                            Text(showingKeyboardForLongHold ? "Hide" : "Show Keyboard")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            if enableLongHold {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Hold Duration:")
                            .font(.subheadline)

                        Slider(value: $longHoldThreshold, in: 0.3...2.0, step: 0.1)

                        Text("\(longHoldThreshold, specifier: "%.1f")s")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40)
                    }

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

    // MARK: - Double Tap Section

    private var doubleTapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Enable Double Tap Action", isOn: $enableDoubleTap)
                    .font(.headline)

                Spacer()

                if enableDoubleTap {
                    Button(action: { showingKeyboardForDoubleTap.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: showingKeyboardForDoubleTap ? "keyboard.chevron.compact.down" : "keyboard")
                            Text(showingKeyboardForDoubleTap ? "Hide" : "Show Keyboard")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            if enableDoubleTap {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tap Window:")
                            .font(.subheadline)

                        Slider(value: $doubleTapThreshold, in: 0.15...0.6, step: 0.05)

                        Text("\(doubleTapThreshold, specifier: "%.2f")s")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 45)
                    }

                    Text("Two taps within this time window trigger the double-tap action")
                        .font(.caption)
                        .foregroundColor(.secondary)

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

    // MARK: - App Overrides Section

    private var appOverridesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("App-Specific Overrides")
                    .font(.headline)

                Spacer()

                Button(action: { showingAppPicker = true }) {
                    Label("Add App", systemImage: "plus")
                        .font(.caption)
                }
            }

            if appOverrides.isEmpty {
                Text("No app-specific overrides configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
            } else {
                ForEach(appOverrides.indices, id: \.self) { index in
                    AppOverrideRow(
                        bundleId: appOverrides[index].bundleId,
                        mapping: appOverrides[index].mapping,
                        onRemove: {
                            appOverrides.remove(at: index)
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet { bundleId in
                // Add new override with empty mapping
                appOverrides.append((bundleId: bundleId, mapping: KeyMapping()))
            }
            .environmentObject(appMonitor)
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
            keyCode = existingMapping.keyCode
            modifiers = existingMapping.modifiers
            isHoldModifier = existingMapping.isHoldModifier

            if let longHold = existingMapping.longHoldMapping {
                enableLongHold = true
                longHoldKeyCode = longHold.keyCode
                longHoldModifiers = longHold.modifiers
                longHoldThreshold = longHold.threshold
            }

            if let doubleTap = existingMapping.doubleTapMapping {
                enableDoubleTap = true
                doubleTapKeyCode = doubleTap.keyCode
                doubleTapModifiers = doubleTap.modifiers
                doubleTapThreshold = doubleTap.threshold
            }
        }

        // Load app overrides
        for (bundleId, mappings) in profile.appOverrides {
            if let overrideMapping = mappings[button] {
                appOverrides.append((bundleId: bundleId, mapping: overrideMapping))
            }
        }
    }

    private func saveMapping() {
        var newMapping = KeyMapping(
            keyCode: keyCode,
            modifiers: modifiers,
            isHoldModifier: isHoldModifier
        )

        if enableLongHold && (longHoldKeyCode != nil || longHoldModifiers.hasAny) {
            newMapping.longHoldMapping = LongHoldMapping(
                keyCode: longHoldKeyCode,
                modifiers: longHoldModifiers,
                threshold: longHoldThreshold
            )
        }

        if enableDoubleTap && (doubleTapKeyCode != nil || doubleTapModifiers.hasAny) {
            newMapping.doubleTapMapping = DoubleTapMapping(
                keyCode: doubleTapKeyCode,
                modifiers: doubleTapModifiers,
                threshold: doubleTapThreshold
            )
        }

        profileManager.setMapping(newMapping, for: button)

        // Save app overrides
        for override in appOverrides {
            profileManager.setAppOverride(override.mapping, for: button, appBundleId: override.bundleId)
        }

        mapping = newMapping
        dismiss()
    }

    private func clearMapping() {
        profileManager.removeMapping(for: button)

        // Remove app overrides for this button
        for override in appOverrides {
            profileManager.removeAppOverride(for: button, appBundleId: override.bundleId)
        }

        mapping = nil
        dismiss()
    }
}

// MARK: - App Override Row

struct AppOverrideRow: View {
    let bundleId: String
    let mapping: KeyMapping
    var onRemove: () -> Void

    @EnvironmentObject var appMonitor: AppMonitor

    var body: some View {
        HStack {
            if let appInfo = appMonitor.appInfo(for: bundleId) {
                if let icon = appInfo.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text(appInfo.name)
                    .font(.caption)
            } else {
                Text(bundleId)
                    .font(.caption)
            }

            Spacer()

            MappingLabelView(
                mapping: mapping,
                horizontal: true,
                font: .caption,
                foregroundColor: .secondary
            )

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - App Picker Sheet

struct AppPickerSheet: View {
    var onSelect: (String) -> Void

    @EnvironmentObject var appMonitor: AppMonitor
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    var filteredApps: [AppInfo] {
        let apps = appMonitor.installedApplications
        if searchText.isEmpty {
            return apps
        }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Application")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(filteredApps) { app in
                Button(action: {
                    onSelect(app.bundleIdentifier)
                    dismiss()
                }) {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                        }
                        Text(app.name)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 350, height: 400)
    }
}

#Preview {
    ButtonMappingSheet(button: .a, mapping: .constant(nil))
        .environmentObject(ProfileManager())
        .environmentObject(AppMonitor())
}
