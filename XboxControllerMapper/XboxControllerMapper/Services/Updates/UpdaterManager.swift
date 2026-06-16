import Foundation
import SwiftUI
import Combine
import Sparkle

/// Wraps Sparkle's standard updater so SwiftUI can drive "Check for Updates"
/// and reflect whether a check is currently allowed.
///
/// Configuration lives in Info.plist (`SUFeedURL`, `SUPublicEDKey`,
/// `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`). The updater is
/// started explicitly from the app at launch so screenshot/test runs can skip
/// it (no network, deterministic captures).
@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    private var updaterController: SPUStandardUpdaterController?

    /// Mirrors Sparkle's `canCheckForUpdates` so the menu/button can disable
    /// itself while a check is already in flight.
    @Published private(set) var canCheckForUpdates = false

    private init() {}

    /// Begins Sparkle's scheduled-update lifecycle. Safe to call more than once.
    func start() {
        guard updaterController == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
        updaterController = controller
    }

    /// Triggers a user-initiated update check (shows Sparkle's UI).
    func checkForUpdates() {
        updaterController?.updater.checkForUpdates()
    }
}
