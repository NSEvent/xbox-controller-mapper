import Foundation

/// Decides when to show the one-time "leave a review" nudge to a licensed user.
///
/// The rules are deliberately conservative so a paying customer sees the prompt
/// at most twice, only after they've lived with the app for a while:
///
/// - The clock starts the first time the app observes a **licensed** launch
///   (`reviewRequestFirstLicensedSeen`). Trial users never start it.
/// - The prompt appears once at least `minLicensedDays` (7) have passed since
///   that first licensed sighting and it has never been shown.
/// - "Not Now" defers the re-ask by `deferDays` (30). A second "Not Now",
///   "Don't Ask Again", or "Leave a Review" ends the sequence permanently
///   (`reviewRequestCompleted`).
///
/// All state lives in `UserDefaults`; the date source and store are injectable
/// so the state machine is unit-testable without touching real defaults or the
/// wall clock. In test / screenshot runs the manager is inert (mirrors the
/// guards in `LicenseManager`), so the nudge never fires during CI or marketing
/// captures.
final class ReviewRequestManager {
    static let shared = ReviewRequestManager()

    /// User's choice on the prompt.
    enum Outcome {
        case leaveReview
        case notNow
        case dontAskAgain
    }

    enum Keys {
        static let firstLicensedSeen = "reviewRequestFirstLicensedSeen"
        static let shownCount = "reviewRequestShownCount"
        static let deferredUntil = "reviewRequestDeferredUntil"
        static let completed = "reviewRequestCompleted"
    }

    /// Days a user must be licensed before the first prompt.
    static let minLicensedDays = 7
    /// Days a "Not Now" pushes the re-ask out.
    static let deferDays = 30
    /// Total number of times the prompt may ever be shown (initial + one re-ask).
    static let maxPrompts = 2

    private let defaults: UserDefaults
    private let now: () -> Date
    /// When true the manager is fully inert (records nothing, never prompts).
    private let isDisabled: Bool

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        isDisabled: Bool = AppRuntime.isRunningTests || AppRuntime.screenshotVariant != nil
    ) {
        self.defaults = defaults
        self.now = now
        self.isDisabled = isDisabled
    }

    // MARK: - Public API

    /// Records the first licensed sighting (if not already) and returns whether
    /// the review prompt should be shown right now. Call on a licensed launch
    /// once the caller has confirmed the app is licensed.
    @discardableResult
    func evaluateForLicensedLaunch() -> Bool {
        recordLicensedSightingIfNeeded()
        return shouldRequestReview()
    }

    /// Persists the first time a licensed launch is observed. No-op afterward,
    /// so the 7-day clock is anchored to the earliest licensed sighting.
    func recordLicensedSightingIfNeeded() {
        guard !isDisabled, !completed else { return }
        if firstLicensedSeen == nil {
            firstLicensedSeen = now()
        }
    }

    /// Whether the one-time review prompt is due. Assumes the caller has already
    /// confirmed the app is licensed.
    func shouldRequestReview() -> Bool {
        guard !isDisabled, !completed else { return false }
        guard shownCount < Self.maxPrompts else { return false }
        guard let firstSeen = firstLicensedSeen else { return false }
        // A deferral from a prior "Not Now" must elapse first.
        if let deferredUntil, now() < deferredUntil { return false }
        let elapsed = now().timeIntervalSince(firstSeen)
        return elapsed >= Double(Self.minLicensedDays) * 86_400
    }

    /// Call exactly once when the sheet is presented.
    func markShown() {
        guard !isDisabled else { return }
        shownCount += 1
    }

    /// Applies the user's choice to the persisted state.
    func apply(_ outcome: Outcome) {
        guard !isDisabled else { return }
        switch outcome {
        case .leaveReview, .dontAskAgain:
            completed = true
        case .notNow:
            // The last allowed prompt was just dismissed → stop for good.
            // Otherwise push the re-ask out by the defer window.
            if shownCount >= Self.maxPrompts {
                completed = true
            } else {
                deferredUntil = now().addingTimeInterval(Double(Self.deferDays) * 86_400)
            }
        }
    }

    // MARK: - Persisted state

    private var firstLicensedSeen: Date? {
        get { date(forKey: Keys.firstLicensedSeen) }
        set { setDate(newValue, forKey: Keys.firstLicensedSeen) }
    }

    private var deferredUntil: Date? {
        get { date(forKey: Keys.deferredUntil) }
        set { setDate(newValue, forKey: Keys.deferredUntil) }
    }

    private var shownCount: Int {
        get { defaults.integer(forKey: Keys.shownCount) }
        set { defaults.set(newValue, forKey: Keys.shownCount) }
    }

    private var completed: Bool {
        get { defaults.bool(forKey: Keys.completed) }
        set { defaults.set(newValue, forKey: Keys.completed) }
    }

    // MARK: - Date storage helpers

    // Stored as timeIntervalSinceReferenceDate so an absent key reads back as
    // nil (rather than the epoch) via the object-presence check.
    private func date(forKey key: String) -> Date? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSinceReferenceDate: defaults.double(forKey: key))
    }

    private func setDate(_ date: Date?, forKey key: String) {
        if let date {
            defaults.set(date.timeIntervalSinceReferenceDate, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
