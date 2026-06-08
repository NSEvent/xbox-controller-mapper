import SwiftUI
import UniformTypeIdentifiers

// MARK: - Profile Sidebar

struct ProfileSidebar: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService

    @State private var showingNewProfileAlert = false
    @State private var newProfileName = ""
    @State private var showingRenameProfileAlert = false
    @State private var renameProfileName = ""
    @State private var profileToRename: Profile?
    @State private var isImporting = false
    @State private var importType: ProfileImportType = .json
    @State private var showingStreamDeckImport = false
    @State private var streamDeckFileURL: URL?
    @State private var isExporting = false
    @State private var profileToExport: Profile?
    @State private var profileToLink: Profile?
    @State private var profileToLinkController: Profile?
    @State private var showingCommunityProfiles = false

    // Safety approval (shell commands / scripts in imported profile)
    @State private var pendingSafetyApproval: SafetyApprovalRequest?

    private final class SafetyApprovalRequest: Identifiable {
        let id = UUID()
        let profile: Profile
        let report: ProfileImportSafetyReport
        let displayName: String

        init(profile: Profile, report: ProfileImportSafetyReport, displayName: String) {
            self.profile = profile
            self.report = report
            self.displayName = displayName
        }
    }

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
                        importType = .json
                        isImporting = true
                    }
                    Button("Import Stream Deck Profile...") {
                        importType = .streamDeck
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
                .accessibilityLabel("Add profile")
                .help("Add profile")
                .fixedSize()
                .hoverableIconButton()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            // Profile list
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(profileManager.profiles) { profile in
                        ProfileListRow(profile: profile)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .hoverableGlassRow(isActive: profile.id == profileManager.activeProfileId) {
                                profileManager.setActiveProfile(profile)
                            }
                            .padding(.horizontal, 12)
                            .contextMenu {
                                ProfileContextMenu(
                                    profile: profile,
                                    profileCount: profileManager.profiles.count,
                                    onDuplicate: {
                                        _ = profileManager.duplicateProfile(profile)
                                    },
                                    onRename: {
                                        profileToRename = profile
                                        renameProfileName = profile.name
                                        showingRenameProfileAlert = true
                                    },
                                    onSetDefault: {
                                        profileManager.setDefaultProfile(profile)
                                    },
                                    onLinkApps: {
                                        profileToLink = profile
                                    },
                                    onLinkController: {
                                        profileToLinkController = profile
                                    },
                                    onSetIcon: { iconName in
                                        profileManager.setProfileIcon(profile, icon: iconName)
                                    },
                                    onExport: {
                                        profileToExport = profile
                                        isExporting = true
                                    },
                                    onDelete: {
                                        profileManager.deleteProfile(profile)
                                    }
                                )
                            }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showingNewProfileAlert) {
            ProfileNameSheet(
                title: "New Profile",
                actionLabel: "Create",
                name: $newProfileName
            ) {
                if !newProfileName.isEmpty {
                    let profile = profileManager.createProfile(name: newProfileName)
                    profileManager.setActiveProfile(profile)
                    newProfileName = ""
                }
            } onCancel: {
                newProfileName = ""
            }
        }
        .sheet(isPresented: $showingRenameProfileAlert) {
            ProfileNameSheet(
                title: "Rename Profile",
                actionLabel: "Rename",
                name: $renameProfileName
            ) {
                if !renameProfileName.isEmpty, let profile = profileToRename {
                    profileManager.renameProfile(profile, to: renameProfileName)
                }
                renameProfileName = ""
                profileToRename = nil
            } onCancel: {
                renameProfileName = ""
                profileToRename = nil
            }
        }
        .sheet(item: $profileToLink) { profile in
            LinkedAppsSheet(profile: profile)
        }
        .sheet(item: $profileToLinkController) { profile in
            LinkedControllersSheet(profile: profile)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                switch importType {
                case .json:
                    do {
                        // Parse first so we can audit, then either install
                        // immediately or route through the safety sheet.
                        let candidate = try ProfileTransferService.importProfile(from: url)
                        let report = ProfileImportSafetyAuditor.audit(candidate)
                        if report.requiresUserConfirmation {
                            pendingSafetyApproval = SafetyApprovalRequest(
                                profile: candidate,
                                report: report,
                                displayName: candidate.name
                            )
                        } else {
                            let imported = profileManager.importFetchedProfile(candidate)
                            profileManager.setActiveProfile(imported)
                        }
                    } catch {
                        // Import failed, profile not loaded
                    }
                case .streamDeck:
                    // No extension filter — the parser handles invalid files
                    // and shows a descriptive error in the import sheet
                    streamDeckFileURL = url
                    showingStreamDeckImport = true
                }
            case .failure:
                #if DEBUG
                print("File import failed")
                #endif
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
        .sheet(isPresented: $showingStreamDeckImport) {
            if let url = streamDeckFileURL {
                StreamDeckImportSheet(fileURL: url)
            }
        }
        .sheet(isPresented: $showingCommunityProfiles) {
            CommunityProfilesSheet()
        }
        .sheet(item: $pendingSafetyApproval) { request in
            ProfileImportSafetySheet(
                profileName: request.displayName,
                report: request.report,
                onApprove: {
                    let imported = profileManager.importFetchedProfile(request.profile)
                    profileManager.setActiveProfile(imported)
                },
                onCancel: {}
            )
        }
    }
}

private enum ProfileImportType {
    case json
    case streamDeck
}

struct ProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var profile: Profile?

    init(profile: Profile?) {
        self.profile = profile
    }

    init(configuration: ReadConfiguration) throws {
        // Not used for export-only
        guard let data = configuration.file.regularFileContents else {
            // Empty/unreadable file — surfaced to SwiftUI as a corrupt-file error
            // instead of crashing on `data!`.
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.profile = try? decoder.decode(Profile.self, from: data)
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
    @EnvironmentObject var appMonitor: AppMonitor

    let profile: Profile

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    LinkedProfileAppIcons(bundleIdentifiers: profile.linkedApps)
                }

                Text("\(profile.buttonMappings.count) \(String(localized: "mappings"))")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            HStack(spacing: 7) {
                if let iconName = profile.icon {
                    ProfileStatusBadge(
                        systemName: iconName,
                        color: .accentColor,
                        helpText: "Profile icon"
                    )
                }

                if profile.inputLatencyMode == .realtime {
                    ProfileStatusBadge(
                        systemName: "bolt.fill",
                        color: .orange,
                        helpText: "Realtime input latency"
                    )
                }

                if !profile.linkedControllers.isEmpty {
                    ProfileStatusBadge(
                        systemName: "gamecontroller.fill",
                        color: .accentColor,
                        helpText: "Linked controller"
                    )
                }

                if profile.isDefault {
                    ProfileStatusBadge(
                        systemName: "star.fill",
                        color: .yellow,
                        helpText: "Default profile"
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct LinkedProfileAppIcons: View {
    @EnvironmentObject var appMonitor: AppMonitor

    let bundleIdentifiers: [String]

    private var visibleBundleIds: [String] {
        Array(bundleIdentifiers.prefix(4))
    }

    private var remainingCount: Int {
        max(0, bundleIdentifiers.count - visibleBundleIds.count)
    }

    var body: some View {
        if !bundleIdentifiers.isEmpty {
            HStack(spacing: 3) {
                ForEach(visibleBundleIds, id: \.self) { bundleId in
                    LinkedProfileAppIcon(appInfo: appMonitor.appInfo(for: bundleId), bundleId: bundleId)
                }

                if remainingCount > 0 {
                    Text("+\(remainingCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .monospacedDigit()
                        .help("\(remainingCount) more Linked Apps")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct LinkedProfileAppIcon: View {
    let appInfo: AppInfo?
    let bundleId: String

    var body: some View {
        Group {
            if let icon = appInfo?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(1)
            }
        }
        .frame(width: 14, height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .help(appInfo?.name ?? bundleId)
        .accessibilityLabel(appInfo?.name ?? bundleId)
    }
}

private struct ProfileStatusBadge: View {
    let systemName: String
    let color: Color
    let helpText: String

    var body: some View {
        Image(systemName: systemName)
            .font(.caption)
            .foregroundColor(color)
            .help(helpText)
            .accessibilityLabel(helpText)
    }
}

struct ProfileContextMenu: View {
    let profile: Profile
    let profileCount: Int
    let onDuplicate: () -> Void
    let onRename: () -> Void
    let onSetDefault: () -> Void
    let onLinkApps: () -> Void
    let onLinkController: () -> Void
    let onSetIcon: (String?) -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Duplicate", action: onDuplicate)

        Button("Rename", action: onRename)

        Button("Set as Default Profile", action: onSetDefault)
            .disabled(profile.isDefault)

        Button("Linked Apps...", action: onLinkApps)
        Button("Linked Controller...", action: onLinkController)

        Menu("Set Icon") {
            ForEach(ProfileIcon.grouped, id: \.name) { group in
                Menu(group.name) {
                    ForEach(group.icons) { icon in
                        Button {
                            onSetIcon(icon.rawValue)
                        } label: {
                            Label(icon.displayName, systemImage: icon.rawValue)
                        }
                    }
                }
            }

            Divider()

            Button("Remove Icon") {
                onSetIcon(nil)
            }
            .disabled(profile.icon == nil)
        }

        Button("Export...", action: onExport)

        Divider()

        Button("Delete", role: .destructive, action: onDelete)
            .disabled(profileCount <= 1)
    }
}

// MARK: - Profile Name Sheet

struct ProfileNameSheet: View {
    let title: String
    let actionLabel: String
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)

            TextField("Profile name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(actionLabel) {
                    onSave()
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onSubmit {
            guard !name.isEmpty else { return }
            onSave()
            dismiss()
        }
    }
}
