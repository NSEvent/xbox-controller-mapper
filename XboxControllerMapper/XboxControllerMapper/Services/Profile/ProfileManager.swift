import Foundation
import Combine
import SwiftUI

/// Errors that can occur when importing profiles from the community repository
enum CommunityProfileError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let error):
            return "Failed to decode profile: \(error.localizedDescription)"
        }
    }
}

/// Represents a profile available in the community repository
struct CommunityProfileInfo: Identifiable, Decodable {
    let name: String
    let downloadURL: String

    var id: String { name }

    var displayName: String {
        name.replacingOccurrences(of: ".json", with: "")
    }

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "download_url"
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        downloadURL = try container.decode(String.self, forKey: .downloadURL)
    }
}

/// Manages profile persistence and selection
@MainActor
class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfile: Profile?
    @Published var activeProfileId: UUID?
    @Published var uiScale: CGFloat = 1.0
    /// Non-nil when the initial config load failed. UI can observe this to show a warning.
    @Published var configLoadError: String?

    var onScreenKeyboardSettings: OnScreenKeyboardSettings {
        activeProfile?.onScreenKeyboardSettings ?? OnScreenKeyboardSettings()
    }

    private let fileManager = FileManager.default
    private let configurationSaveService: ProfileConfigurationSaveService
    private let configURL: URL
    private let legacyConfigURL: URL
    /// Tracks if config load succeeded to prevent clobbering on save.
    /// Thread-safe: only accessed from @MainActor context (all callers are @MainActor-isolated).
    private var loadSucceeded = false
    
    // Track previous app for restoration logic
    private var previousBundleId: String?
    private var profileIdBeforeBackground: UUID?
    
    private var cancellables = Set<AnyCancellable>()

    init(appMonitor: AppMonitor? = nil, configDirectoryOverride: URL? = nil) {
        let configPaths = ProfileConfigPathResolver.resolve(
            fileManager: fileManager,
            configDirectoryOverride: configDirectoryOverride
        )
        configurationSaveService = ProfileConfigurationSaveService(fileManager: fileManager)
        configURL = configPaths.configURL
        legacyConfigURL = configPaths.legacyConfigURL
        createDirectoryIfNeeded(at: configPaths.configDirectory)

        loadConfiguration()
        loadCachedFavicons()
        ensureActiveProfileSelection()
        
        // Initialize state for app switching
        self.previousBundleId = Bundle.main.bundleIdentifier
        self.profileIdBeforeBackground = activeProfileId
        
        if let appMonitor = appMonitor {
            setupAutoSwitching(with: appMonitor)
        }
    }
    
    private func setupAutoSwitching(with appMonitor: AppMonitor) {
        appMonitor.$frontmostBundleId
            .removeDuplicates()
            .dropFirst() // Skip initial value to avoid overriding manual selection on launch
            .sink { [weak self] bundleId in
                guard let self = self, let bundleId = bundleId else { return }
                self.handleAppChange(bundleId)
            }
            .store(in: &cancellables)
    }
    
    private func handleAppChange(_ bundleId: String) {
        let appBundleId = Bundle.main.bundleIdentifier
        let state = ProfileAutoSwitchState(
            previousBundleId: previousBundleId,
            profileIdBeforeBackground: profileIdBeforeBackground,
            activeProfileId: activeProfileId
        )
        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: bundleId,
            appBundleId: appBundleId,
            profiles: profiles,
            state: state
        )

        previousBundleId = result.previousBundleId
        profileIdBeforeBackground = result.profileIdBeforeBackground

        guard let action = result.action,
              let profile = profiles.first(where: { $0.id == action.profileId }) else {
            return
        }

        #if DEBUG
        switch action.reason {
        case .restoreEditingProfile:
            print("🔄 Restoring editing profile: \(profile.name)")
        case .linkedApp(let bundleId):
            print("🔄 Auto-switching to profile: \(profile.name) for app: \(bundleId)")
        case .defaultProfile(let bundleId):
            print("🔄 Auto-switching to default profile for app: \(bundleId)")
        }
        #endif

        setActiveProfile(profile)
    }
    
    @discardableResult
    private func createDirectoryIfNeeded(at url: URL) -> Bool {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            NSLog("[ProfileManager] Failed to create directory at %@: %@", url.path, error.localizedDescription)
            return false
        }
    }

    private func ensureActiveProfileSelection() {
        let action = ProfileBootstrapSelectionPolicy.resolve(
            profiles: profiles,
            hasActiveProfile: activeProfile != nil
        )

        switch action {
        case .createAndActivateDefault:
            let defaultProfile = Profile.createDefault()
            profiles.append(defaultProfile)
            setActiveProfile(defaultProfile)
        case .activateProfile(let profileId):
            guard let profile = profiles.first(where: { $0.id == profileId }) else { return }
            setActiveProfile(profile)
        case .none:
            break
        }
    }
    
    // MARK: - UI Settings
    
    func setUiScale(_ scale: CGFloat) {
        uiScale = scale
        saveConfiguration()
    }

    // MARK: - Profile Management

    func createProfile(name: String, basedOn template: Profile? = nil) -> Profile {
        var newProfile: Profile
        if let template = template {
        newProfile = template
            newProfile.id = UUID()
            newProfile.name = name
            newProfile.isDefault = false
            newProfile.createdAt = Date()
            newProfile.modifiedAt = Date()
        } else {
            newProfile = Profile(
                name: name,
                onScreenKeyboardSettings: activeProfile?.onScreenKeyboardSettings ?? OnScreenKeyboardSettings()
            )
        }

        profiles.append(newProfile)
        saveConfiguration()
        return newProfile
    }

    func deleteProfile(_ profile: Profile) {
        // Don't delete the last profile
        guard profiles.count > 1 else { return }

        profiles.removeAll { $0.id == profile.id }
        saveConfiguration()

        // If we deleted the active profile, switch to another
        if activeProfileId == profile.id {
            if let firstProfile = profiles.first {
                setActiveProfile(firstProfile)
            }
        }
    }

    func duplicateProfile(_ profile: Profile) -> Profile {
        createProfile(name: "\(profile.name) Copy", basedOn: profile)
    }

    func updateProfile(_ profile: Profile) {
        var updatedProfile = profile
        updatedProfile.modifiedAt = Date()

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = updatedProfile
        }

        saveConfiguration()

        if activeProfileId == profile.id {
            activeProfile = updatedProfile
        }
    }

    func setActiveProfile(_ profile: Profile) {
        activeProfile = profile
        activeProfileId = profile.id
        saveConfiguration()
    }

    func setDefaultProfile(_ profile: Profile) {
        var didChange = false

        for index in profiles.indices {
            let shouldBeDefault = profiles[index].id == profile.id
            if profiles[index].isDefault != shouldBeDefault {
                profiles[index].isDefault = shouldBeDefault
                didChange = true
            }
        }

        guard didChange else { return }

        if let activeId = activeProfileId,
           let updatedActive = profiles.first(where: { $0.id == activeId }) {
            activeProfile = updatedActive
        }

        saveConfiguration()
    }

    func renameProfile(_ profile: Profile, to newName: String) {
        var updatedProfile = profile
        updatedProfile.name = newName
        updateProfile(updatedProfile)
    }

    func setProfileIcon(_ profile: Profile, icon: String?) {
        var updatedProfile = profile
        updatedProfile.icon = icon
        updateProfile(updatedProfile)
    }

    // MARK: - Joystick Settings

    func updateJoystickSettings(_ settings: JoystickSettings, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.joystickSettings = settings
        updateProfile(targetProfile)
    }

    // MARK: - DualSense LED Settings

    func updateDualSenseLEDSettings(_ settings: DualSenseLEDSettings, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.dualSenseLEDSettings = settings
        updateProfile(targetProfile)
    }

    // MARK: - Persistence
    private func loadConfiguration() {
        guard let loadSource = ProfileConfigLoadSourceResolver.resolve(
            fileManager: fileManager,
            configURL: configURL,
            legacyConfigURL: legacyConfigURL
        ) else {
            return
        }

        let urlToLoad = loadSource.url
        let migratingFromLegacy = loadSource.migratingFromLegacy
        if let preLoadLog = ProfileConfigurationPostLoadPolicy.preLoadLogMessage(
            migratingFromLegacy: migratingFromLegacy,
            legacyConfigURL: legacyConfigURL
        ) {
            NSLog("%@", preLoadLog)
        }

        do {
            let result = try ProfileConfigurationLoadCoordinator.load(from: urlToLoad)
            let applyState = ProfileConfigurationApplyService.resolveState(
                currentUiScale: uiScale,
                result: result
            )
            applyLoadedState(applyState)

            loadSucceeded = true  // Mark that we successfully loaded the config

            let decision = ProfileConfigurationPostLoadPolicy.persistenceDecision(
                migratingFromLegacy: migratingFromLegacy,
                didMigrate: result.didMigrate,
                configURL: configURL
            )

            if decision.shouldPersist {
                saveConfiguration()
                if let postPersistLog = decision.postPersistLogMessage {
                    NSLog("%@", postPersistLog)
                }
            }
        } catch {
            NSLog("[ProfileManager] ⚠️ Configuration load failed: \(error)")
            configLoadError = error.localizedDescription
            // loadSucceeded stays false — saves will be blocked until in-memory state is validated.
            // See saveConfiguration() for the recovery logic.
        }
    }

    private func applyLoadedState(_ state: ProfileConfigurationApplyState) {
        self.profiles = state.profiles
        self.activeProfile = state.activeProfile
        self.activeProfileId = state.activeProfileId
        self.uiScale = state.uiScale
    }

    private func saveConfiguration() {
        // Safety check: don't save if load failed (to avoid clobbering existing config).
        // Recovery: if load failed but user has since built up valid in-memory state
        // (non-empty profiles), allow the save — the user's work should not be silently lost.
        if !configurationSaveService.shouldSave(loadSucceeded: loadSucceeded, configURL: configURL) {
            if !profiles.isEmpty {
                NSLog("[ProfileManager] ⚠️ Config load had failed, but in-memory state has %d profile(s) — allowing save to preserve user work", profiles.count)
                loadSucceeded = true
                configLoadError = nil
            } else {
                NSLog("[ProfileManager] ⚠️ Skipping save — config load failed earlier and no valid profiles in memory. User data on disk is preserved.")
                return
            }
        }

        // Snapshot captured here on @MainActor BEFORE dispatching to the serial save queue.
        // This guarantees each save gets the state at the time it was requested,
        // and the serial queue guarantees they are written in order (fixes Issue 5 & 13).
        let config = ProfileConfiguration(
            profiles: profiles,
            activeProfileId: activeProfileId,
            uiScale: uiScale
        )
        configurationSaveService.save(config, to: configURL)
    }

    // MARK: - Import/Export

    func exportProfile(_ profile: Profile, to url: URL) throws {
        try ProfileTransferService.export(profile, to: url)
    }

    func importProfile(from url: URL) throws -> Profile {
        let profile = try ProfileTransferService.importProfile(from: url)
        return persistImportedProfile(profile)
    }

    // MARK: - Community Profiles

    /// Fetches the list of available community profiles from GitHub
    nonisolated func fetchCommunityProfiles() async throws -> [CommunityProfileInfo] {
        try await CommunityProfileClient.fetchCommunityProfiles()
    }

    /// Fetches a profile for preview without importing it
    nonisolated func fetchProfileForPreview(from urlString: String) async throws -> Profile {
        try await CommunityProfileClient.fetchProfile(from: urlString)
    }

    /// Imports a profile that was previously fetched (e.g., from preview cache)
    func importFetchedProfile(_ profile: Profile) -> Profile {
        persistImportedProfile(ProfileTransferService.prepareForImport(profile))
    }

    /// Imports a profile built from a Stream Deck profile
    func importStreamDeckProfile(_ profile: Profile) -> Profile {
        persistImportedProfile(ProfileTransferService.prepareForImport(profile))
    }

    /// Downloads and imports a profile from a URL
    nonisolated func downloadProfile(from urlString: String) async throws -> Profile {
        let downloadedProfile = try await CommunityProfileClient.fetchProfile(from: urlString)
        return await MainActor.run {
            let importedProfile = ProfileTransferService.prepareForImport(downloadedProfile)
            return persistImportedProfile(importedProfile)
        }
    }

    private func persistImportedProfile(_ profile: Profile) -> Profile {
        profiles.append(profile)
        saveConfiguration()
        return profile
    }
}
