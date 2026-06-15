import SwiftUI
import AppKit

// MARK: - Settings

/// Top-level settings categories shown in the sidebar. Apple System
/// Settings-style: a colored icon + label on the left, the selected pane on
/// the right.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case layout = "Layout"
    case controllers = "Controllers"
    case remoteMouse = "Remote Mouse"
    case about = "About"

    var id: String { rawValue }
    var label: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintpalette.fill"
        case .layout: return "rectangle.3.group.fill"
        case .controllers: return "gamecontroller.fill"
        case .remoteMouse: return "antenna.radiowaves.left.and.right"
        case .about: return "info.circle.fill"
        }
    }

    /// Background tint for the sidebar glyph (the rounded colored square).
    var tint: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .pink
        case .layout: return .blue
        case .controllers: return .green
        case .remoteMouse: return .purple
        case .about: return .orange
        }
    }
}

/// Settings presented as an Apple System Settings-style sheet: a sidebar of
/// categories on the left, the selected category's controls on the right.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var controllerService: ControllerService

    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("hideFromDock") private var hideFromDock = false
    @AppStorage(MainWindowSection.hiddenDefaultsKey) private var hiddenSectionTags = ""
    @AppStorage(ButtonMappingsTabSection.hiddenDefaultsKey) private var hiddenButtonSectionTags = ""
    @AppStorage("universalControlRelayHost") private var relayRemoteHost = "kmacstudio"
    @AppStorage("universalControlRelayPort") private var relayRemotePort = 38383
    @AppStorage(WindowBackgroundDefaults.opacityKey) private var windowBackgroundOpacity: Double = WindowBackgroundDefaults.defaultOpacity

    @ObservedObject private var license = LicenseManager.shared

    @State private var selection: SettingsCategory? = .general
    @State private var isRefreshingDatabase = false
    @State private var databaseStatus: String?
    @State private var relayPairingCodeInput = ""
    @State private var relaySecretStatus: String?
    @State private var relaySecretStatusIsError = false
    @State private var isCheckingRelaySecret = false
    @State private var licenseKeyInput = ""
    @State private var isVerifyingLicense = false
    @State private var licenseMessage: String?
    @State private var licenseMessageIsError = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailPane
        }
        .frame(width: 760, height: 560)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(SettingsCategory.allCases) { category in
                Label {
                    Text(category.label)
                } icon: {
                    Image(systemName: category.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(
                            category.tint,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }
                .tag(category)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 198)
    }

    // MARK: Detail

    private var detailPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text((selection ?? .general).label)
                    .font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 2)

            Form {
                detailSections
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var detailSections: some View {
        switch selection ?? .general {
        case .general: generalSection
        case .appearance: appearanceSection
        case .layout: layoutSections
        case .controllers: controllersSections
        case .remoteMouse: remoteMouseSection
        case .about: aboutSection
        }
    }

    // MARK: General

    @ViewBuilder
    private var generalSection: some View {
        licenseSection

        Section {
            Toggle("Launch at Login", isOn: $launchAtLogin)

            Toggle(isOn: $hideFromDock) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide Dock Icon")
                    Text("Run as a menu bar app. The dock icon only appears while the main window is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: hideFromDock) { _, _ in
                DockVisibilityController.shared.preferenceChanged()
                NotificationCenter.default.post(name: .hideFromDockPreferenceDidChange, object: nil)
                if !hideFromDock {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    // MARK: License

    @ViewBuilder
    private var licenseSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: licenseStatusIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(licenseStatusColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(licenseStatusTitle)
                        .font(.body.weight(.semibold))
                    if let subtitle = licenseStatusSubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }

            if license.isLicensed {
                Button("Deactivate on This Mac") {
                    license.clearLicense()
                    licenseMessage = nil
                }
                .controlSize(.small)
            } else {
                HStack {
                    TextField("Gumroad license key", text: $licenseKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .onSubmit { activateLicense() }

                    Button {
                        activateLicense()
                    } label: {
                        if isVerifyingLicense {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Activate")
                        }
                    }
                    .disabled(isVerifyingLicense || licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let url = URL(string: Config.updateCheckGumroadURL) {
                    Link("Buy a license", destination: url)
                        .font(.callout)
                }
            }

            if let licenseMessage {
                Label(
                    licenseMessage,
                    systemImage: licenseMessageIsError ? "xmark.circle.fill" : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(licenseMessageIsError ? .red : .green)
                .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("License")
        }
    }

    private var licenseStatusIcon: String {
        switch license.status {
        case .licensed: return "checkmark.seal.fill"
        case .trial: return "hourglass"
        case .expired: return "lock.fill"
        }
    }

    private var licenseStatusColor: Color {
        switch license.status {
        case .licensed: return .green
        case .trial(let days): return days <= 3 ? .orange : .blue
        case .expired: return .orange
        }
    }

    private var licenseStatusTitle: String {
        switch license.status {
        case .licensed:
            return "Licensed"
        case .trial(let days):
            return "Free Trial — \(days) day\(days == 1 ? "" : "s") left"
        case .expired:
            return "Trial Ended"
        }
    }

    private var licenseStatusSubtitle: String? {
        switch license.status {
        case .licensed:
            return "Thanks for supporting ControllerKeys."
        case .trial:
            return "Enter a license key any time to unlock permanently."
        case .expired:
            return "Controller mapping is paused. Enter a license to re-enable it."
        }
    }

    private func activateLicense() {
        let key = licenseKeyInput
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isVerifyingLicense = true
        licenseMessage = nil
        Task {
            let result = await license.verify(key: key)
            isVerifyingLicense = false
            licenseMessage = result.message
            licenseMessageIsError = !result.success
            if result.success {
                licenseKeyInput = ""
            }
        }
    }

    // MARK: Appearance

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Window Background Opacity")
                    Spacer()
                    Text("\(Int(windowBackgroundOpacity * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $windowBackgroundOpacity, in: 0.0...1.0)
                HStack {
                    Text("How much the desktop and other apps bleed through the window. Higher is more opaque.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Reset") {
                        windowBackgroundOpacity = WindowBackgroundDefaults.defaultOpacity
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: Layout (visible tabs / canvas sections)

    @ViewBuilder
    private var layoutSections: some View {
        Section {
            ForEach(ButtonMappingsTabSection.allCases) { section in
                Toggle(isOn: visibleButtonSectionBinding(for: section)) {
                    Text(section.label)
                }
            }

            Button("Show All Button Sections") {
                hiddenButtonSectionTags = ""
            }
        } header: {
            Text("Button Map Canvas")
        }

        ForEach(MainWindowNavGroup.allCases) { group in
            Section {
                ForEach(mainWindowSections(in: group)) { section in
                    mainSectionToggle(section)
                }
            } header: {
                Label(group.rawValue, systemImage: group.systemImage)
            }
        }

        Section {
            Button("Show All Main Sections") {
                hiddenSectionTags = ""
            }
        }
    }

    @ViewBuilder
    private func mainSectionToggle(_ section: MainWindowSection) -> some View {
        let available = section.isAvailable(
            isPlayStation: controllerService.threadSafeIsPlayStation,
            isDualSense: controllerService.threadSafeIsDualSense,
            isSteamController: controllerService.threadSafeIsSteamController,
            isAppleTVRemote: controllerService.threadSafeIsAppleTVRemote,
            hasMotion: controllerService.threadSafeHasMotion
        )

        Toggle(isOn: visibleSectionBinding(for: section)) {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.label)
                    if !available {
                        Text(unavailableReason(for: section))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .disabled(!available || isLastVisibleSection(section))
    }

    // MARK: Controllers

    @ViewBuilder
    private var controllersSections: some View {
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

        Section {
            Toggle(isOn: Binding(
                get: { ControllerService.isKeepAliveEnabled },
                set: { newValue in
                    ControllerService.isKeepAliveEnabled = newValue
                    if newValue {
                        controllerService.startKeepAliveTimer()
                    } else {
                        controllerService.stopKeepAliveTimer()
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prevent Controller Sleep")
                    Text("Sends periodic signals to keep PlayStation controllers awake over Bluetooth")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Bluetooth")
        }
    }

    // MARK: Remote Mouse

    @ViewBuilder
    private var remoteMouseSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pair a Remote Mac")
                            .font(.body)
                        Text("Start pairing, then enter the six-digit code shown on the other Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Button {
                        startRelayPairing()
                    } label: {
                        Label("Start", systemImage: "link")
                    }
                    .disabled(isCheckingRelaySecret)
                }

                relayCodeRow
            }

            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Remote Mac host")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Optional hostname or Tailscale IP", text: $relayRemoteHost)
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)

                        TextField("Port", value: $relayRemotePort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 84)
                    }
                }
            }

            if let relaySecretStatus {
                Label(
                    relaySecretStatus,
                    systemImage: relaySecretStatusIsError ? "xmark.circle.fill" : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(relaySecretStatusIsError ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Remote Mouse Pairing")
        }
    }

    private var relayCodeRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Code")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)

                    TextField("", text: relayPairingCodeBinding)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .lineLimit(1)
                        .frame(width: 96, height: 18)
                        .accessibilityLabel("Six-digit pairing code")
                }
                .frame(width: 116, height: 24)
            }

            Button {
                confirmRelayPairing()
            } label: {
                Label("Confirm", systemImage: "checkmark")
            }
            .disabled(isCheckingRelaySecret || relayPairingCodeInput.count != 6)

            if isCheckingRelaySecret {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer(minLength: 8)

            Button {
                resetRelayPairing()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .disabled(isCheckingRelaySecret)
        }
    }

    // MARK: About

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ControllerKeys")
                        .font(.title2.bold())
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }

        Section {
            Text("\u{00A9} 2026 Kevin Tang. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func mainWindowSections(in group: MainWindowNavGroup) -> [MainWindowSection] {
        MainWindowSection.displayOrder.filter { $0.navGroup == group }
    }

    private func setRelaySecretStatus(_ message: String, isError: Bool) {
        relaySecretStatus = message
        relaySecretStatusIsError = isError
    }

    private var relayPairingCodeBinding: Binding<String> {
        Binding(
            get: { relayPairingCodeInput },
            set: { relayPairingCodeInput = String($0.filter { $0.isNumber }.prefix(6)) }
        )
    }

    private func startRelayPairing() {
        isCheckingRelaySecret = true
        relayPairingCodeInput = ""
        setRelaySecretStatus("Searching for ControllerKeys on LAN and tailnet...", isError: false)
        UniversalControlMouseRelay.shared.startRelayCodePairing { success, message in
            isCheckingRelaySecret = false
            setRelaySecretStatus(message, isError: !success)
        }
    }

    private func confirmRelayPairing() {
        isCheckingRelaySecret = true
        UniversalControlMouseRelay.shared.completeRelayCodePairing(code: relayPairingCodeInput) { success, message in
            isCheckingRelaySecret = false
            if success {
                relayPairingCodeInput = ""
            }
            setRelaySecretStatus(message, isError: !success)
        }
    }

    private func resetRelayPairing() {
        UniversalControlMouseRelay.shared.resetRelayPairingSecret()
        relayPairingCodeInput = ""
        setRelaySecretStatus(
            "Reset. Pair again before using remote mouse.",
            isError: false
        )
    }

    private func visibleSectionBinding(for section: MainWindowSection) -> Binding<Bool> {
        Binding(
            get: {
                !MainWindowSection.hiddenSections(from: hiddenSectionTags).contains(section)
            },
            set: { isVisible in
                var hiddenSections = MainWindowSection.hiddenSections(from: hiddenSectionTags)
                if isVisible {
                    hiddenSections.remove(section)
                } else if !isLastVisibleSection(section) {
                    hiddenSections.insert(section)
                }
                hiddenSectionTags = MainWindowSection.encodedHiddenSections(hiddenSections)
            }
        )
    }

    private func isLastVisibleSection(_ section: MainWindowSection) -> Bool {
        let hiddenSections = MainWindowSection.hiddenSections(from: hiddenSectionTags)
        let visibleSections = MainWindowSection.visibleSections(
            hiddenSections: hiddenSections,
            isPlayStation: controllerService.threadSafeIsPlayStation,
            isDualSense: controllerService.threadSafeIsDualSense,
            isSteamController: controllerService.threadSafeIsSteamController,
            isAppleTVRemote: controllerService.threadSafeIsAppleTVRemote,
            hasMotion: controllerService.threadSafeHasMotion
        )
        return visibleSections.count == 1 && visibleSections.first == section
    }

    private func visibleButtonSectionBinding(for section: ButtonMappingsTabSection) -> Binding<Bool> {
        Binding(
            get: {
                !ButtonMappingsTabSection.hiddenSections(from: hiddenButtonSectionTags).contains(section)
            },
            set: { isVisible in
                var hiddenSections = ButtonMappingsTabSection.hiddenSections(from: hiddenButtonSectionTags)
                if isVisible {
                    hiddenSections.remove(section)
                } else {
                    hiddenSections.insert(section)
                }
                hiddenButtonSectionTags = ButtonMappingsTabSection.encodedHiddenSections(hiddenSections)
            }
        )
    }

    private func unavailableReason(for section: MainWindowSection) -> String {
        switch section {
        case .touchpad:
            return "Requires a PlayStation, Steam, or Apple TV Remote"
        case .leds:
            return "Requires a PlayStation controller"
        case .gestures:
            return "Requires a controller with a gyroscope"
        case .microphone:
            return "Requires a DualSense controller"
        default:
            return ""
        }
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
