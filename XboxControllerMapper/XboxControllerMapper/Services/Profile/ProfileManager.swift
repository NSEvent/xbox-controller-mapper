import Foundation
import Combine
import SwiftUI
import TriggerKitCore
import TriggerKitLibrary

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

    /// Bumped each time a snapshot is written. Lets the History tab refresh
    /// reactively while it's visible (the alternative is polling the snapshot
    /// directory on every render, which costs file I/O per redraw).
    @Published private(set) var snapshotsRevision: Int = 0

    /// Macros in the shared TriggerKit library (TriggerKit.app, Plaque, and
    /// Tardy share the same store). Refreshed on store change notifications,
    /// including distributed ones from other apps' processes.
    @Published private(set) var sharedLibraryMacros: [TriggerKitCore.AutomationMacro] = []

    var onScreenKeyboardSettings: OnScreenKeyboardSettings {
	guard let activeProfile else { return OnScreenKeyboardSettings() }
	return resolvedOnScreenKeyboardSettings(for: activeProfile)
    }

    /// Shared TriggerKit macro library. Bindings whose `macroId` isn't a
    /// profile macro resolve against this store (with the profile's
    /// `sharedMacroSnapshots` as the deletion fallback).
    let sharedMacroStore: AutomationMacroStore

    private let fileManager = FileManager.default
    private let configurationSaveService: ProfileConfigurationSaveService
    private let snapshotService: SnapshotService
    private let configURL: URL
    private let legacyConfigURLs: [URL]
    /// Tracks if config load succeeded to prevent clobbering on save.
    /// Thread-safe: only accessed from @MainActor context (all callers are @MainActor-isolated).
    private var loadSucceeded = false
    
    // Track previous app for restoration logic
    private var previousBundleId: String?
    private var profileIdBeforeBackground: UUID?
    private var currentControllerIdentity: ControllerIdentity?
    
    private var cancellables = Set<AnyCancellable>()

    init(
        appMonitor: AppMonitor? = nil,
        configDirectoryOverride: URL? = nil,
        sharedMacroStore: AutomationMacroStore = .shared
    ) {
        self.sharedMacroStore = sharedMacroStore
        let configPaths = ProfileConfigPathResolver.resolve(
            fileManager: fileManager,
            configDirectoryOverride: configDirectoryOverride
        )
        configurationSaveService = ProfileConfigurationSaveService(fileManager: fileManager)
        snapshotService = SnapshotService(
            snapshotsDirectory: configPaths.configDirectory.appendingPathComponent("snapshots", isDirectory: true),
            fileManager: fileManager
        )
        configURL = configPaths.configURL
	legacyConfigURLs = configPaths.legacyConfigURLs
        createDirectoryIfNeeded(at: configPaths.configDirectory)

        loadConfiguration()
        loadCachedFavicons()
        ensureActiveProfileSelection()
        setupSharedMacroLibraryObservation()
        
        // Initialize state for app switching
        self.previousBundleId = Bundle.main.bundleIdentifier
        self.profileIdBeforeBackground = activeProfileId
        
        if let appMonitor = appMonitor {
            setupAutoSwitching(with: appMonitor)
        }
    }
    
    private func setupSharedMacroLibraryObservation() {
        sharedLibraryMacros = sharedMacroStore.all()

        let refresh: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sharedLibraryMacros = self.sharedMacroStore.all()
            }
        }
        NotificationCenter.default
            .publisher(for: .triggerKitMacrosChanged)
            .sink(receiveValue: refresh)
            .store(in: &cancellables)
        // Edits made in TriggerKit.app / Plaque / Tardy arrive via the
        // distributed center; the store reloads lazily, so re-read from disk.
        DistributedNotificationCenter.default()
            .publisher(for: .triggerKitMacrosChanged)
            .sink { [weak self] notification in
                guard let self else { return }
                Task { @MainActor in
                    self.sharedMacroStore.reloadFromDisk()
                    self.sharedLibraryMacros = self.sharedMacroStore.all()
                }
            }
            .store(in: &cancellables)
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

    func setupControllerAutoSwitching(with controllerService: ControllerService) {
        controllerService.$currentControllerIdentity
            .removeDuplicates()
            .sink { [weak self] identity in
                guard let self = self else { return }
                self.currentControllerIdentity = identity
                guard identity != nil,
                      let bundleId = self.previousBundleId else { return }
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
            state: state,
            controllerIdentity: currentControllerIdentity
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
        case .linkedController(let displayName):
            print("🔄 Auto-switching to profile: \(profile.name) for controller: \(displayName)")
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
		onScreenKeyboardSettings: onScreenKeyboardSettings
            )
        }

        profiles.append(newProfile)
        saveConfiguration()
        return newProfile
    }

    func deleteProfile(_ profile: Profile) {
        // Don't delete the last profile
        guard profiles.count > 1 else { return }

        snapshotCurrentState(reason: "Before deleting '\(profile.name)'")
        let deletedProfileId = profile.id
        profiles.removeAll { $0.id == deletedProfileId }
        clearOnScreenKeyboardInheritanceReferences(to: deletedProfileId)
        saveConfiguration()

        // If we deleted the active profile, switch to another
        if activeProfileId == deletedProfileId {
            if let firstProfile = profiles.first {
                setActiveProfile(firstProfile)
            }
        } else if let activeId = activeProfileId,
                  let updatedActiveProfile = profiles.first(where: { $0.id == activeId }) {
            activeProfile = updatedActiveProfile
        }
    }

    private func clearOnScreenKeyboardInheritanceReferences(to deletedProfileId: UUID) {
        let now = Date()
        for index in profiles.indices where profiles[index].inheritedOnScreenKeyboardProfileId == deletedProfileId {
            profiles[index].inheritedOnScreenKeyboardProfileId = nil
            profiles[index].modifiedAt = now
        }
    }

    func duplicateProfile(_ profile: Profile) -> Profile {
        createProfile(name: "\(profile.name) Copy", basedOn: profile)
    }

    func updateProfile(_ profile: Profile) {
        var updatedProfile = profile
        updatedProfile.modifiedAt = Date()
        updatedProfile.sharedMacroSnapshots = SharedMacroSnapshotPolicy.syncedSnapshots(
            for: updatedProfile,
            store: sharedMacroStore
        )

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = updatedProfile
        }

        saveConfiguration()

        if activeProfileId == profile.id {
            activeProfile = updatedProfile
        }
    }

    func setActiveProfile(_ profile: Profile) {
        if !profiles.contains(where: { $0.id == profile.id }) {
            profiles.append(profile)
        }
        // Update both properties atomically: set activeProfileId first so that
        // when activeProfile's @Published triggers objectWillChange, any
        // downstream reader that also reads activeProfileId sees the new value.
        activeProfileId = profile.id
        activeProfile = profile
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

    /// Sets the stick mode for one side at the given scope.
    /// - Parameter layerId: When nil, writes the profile-level default (i.e. `JoystickSettings.leftStickMode`/`rightStickMode`).
    ///   When non-nil, writes that layer's per-side override. Pass `mode = nil` together with a layer id to clear the override
    ///   so the layer falls back to the profile default.
    func setStickMode(_ mode: StickMode?, side: JoystickSide, layerId: UUID?, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        if let layerId {
            guard let layerIndex = targetProfile.layers.firstIndex(where: { $0.id == layerId }) else { return }
            switch side {
            case .left:
                targetProfile.layers[layerIndex].leftStickModeOverride = mode
            case .right:
                targetProfile.layers[layerIndex].rightStickModeOverride = mode
            }
        } else {
            // Profile-level write: a nil mode is meaningless here (the profile always has a concrete mode),
            // so callers must pass a real StickMode for layer-id-less writes.
            guard let mode else { return }
            switch side {
            case .left:
                targetProfile.joystickSettings.leftStickMode = mode
            case .right:
                targetProfile.joystickSettings.rightStickMode = mode
            }
        }
        updateProfile(targetProfile)
    }

    // MARK: - DualSense LED Settings

    func updateDualSenseLEDSettings(_ settings: DualSenseLEDSettings, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.dualSenseLEDSettings = settings
        updateProfile(targetProfile)
    }

    // MARK: - Touchpad Region Mappings

    func updateTouchpadRegionMappings(_ mappings: [TouchpadRegionMapping], in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.touchpadRegionMappings = mappings
        updateProfile(targetProfile)
    }

    // MARK: - Persistence
    private func loadConfiguration() {
        guard let loadSource = ProfileConfigLoadSourceResolver.resolve(
            fileManager: fileManager,
            configURL: configURL,
	    legacyConfigURLs: legacyConfigURLs
        ) else {
            return
        }

        let urlToLoad = loadSource.url
        let migratingFromLegacy = loadSource.migratingFromLegacy
        if let preLoadLog = ProfileConfigurationPostLoadPolicy.preLoadLogMessage(
            migratingFromLegacy: migratingFromLegacy,
	    legacyConfigURL: urlToLoad
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
        // Set activeProfileId before activeProfile to avoid transient desync
        self.activeProfileId = state.activeProfileId
        self.activeProfile = state.activeProfile
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

        // Validate activeProfileId: if it references a profile that doesn't exist
        // in the profiles array, fall back to the first profile's id (or nil).
        var validatedActiveProfileId = activeProfileId
        if let id = validatedActiveProfileId, !profiles.contains(where: { $0.id == id }) {
            NSLog("[ProfileManager] ⚠️ activeProfileId %@ is orphaned — falling back to first profile", id.uuidString)
            validatedActiveProfileId = profiles.first?.id
            activeProfileId = validatedActiveProfileId
            activeProfile = profiles.first
        }

        // Snapshot captured here on @MainActor BEFORE dispatching to the serial save queue.
        // This guarantees each save gets the state at the time it was requested,
        // and the serial queue guarantees they are written in order (fixes Issue 5 & 13).
        let config = ProfileConfiguration(
            profiles: profiles,
            activeProfileId: validatedActiveProfileId,
            uiScale: uiScale
        )
        configurationSaveService.save(config, to: configURL)
    }

    /// Blocks until all queued configuration saves have hit disk. Called from
    /// applicationWillTerminate — saves are async on a utility queue, so an
    /// edit made just before quitting would otherwise be silently dropped.
    func flushPendingSaves() {
        configurationSaveService.flushPendingWrites()
    }

    /// Current in-memory state encoded as `ProfileConfiguration`. Used by both
    /// the save path and the snapshot path so they capture the same shape.
    private func currentConfiguration() -> ProfileConfiguration {
        ProfileConfiguration(
            profiles: profiles,
            activeProfileId: activeProfileId,
            uiScale: uiScale
        )
    }

    // MARK: - Snapshots (Memento)

    /// Snapshots the current configuration with a human-readable reason. Called
    /// before destructive operations so the user can roll back via the Settings UI.
    /// Best-effort: failures are logged but don't block the caller.
    private func snapshotCurrentState(reason: String) {
        snapshotService.writeSnapshot(currentConfiguration(), reason: reason)
        // Bump unconditionally — even if the write failed, a re-render is
        // cheap and any observer that re-reads availableSnapshots() will see
        // accurate state. Avoids returning a Bool from writeSnapshot just to
        // gate this.
        snapshotsRevision &+= 1
    }

    /// All available snapshots, newest first.
    func availableSnapshots() -> [ProfileSnapshot] {
        snapshotService.listSnapshots()
    }

    /// Restore profile state from a snapshot. Captures the pre-restore state as
    /// its own snapshot first, so the restore itself is undoable.
    /// Returns true on success; logs and returns false on failure.
    @discardableResult
    func restoreSnapshot(_ snapshot: ProfileSnapshot) -> Bool {
        // Load the target snapshot file BEFORE writing the pre-restore
        // checkpoint. The checkpoint write triggers retention-cap pruning, and
        // if `snapshot` is the oldest retained file, that pruning would delete
        // the very file we're about to read. Loading first means the data is
        // safely in memory before any pruning runs.
        let restoredConfig: ProfileConfiguration
        do {
            restoredConfig = try snapshotService.loadConfiguration(from: snapshot)
        } catch {
            NSLog("[ProfileManager] ⚠️ Failed to load snapshot %@: %@", snapshot.id, error.localizedDescription)
            return false
        }

        snapshotCurrentState(reason: "Before restoring snapshot from \(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))")

        // Run snapshot through the same validation pipeline as a fresh load so
        // invalid profiles are dropped and active-profile resolution stays consistent.
        guard let applied = ProfileLoadedDataApplicator.apply(
            loadedProfiles: restoredConfig.profiles,
            activeProfileId: restoredConfig.activeProfileId
        ) else {
            NSLog("[ProfileManager] ⚠️ Snapshot %@ contained no valid profiles — restore aborted", snapshot.id)
            return false
        }

        applyLoadedState(ProfileConfigurationApplyState(
            profiles: applied.profiles,
            activeProfile: applied.activeProfile,
            activeProfileId: applied.activeProfileId,
            uiScale: restoredConfig.uiScale ?? uiScale
        ))
        saveConfiguration()
        return true
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

    /// Fetches the setup guide markdown sidecar for a profile, if one exists.
    nonisolated func fetchSetupGuideForPreview(profileURL urlString: String) async throws -> String? {
        try await CommunityProfileClient.fetchSetupGuide(forProfileURL: urlString)
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
        snapshotCurrentState(reason: "Before importing '\(profile.name)'")
        profiles.append(profile)
        saveConfiguration()
        return profile
    }
}
