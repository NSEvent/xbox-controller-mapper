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

    var onScreenKeyboardSettings: OnScreenKeyboardSettings {
        activeProfile?.onScreenKeyboardSettings ?? OnScreenKeyboardSettings()
    }

    private let fileManager = FileManager.default
    private let configURL: URL
    private let legacyConfigURL: URL
    private var loadSucceeded = false  // Track if initial load succeeded to prevent clobbering
    
    // Track previous app for restoration logic
    private var previousBundleId: String?
    private var profileIdBeforeBackground: UUID?
    
    private var cancellables = Set<AnyCancellable>()

    init(appMonitor: AppMonitor? = nil, configDirectoryOverride: URL? = nil) {
        let configPaths = ProfileConfigPathResolver.resolve(
            fileManager: fileManager,
            configDirectoryOverride: configDirectoryOverride
        )
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
    
    private func createDirectoryIfNeeded(at url: URL) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            // Directory creation failed, but we'll handle it gracefully
        }
    }

    private func ensureActiveProfileSelection() {
        if profiles.isEmpty {
            let defaultProfile = Profile.createDefault()
            profiles.append(defaultProfile)
            setActiveProfile(defaultProfile)
            return
        }

        guard activeProfile == nil else { return }

        if let defaultProfile = profiles.first(where: { $0.isDefault }) {
            setActiveProfile(defaultProfile)
        } else if let firstProfile = profiles.first {
            setActiveProfile(firstProfile)
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
        if migratingFromLegacy {
            NSLog("[ProfileManager] Migrating config from legacy location: \(legacyConfigURL.path)")
        }

        do {
            let data = try Data(contentsOf: urlToLoad)
            
            let config = try ProfileConfigurationCodec.decode(from: data)
            var didMigrate = false

            let (migratedProfiles, migratedTouchpadSettings) = migrateTouchpadSettingsIfNeeded(in: config.profiles)
            didMigrate = didMigrate || migratedTouchpadSettings
            applyLoadedProfiles(migratedProfiles, activeProfileId: config.activeProfileId)

            if let scale = config.uiScale {
                self.uiScale = scale
            }

            // Migrate legacy global keyboard settings into profiles
            if let legacyKeyboardSettings = config.onScreenKeyboardSettings {
                didMigrate = didMigrate || migrateLegacyKeyboardSettings(legacyKeyboardSettings)
            }

            loadSucceeded = true  // Mark that we successfully loaded the config

            // Save to new location if migrating from legacy or if data migrations occurred
            if migratingFromLegacy || didMigrate {
                saveConfiguration()
                if migratingFromLegacy {
                    NSLog("[ProfileManager] Config migrated to new location: \(configURL.path)")
                }
            }
        } catch {
            NSLog("[ProfileManager] Configuration load failed: \(error)")
            // DO NOT set loadSucceeded = true, so we won't overwrite corrupted/incompatible config
        }
    }

    private func migrateTouchpadSettingsIfNeeded(in profiles: [Profile]) -> ([Profile], Bool) {
        var didMigrate = false
        let migratedProfiles = profiles.map { profile in
            var updated = profile
            if updated.joystickSettings.touchpadSensitivity == 0.8 &&
                updated.joystickSettings.touchpadAcceleration == 0.9 &&
                updated.joystickSettings.touchpadDeadzone == 0.0 &&
                updated.joystickSettings.touchpadSmoothing == 0.4 {
                updated.joystickSettings.touchpadSensitivity = 0.5
                updated.joystickSettings.touchpadAcceleration = 0.5
                didMigrate = true
            } else if updated.joystickSettings.touchpadSensitivity == 0.5 &&
                        updated.joystickSettings.touchpadAcceleration == 0.5 &&
                        updated.joystickSettings.touchpadDeadzone == 0.01 &&
                        updated.joystickSettings.touchpadSmoothing == 0.4 {
                updated.joystickSettings.touchpadDeadzone = 0.0
                didMigrate = true
            }
            return updated
        }
        return (migratedProfiles, didMigrate)
    }

    private func applyLoadedProfiles(_ loadedProfiles: [Profile], activeProfileId: UUID?) {
        let validProfiles = loadedProfiles.filter { $0.isValid() }
        guard !validProfiles.isEmpty else { return }

        self.profiles = validProfiles.sorted { $0.createdAt < $1.createdAt }

        if let activeProfileId,
           let profile = profiles.first(where: { $0.id == activeProfileId }) {
            self.activeProfile = profile
            self.activeProfileId = activeProfileId
        } else {
            self.activeProfile = nil
            self.activeProfileId = nil
        }
    }

    private func migrateLegacyKeyboardSettings(_ legacyKeyboardSettings: OnScreenKeyboardSettings) -> Bool {
        for i in 0..<self.profiles.count {
            if self.profiles[i].onScreenKeyboardSettings.quickTexts.isEmpty &&
               self.profiles[i].onScreenKeyboardSettings.toggleShortcutKeyCode == nil {
                self.profiles[i].onScreenKeyboardSettings = legacyKeyboardSettings
            }
        }

        if let activeId = self.activeProfileId,
           let profile = self.profiles.first(where: { $0.id == activeId }) {
            self.activeProfile = profile
        }

        // Preserve existing behavior: treat presence of legacy field as migration work.
        return true
    }

    private func saveConfiguration() {
        // Safety check: don't save if load failed (to avoid clobbering existing config)
        guard loadSucceeded || !fileManager.fileExists(atPath: configURL.path) else {
            NSLog("[ProfileManager] Skipping save - config load failed earlier, refusing to clobber existing config")
            return
        }

        // Capture state for background save
        let config = ProfileConfiguration(
            profiles: profiles,
            activeProfileId: activeProfileId,
            uiScale: uiScale
        )
        let configURL = self.configURL
        let backupService = ConfigBackupService(fileManager: self.fileManager)

        // Perform file I/O on background thread to avoid blocking main thread
        DispatchQueue.global(qos: .utility).async {
            // Create backup before saving
            backupService.createBackupIfNeeded(for: configURL)

            do {
                let data = try ProfileConfigurationCodec.encode(config)
                try data.write(to: configURL)
            } catch {
                // Configuration save failed silently
            }
        }
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
