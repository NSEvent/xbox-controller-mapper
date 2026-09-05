import SwiftUI

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
	@State private var downloadTotal = 0
	@State private var importFailures: [CommunityProfileImportBatch.Failure] = []
	@State private var importTask: Task<Void, Never>?
	@State private var previewError: String?
	@State private var previewRequestID = UUID()

    // Preview state
    @State private var previewingProfileId: String?
    @State private var previewedProfile: Profile?
    @State private var isLoadingPreview = false
    @State private var previewCache: [String: Profile] = [:]

    // Setup guide state (sidecar markdown)
    @State private var previewedSetupGuide: String?
    @State private var setupGuideCache: [String: String?] = [:]

    // Safety approval (shell commands / scripts in imported profile)
    @State private var pendingSafetyApproval: SafetyApprovalRequest?

    /// Bridges the synchronous SwiftUI sheet flow with the async download
    /// loop: the loop awaits a continuation that fires when the user clicks
    /// Import or Cancel on the safety sheet.
    ///
    /// `resume(_:)` is idempotent — only the first call wins. This lets the
    /// sheet's `.onDisappear` safely fire as a fallback without double-resuming
    /// (which would crash with a checked-continuation violation) when the user
    /// already clicked a button.
    private final class SafetyApprovalRequest: Identifiable {
        let id = UUID()
        let profileName: String
        let report: ProfileImportSafetyReport
        private var continuation: CheckedContinuation<Bool, Never>?

        init(profileName: String, report: ProfileImportSafetyReport, continuation: CheckedContinuation<Bool, Never>) {
            self.profileName = profileName
            self.report = report
            self.continuation = continuation
        }

        func resume(approved: Bool) {
            continuation?.resume(returning: approved)
            continuation = nil
        }
    }

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
                .keyboardShortcut(.cancelAction)
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
									guard !isDownloading else { return }
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
					VStack(spacing: 0) {
						if let previewError {
							Text(previewError).font(.callout).foregroundStyle(.secondary).padding()
							Button("Retry Preview") {
								if let info = availableProfiles.first(where: { $0.id == previewingProfileId }) {
									loadPreview(for: info)
								}
							}
						}
						CommunityProfilePreview(
							profile: previewedProfile,
							profileName: availableProfiles.first { $0.id == previewingProfileId }?.displayName,
							setupGuide: previewedSetupGuide,
							isLoading: isLoadingPreview
						)
					}
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()

			if !importFailures.isEmpty {
				ScrollView {
					VStack(alignment: .leading, spacing: 4) {
						Text("Some profiles couldn't be imported. Check your connection and try Import again.")
							.font(.callout.weight(.semibold))
						ForEach(Array(importFailures.enumerated()), id: \.offset) { _, failure in
							Text("\(failure.profileName): \(failure.message)").font(.caption)
						}
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(12)
				}
				.frame(maxHeight: 105)
				.background(Color.orange.opacity(0.1))
			}

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
					.disabled(isDownloading)
                }

                Spacer()

                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.7)
					Text("Downloaded \(downloadedCount)/\(downloadTotal)")
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
		.onDisappear {
			importTask?.cancel()
			pendingSafetyApproval?.resume(approved: false)
			pendingSafetyApproval = nil
		}
        .sheet(item: $pendingSafetyApproval) { request in
            ProfileImportSafetySheet(
                profileName: request.profileName,
                report: request.report,
				onApprove: {
					pendingSafetyApproval = nil
					request.resume(approved: true)
				},
				onCancel: {
					pendingSafetyApproval = nil
					request.resume(approved: false)
				}
            )
            // Safety net for any non-button dismissal (parent close, system
            // event, view teardown). resume() is idempotent so this is a
            // no-op when the user clicked Approve or Cancel.
            .onDisappear { request.resume(approved: false) }
        }
    }

    /// Audit the profile and, if it carries shell commands or scripts, present
    /// the safety sheet and await the user's choice. Returns true on approve
    /// or no-warning-needed; false on cancel.
    private func requestSafetyApproval(for profile: Profile, displayName: String) async -> Bool {
        let report = ProfileImportSafetyAuditor.audit(profile)
        guard report.requiresUserConfirmation else { return true }
        return await withCheckedContinuation { continuation in
			pendingSafetyApproval = SafetyApprovalRequest(
				profileName: displayName, report: report, continuation: continuation
			)
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
		previewError = nil
		let requestID = UUID()
		previewRequestID = requestID

        // Setup guide: outer optional == "have we tried fetching", inner == "did one exist".
        // `if let` unwraps the outer only, so a cached "no guide" is honored without a refetch.
        if let cachedGuide = setupGuideCache[profileInfo.id] {
            previewedSetupGuide = cachedGuide
        } else {
            previewedSetupGuide = nil
			loadSetupGuide(for: profileInfo, requestID: requestID)
        }

        // Check profile cache
        if let cached = previewCache[profileInfo.id] {
            previewedProfile = cached
            // Clear the spinner left over from any in-flight load triggered by
            // a previous selection — without this, switching from a loading
            // profile to a cached one leaves the spinner visible forever.
            isLoadingPreview = false
            return
        }

        isLoadingPreview = true
        previewedProfile = nil

        Task {
            do {
                let profile = try await profileManager.fetchProfileForPreview(from: profileInfo.downloadURL)
                await MainActor.run {
                    previewCache[profileInfo.id] = profile
					// Also distinguish A → B → A: the first A request is stale.
					if previewRequestID == requestID {
                        previewedProfile = profile
						isLoadingPreview = false
                    }
                }
            } catch {
                await MainActor.run {
					if previewRequestID == requestID {
						previewError = error.localizedDescription
						isLoadingPreview = false
					}
                }
            }
        }
    }

	private func loadSetupGuide(for profileInfo: CommunityProfileInfo, requestID: UUID) {
        Task {
            let guide = try? await profileManager.fetchSetupGuideForPreview(profileURL: profileInfo.downloadURL)
            await MainActor.run {
                setupGuideCache[profileInfo.id] = guide
				if previewRequestID == requestID {
                    previewedSetupGuide = guide
                }
            }
        }
    }

    private func downloadSelectedProfiles() {
		guard !isDownloading else { return }
        isDownloading = true
        downloadedCount = 0
		importFailures = []

        // Only download profiles that aren't already imported
        let profilesToDownload = availableProfiles.filter {
            selectedProfiles.contains($0.id) && !alreadyImportedProfiles.contains($0.id)
        }
		downloadTotal = profilesToDownload.count

		importTask = Task { @MainActor in
			let result = await CommunityProfileImportBatch.run(
				profilesToDownload,
				fetch: { info in
					if let cached = previewCache[info.id] { return cached }
					return try await profileManager.fetchProfileForPreview(from: info.downloadURL)
				},
				approve: { profile, name in
					await requestSafetyApproval(for: profile, displayName: name)
				},
				persist: { profileManager.importFetchedProfile($0) },
				didImport: { info, _ in
					alreadyImportedProfiles.insert(info.id)
					downloadedCount += 1
                }
			)
			isDownloading = false
			guard !Task.isCancelled else { return }
			importFailures = result.failures
			if let profile = result.imported.last { profileManager.setActiveProfile(profile) }
			if result.shouldDismiss { dismiss() }
        }
    }
}
