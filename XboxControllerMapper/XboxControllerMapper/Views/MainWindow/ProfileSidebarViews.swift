import SwiftUI
import UniformTypeIdentifiers

// MARK: - Profile Sidebar

private struct ProfileDropDelegate: DropDelegate {
	let profile: Profile
	let profiles: [Profile]
	@Binding var draggedProfile: Profile?
	let moveProfiles: (IndexSet, Int) -> Void

	func performDrop(info: DropInfo) -> Bool {
		draggedProfile = nil
		return true
	}

	func dropEntered(info: DropInfo) {
		guard let draggedProfile,
		      draggedProfile.id != profile.id,
		      let sourceIndex = profiles.firstIndex(where: { $0.id == draggedProfile.id }),
		      let destinationIndex = profiles.firstIndex(where: { $0.id == profile.id }) else {
			return
		}

		withAnimation(.easeInOut(duration: 0.2)) {
			moveProfiles(
				IndexSet(integer: sourceIndex),
				destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
			)
		}
	}

	func dropUpdated(info: DropInfo) -> DropProposal? {
		DropProposal(operation: .move)
	}
}

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
	@State private var profileToShare: Profile?
    @State private var profileToLink: Profile?
    @State private var profileToLinkController: Profile?
    @State private var showingCommunityProfiles = false
	@State private var showingGuidedPreset = false
	@State private var draggedProfile: Profile?

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
					Button("Guided Preset…") { showingGuidedPreset = true }
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
                .help("Add profile")
                .accessibilityLabel("Add profile")
                .fixedSize()
                .hoverableIconButton()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

			// Make the existing gallery discoverable before a new user has
			// learned the Add menu. Imported/custom profiles keep the sidebar compact.
			if profileManager.profiles.count == 1, profileManager.profiles.first?.isDefault == true {
				Button {
					showingCommunityProfiles = true
				} label: {
					Label("Browse Starter Profiles", systemImage: "square.stack.3d.up")
						.font(.callout)
				}
				.buttonStyle(.bordered)
				.help("Ready-made mappings for Anki, presentations, and more")
				.padding(.horizontal, 12)
				.padding(.bottom, 12)
			}

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
							.onDrag {
								draggedProfile = profile
								return NSItemProvider(object: profile.id.uuidString as NSString)
							}
							.onDrop(of: [.text], delegate: ProfileDropDelegate(
								profile: profile,
								profiles: profileManager.profiles,
								draggedProfile: $draggedProfile,
								moveProfiles: profileManager.moveProfiles
							))
							.help("Drag to reorder profiles")
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
				    keyboardSourceProfiles: profileManager.onScreenKeyboardInheritanceCandidates(for: profile),
				    onSetOnScreenKeyboardSource: { sourceProfileId in
					profileManager.setOnScreenKeyboardInheritance(
					    for: profile,
					    sourceProfileId: sourceProfileId
					)
				    },
                                    onSetIcon: { iconName in
                                        profileManager.setProfileIcon(profile, icon: iconName)
                                    },
                                    onExport: {
                                        profileToExport = profile
                                        isExporting = true
                                    },
									onShare: { profileToShare = profileManager.communitySharingSource(for: profile) },
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
		.sheet(isPresented: $showingGuidedPreset) { GuidedPresetSheet() }
		.sheet(item: $profileToShare) { ShareCommunityProfileSheet(profile: $0) }
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
