import SwiftUI
import UniformTypeIdentifiers

// MARK: - Profile Sidebar

struct ProfileSidebar: View {
    @EnvironmentObject var profileManager: ProfileManager

    @State private var showingNewProfileAlert = false
    @State private var newProfileName = ""
    @State private var showingRenameProfileAlert = false
    @State private var renameProfileName = ""
    @State private var profileToRename: Profile?
    @State private var isImporting = false
    @State private var isImportingStreamDeck = false
    @State private var showingStreamDeckImport = false
    @State private var streamDeckFileURL: URL?
    @State private var isExporting = false
    @State private var profileToExport: Profile?
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
                    Button("Import Stream Deck Profile...") {
                        isImportingStreamDeck = true
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
        .fileImporter(
            isPresented: $isImportingStreamDeck,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                // No extension filter — the parser handles invalid files
                // and shows a descriptive error in the import sheet
                streamDeckFileURL = url
                showingStreamDeckImport = true
            case .failure:
                #if DEBUG
                print("Stream Deck file import failed")
                #endif
            }
        }
        .sheet(isPresented: $showingStreamDeckImport) {
            if let url = streamDeckFileURL {
                StreamDeckImportSheet(fileURL: url)
            }
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

struct ProfileListRow: View {
    let profile: Profile

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

struct ProfileContextMenu: View {
    let profile: Profile
    let profileCount: Int
    let onDuplicate: () -> Void
    let onRename: () -> Void
    let onSetDefault: () -> Void
    let onLinkApps: () -> Void
    let onSetIcon: (String?) -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Duplicate", action: onDuplicate)

        Button("Rename", action: onRename)

        Button("Set as Default Profile", action: onSetDefault)
            .disabled(profile.isDefault)

        Button("Linked Apps...", action: onLinkApps)

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
