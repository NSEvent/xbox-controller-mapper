import SwiftUI
import AppKit

/// A searchable app picker sheet for selecting a single app (used in system action configuration)
struct SystemActionAppPickerSheet: View {
    let currentBundleIdentifier: String?
    let onSelect: (AppInfo) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var cachedInstalledApps: [AppInfo] = []

    private var filteredApps: [AppInfo] {
        cachedInstalledApps.filter { app in
            searchText.isEmpty ||
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select App")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Search field with keyboard navigation
            NavigableSearchField(
                text: $searchText,
                placeholder: "Search apps...",
                itemCount: filteredApps.count,
                selectedIndex: $selectedIndex,
                onSelect: {
                    selectApp(at: selectedIndex)
                }
            )
            .padding()

            Divider()

            // App list
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(filteredApps.enumerated()), id: \.element.id) { index, app in
                        let isCurrent = app.bundleIdentifier == currentBundleIdentifier
                        let isHighlighted = index == selectedIndex

                        Button {
                            selectApp(at: index)
                        } label: {
                            HStack(spacing: 12) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                } else {
                                    Image(systemName: "app.fill")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                }

                                Text(app.name)

                                Spacer()

                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(isHighlighted ? .white : .green)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(isHighlighted ? Color.accentColor : Color.clear)
                            .foregroundColor(isHighlighted ? .white : .primary)
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .onChange(of: searchText) { _, _ in
                    selectedIndex = 0
                    proxy.scrollTo(0, anchor: .top)
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .onAppear { loadInstalledApps() }
        .onDisappear {
            searchText = ""
            selectedIndex = 0
        }
    }

    private func selectApp(at index: Int) {
        let apps = filteredApps
        guard index >= 0 && index < apps.count else { return }
        onSelect(apps[index])
        dismiss()
    }

    private func loadInstalledApps() {
        guard cachedInstalledApps.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = AppMonitor().installedApplications
            DispatchQueue.main.async {
                cachedInstalledApps = apps
            }
        }
    }
}

/// A button that shows the currently selected app or a "Select App..." placeholder
struct AppSelectionButton: View {
    let bundleId: String
    @Binding var showingPicker: Bool

    var body: some View {
        Button { showingPicker = true } label: {
            HStack(spacing: 8) {
                if !bundleId.isEmpty,
                   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.subheadline)
                        .fontWeight(.medium)
                } else {
                    Image(systemName: "app.badge.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Select App...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

/// Terminal app picker + automation permission status row
struct TerminalAppPickerRow: View {
    @EnvironmentObject var profileManager: ProfileManager

    @State private var automationPermissionGranted = false
    @State private var isUsingCustomTerminal = false
    @State private var customTerminalApp = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Terminal app picker
            Picker("Terminal App", selection: Binding(
                get: {
                    let current = profileManager.onScreenKeyboardSettings.defaultTerminalApp
                    if OnScreenKeyboardSettings.terminalOptions.contains(current) {
                        return current
                    }
                    return "Other"
                },
                set: { newValue in
                    if newValue == "Other" {
                        isUsingCustomTerminal = true
                    } else {
                        isUsingCustomTerminal = false
                        profileManager.setDefaultTerminalApp(newValue)
                    }
                }
            )) {
                ForEach(OnScreenKeyboardSettings.terminalOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
                Divider()
                Text("Other...").tag("Other")
            }
            .pickerStyle(.menu)

            if isUsingCustomTerminal {
                HStack {
                    TextField("App name", text: $customTerminalApp)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .onSubmit {
                            if !customTerminalApp.isEmpty {
                                profileManager.setDefaultTerminalApp(customTerminalApp)
                            }
                        }

                    Button("Set") {
                        if !customTerminalApp.isEmpty {
                            profileManager.setDefaultTerminalApp(customTerminalApp)
                        }
                    }
                    .disabled(customTerminalApp.isEmpty)
                }
            }

            // Automation permission status
            if automationPermissionGranted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Automation permission granted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Automation permission required")
                            .font(.caption)
                    }

                    Button("Open Automation Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .onAppear {
            checkAutomationPermission()
            setupCustomTerminal()
        }
    }

    private func checkAutomationPermission() {
        let script = """
        tell application "System Events"
            return name of first process whose frontmost is true
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
                DispatchQueue.main.async {
                    automationPermissionGranted = (error == nil)
                }
            }
        }
    }

    private func setupCustomTerminal() {
        let currentTerminal = profileManager.onScreenKeyboardSettings.defaultTerminalApp
        if !OnScreenKeyboardSettings.terminalOptions.contains(currentTerminal) {
            isUsingCustomTerminal = true
            customTerminalApp = currentTerminal
        }
    }
}
