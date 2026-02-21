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

    // Preview state
    @State private var previewingProfileId: String?
    @State private var previewedProfile: Profile?
    @State private var isLoadingPreview = false
    @State private var previewCache: [String: Profile] = [:]

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
                    CommunityProfilePreview(
                        profile: previewedProfile,
                        profileName: availableProfiles.first { $0.id == previewingProfileId }?.displayName,
                        isLoading: isLoadingPreview
                    )
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()

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
                }

                Spacer()

                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Downloading \(downloadedCount)/\(newProfilesToImportCount)...")
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

        // Check cache first
        if let cached = previewCache[profileInfo.id] {
            previewedProfile = cached
            return
        }

        isLoadingPreview = true
        previewedProfile = nil

        Task {
            do {
                let profile = try await profileManager.fetchProfileForPreview(from: profileInfo.downloadURL)
                await MainActor.run {
                    previewCache[profileInfo.id] = profile
                    // Only update if still previewing the same profile
                    if previewingProfileId == profileInfo.id {
                        previewedProfile = profile
                    }
                    isLoadingPreview = false
                }
            } catch {
                await MainActor.run {
                    isLoadingPreview = false
                }
            }
        }
    }

    private func downloadSelectedProfiles() {
        isDownloading = true
        downloadedCount = 0

        // Only download profiles that aren't already imported
        let profilesToDownload = availableProfiles.filter {
            selectedProfiles.contains($0.id) && !alreadyImportedProfiles.contains($0.id)
        }

        Task {
            var lastImportedProfile: Profile?

            for profileInfo in profilesToDownload {
                do {
                    // Use cached profile if available, otherwise download
                    let profile: Profile
                    if let cached = previewCache[profileInfo.id] {
                        profile = await MainActor.run {
                            profileManager.importFetchedProfile(cached)
                        }
                    } else {
                        profile = try await profileManager.downloadProfile(from: profileInfo.downloadURL)
                    }
                    lastImportedProfile = profile
                    await MainActor.run {
                        downloadedCount += 1
                    }
                } catch {
                    #if DEBUG
                    print("Failed to download profile \(profileInfo.name): \(error)")
                    #endif
                }
            }

            await MainActor.run {
                isDownloading = false
                if let profile = lastImportedProfile {
                    profileManager.setActiveProfile(profile)
                }
                dismiss()
            }
        }
    }
}

// MARK: - Community Profile Row

struct CommunityProfileRow: View {
    let profileInfo: CommunityProfileInfo
    let isSelected: Bool
    let isAlreadyImported: Bool
    let isPreviewing: Bool
    let onToggleSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox - disabled for already-imported profiles
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isAlreadyImported ? .secondary : (isSelected ? .accentColor : .secondary))
            }
            .buttonStyle(.plain)
            .disabled(isAlreadyImported)

            // Profile name (clickable for preview)
            Text(profileInfo.displayName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(isAlreadyImported ? .secondary : .primary)

            // Already imported indicator
            if isAlreadyImported {
                Text("Imported")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }

            // Preview indicator
            if isPreviewing {
                Image(systemName: "eye.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isPreviewing ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onToggleSelect()
            onPreview()
        }
        .onTapGesture(count: 1) {
            onPreview()
        }
    }
}

// MARK: - Community Profile Preview

struct CommunityProfilePreview: View {
    let profile: Profile?
    let profileName: String?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Loading preview...")
                Spacer()
            } else if let profile = profile {
                // Header
                HStack {
                    Text(profileName ?? profile.name)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(profile.buttonMappings.count) mappings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !profile.chordMappings.isEmpty {
                        Text("• \(profile.chordMappings.count) chords")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Mappings list
                ScrollView {
                    VStack(spacing: 6) {
                        // Button mappings
                        ForEach(ControllerButton.allCases.filter { profile.buttonMappings[$0] != nil }, id: \.self) { button in
                            if let mapping = profile.buttonMappings[button], !mapping.isEmpty {
                                PreviewMappingRow(button: button, mapping: mapping, profile: profile)
                            }
                        }

                        // Chord mappings
                        if !profile.chordMappings.isEmpty {
                            Divider()
                                .padding(.vertical, 12)

                            HStack {
                                Text("CHORDS")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                            VStack(spacing: 8) {
                                ForEach(profile.chordMappings) { chord in
                                    PreviewChordRow(chord: chord, profile: profile)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                // Empty state - no profile selected
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "gamecontroller")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.secondary.opacity(0.3))

                    VStack(spacing: 4) {
                        Text("Preview")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("Click a profile to see its mappings")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.4))
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.opacity(0.15))
    }
}

// MARK: - Preview Mapping Row

struct PreviewMappingRow: View {
    @EnvironmentObject var controllerService: ControllerService

    let button: ControllerButton
    let mapping: KeyMapping
    let profile: Profile

    var body: some View {
        HStack(spacing: 12) {
            ButtonIconView(button: button, isPressed: false, isDualSense: controllerService.threadSafeIsPlayStation)
                .frame(width: 28, height: 28)

            // Show mappings with hint + actual shortcut side by side
            HStack(spacing: 16) {
                // Primary mapping
                if let systemCommand = mapping.systemCommand {
                    PreviewMappingLabel(
                        text: mapping.hint ?? systemCommand.displayName,
                        shortcut: mapping.hint != nil ? systemCommand.displayName : nil,
                        icon: "SYS",
                        color: .green
                    )
                } else if let macroId = mapping.macroId,
                          let macro = profile.macros.first(where: { $0.id == macroId }) {
                    PreviewMappingLabel(
                        text: mapping.hint ?? macro.name,
                        shortcut: mapping.hint != nil ? "Macro: \(macro.name)" : nil,
                        icon: "▶",
                        color: .purple
                    )
                } else if !mapping.isEmpty {
                    PreviewMappingLabel(
                        text: mapping.hint ?? mapping.displayString,
                        shortcut: mapping.hint != nil ? mapping.displayString : nil,
                        icon: mapping.isHoldModifier ? "▼" : nil,
                        color: mapping.isHoldModifier ? .purple : .primary
                    )
                }

                // Long hold
                if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
                    PreviewMappingLabel(
                        text: longHold.hint ?? longHold.displayString,
                        shortcut: longHold.hint != nil ? longHold.displayString : nil,
                        icon: "⏱",
                        color: .orange
                    )
                }

                // Double tap
                if let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty {
                    PreviewMappingLabel(
                        text: doubleTap.hint ?? doubleTap.displayString,
                        shortcut: doubleTap.hint != nil ? doubleTap.displayString : nil,
                        icon: "2×",
                        color: .cyan
                    )
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }
}

struct PreviewMappingLabel: View {
    let text: String
    let shortcut: String?
    let icon: String?
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Text(icon)
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(color)
                    .cornerRadius(2)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color == .primary ? .primary : color)
                .lineLimit(1)

            // Show actual shortcut to the right if there's a hint
            if let shortcut = shortcut {
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Preview Chord Row

struct PreviewChordRow: View {
    @EnvironmentObject var controllerService: ControllerService

    let chord: ChordMapping
    let profile: Profile

    var body: some View {
        HStack(spacing: 12) {
            // Button icons - match main chord list spacing
            HStack(spacing: 4) {
                ForEach(Array(chord.buttons).sorted(by: { $0.category.chordDisplayOrder < $1.category.chordDisplayOrder }), id: \.self) { button in
                    ButtonIconView(button: button, isPressed: false, isDualSense: controllerService.threadSafeIsPlayStation)
                }
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // Action with hint + actual shortcut shown inline
            if let systemCommand = chord.systemCommand {
                chordActionLabel(
                    text: chord.hint ?? systemCommand.displayName,
                    shortcut: chord.hint != nil ? systemCommand.displayName : nil,
                    color: .green.opacity(0.9)
                )
            } else if let macroId = chord.macroId,
                      let macro = profile.macros.first(where: { $0.id == macroId }) {
                chordActionLabel(
                    text: chord.hint ?? macro.name,
                    shortcut: chord.hint != nil ? "Macro: \(macro.name)" : nil,
                    color: .purple.opacity(0.9)
                )
            } else {
                chordActionLabel(
                    text: chord.hint ?? chord.actionDisplayString,
                    shortcut: chord.hint != nil ? chord.actionDisplayString : nil,
                    color: .primary
                )
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func chordActionLabel(text: String, shortcut: String?, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)

            if let shortcut = shortcut {
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}
