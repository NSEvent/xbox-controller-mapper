import Foundation
import Combine

/// Tracks and persists controller usage statistics
class UsageStatsService: ObservableObject {
    struct Timing {
        let saveDelaySeconds: TimeInterval
        let publishDelaySeconds: TimeInterval

        static let `default` = Timing(
            saveDelaySeconds: 30,
            publishDelaySeconds: 0.25
        )
    }

    @Published private(set) var stats: UsageStats

    private let lock = NSLock()
    private let statsFileURL: URL
    private let timing: Timing
    private let backgroundQueue: DispatchQueue
    private let now: () -> Date

    private var workingStats: UsageStats
    private var isDirty = false
    private var isPublishScheduled = false
    private var saveWorkItem: DispatchWorkItem?
    private var publishWorkItem: DispatchWorkItem?
    private var sessionStartDate: Date?

    private static let statsDirectory: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".controllerkeys")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let defaultStatsFileURL: URL = {
        statsDirectory.appendingPathComponent("stats.json")
    }()

    init(
        statsFileURL: URL? = nil,
        timing: Timing = .default,
        backgroundQueue: DispatchQueue = DispatchQueue.global(qos: .utility),
        now: @escaping () -> Date = Date.init
    ) {
        self.statsFileURL = statsFileURL ?? Self.defaultStatsFileURL
        self.timing = timing
        self.backgroundQueue = backgroundQueue
        self.now = now

        let loaded = Self.loadFromDisk(at: self.statsFileURL)
        self.stats = loaded
        self.workingStats = loaded
        startSession()
    }

    // MARK: - Recording (called from background inputQueue)

    /// Record a button press. Thread-safe via NSLock.
    func record(button: ControllerButton, type: InputEventType) {
        mutateStats { stats in
            stats.buttonCounts[button.rawValue, default: 0] += 1
            stats.actionTypeCounts[type.rawValue, default: 0] += 1
        }
    }

    /// Record a chord press (multiple buttons). Thread-safe.
    func recordChord(buttons: [ControllerButton], type: InputEventType) {
        mutateStats { stats in
            for button in buttons {
                stats.buttonCounts[button.rawValue, default: 0] += 1
            }
            stats.actionTypeCounts[type.rawValue, default: 0] += 1
        }
    }

    // MARK: - Output Action Recording

    /// Record a keyboard key press action.
    func recordKeyPress() {
        mutateStats { $0.keyPresses += 1 }
    }

    /// Record a mouse click action.
    func recordMouseClick() {
        mutateStats { $0.mouseClicks += 1 }
    }

    /// Record a macro execution with its step count.
    func recordMacro(stepCount: Int) {
        mutateStats { stats in
            stats.macrosExecuted += 1
            stats.macroStepsAutomated += stepCount
        }
    }

    /// Record a webhook/HTTP request.
    func recordWebhook() {
        mutateStats { $0.webhooksFired += 1 }
    }

    /// Record an app launch.
    func recordAppLaunch() {
        mutateStats { $0.appsLaunched += 1 }
    }

    /// Record a text snippet execution.
    func recordTextSnippet() {
        mutateStats { $0.textSnippetsRun += 1 }
    }

    /// Record a terminal command execution.
    func recordTerminalCommand() {
        mutateStats { $0.terminalCommandsRun += 1 }
    }

    /// Record a link/URL opened.
    func recordLinkOpened() {
        mutateStats { $0.linksOpened += 1 }
    }

    // MARK: - Distance Recording (called from 120Hz polling)

    /// Accumulate mouse distance from joystick input. Called at 120Hz.
    func recordJoystickMouseDistance(dx: Double, dy: Double) {
        recordDistance(dx: dx, dy: dy) { stats, distance in
            stats.joystickMousePixels += distance
        }
    }

    /// Accumulate mouse distance from touchpad input.
    func recordTouchpadMouseDistance(dx: Double, dy: Double) {
        recordDistance(dx: dx, dy: dy) { stats, distance in
            stats.touchpadMousePixels += distance
        }
    }

    /// Accumulate scroll distance.
    func recordScrollDistance(dx: Double, dy: Double) {
        recordDistance(dx: dx, dy: dy) { stats, distance in
            stats.scrollPixels += distance
        }
    }

    // MARK: - Session Tracking

    func startSession() {
        let currentDate = now()
        sessionStartDate = currentDate
        mutateStats { stats in
            if stats.firstSessionDate == nil {
                stats.firstSessionDate = currentDate
            }
            stats.totalSessions += 1
            updateStreak(&stats, currentDate: currentDate)
        }
    }

    func endSession() {
        guard let start = sessionStartDate else { return }
        let currentDate = now()
        let duration = currentDate.timeIntervalSince(start)
        sessionStartDate = nil
        mutateStats { stats in
            stats.totalSessionSeconds += duration
            stats.lastSessionDate = currentDate
        }

        // Save immediately on session end
        saveNow()
    }

    // MARK: - Streak Logic

    private func updateStreak(_ stats: inout UsageStats, currentDate: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: currentDate)

        guard let lastDate = stats.lastSessionDate else {
            // First ever session
            stats.currentStreakDays = 1
            stats.longestStreakDays = 1
            stats.lastSessionDate = currentDate
            return
        }

        let lastDay = calendar.startOfDay(for: lastDate)
        let daysSince = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

        if daysSince == 0 {
            // Same day, streak unchanged
        } else if daysSince == 1 {
            // Consecutive day
            stats.currentStreakDays += 1
            stats.longestStreakDays = max(stats.longestStreakDays, stats.currentStreakDays)
        } else {
            // Streak broken
            stats.currentStreakDays = 1
        }
        stats.lastSessionDate = currentDate
    }

    // MARK: - Persistence

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func recordDistance(dx: Double, dy: Double, apply: (inout UsageStats, Double) -> Void) {
        let distance = hypot(dx, dy)
        guard distance > 0 else { return }
        mutateStats { stats in
            apply(&stats, distance)
        }
    }

    private func mutateStats(_ mutation: (inout UsageStats) -> Void) {
        let (shouldScheduleSave, shouldSchedulePublish) = withLock {
            mutation(&workingStats)
            let shouldScheduleSave = !isDirty
            let shouldSchedulePublish = !isPublishScheduled
            isDirty = true
            isPublishScheduled = true
            return (shouldScheduleSave, shouldSchedulePublish)
        }

        if shouldScheduleSave {
            scheduleSave()
        }
        if shouldSchedulePublish {
            schedulePublish()
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWorkItem = item
        backgroundQueue.asyncAfter(deadline: .now() + timing.saveDelaySeconds, execute: item)
    }

    private func schedulePublish() {
        publishWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.publishSnapshot()
        }
        publishWorkItem = item
        backgroundQueue.asyncAfter(deadline: .now() + timing.publishDelaySeconds, execute: item)
    }

    private func publishSnapshot() {
        let snapshot = withLock {
            let snapshot = workingStats
            isPublishScheduled = false
            return snapshot
        }

        DispatchQueue.main.async { [weak self] in
            self?.stats = snapshot
        }
    }

    private func saveNow() {
        let snapshot = withLock {
            let snapshot = workingStats
            isDirty = false
            isPublishScheduled = false
            return snapshot
        }
        publishWorkItem?.cancel()
        publishWorkItem = nil

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: statsFileURL, options: .atomic)
        } catch {
            // Silently fail - stats are non-critical
        }

        // Publish on main thread
        DispatchQueue.main.async { [weak self] in
            self?.stats = snapshot
        }
    }

    private static func loadFromDisk(at fileURL: URL) -> UsageStats {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return UsageStats() }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(UsageStats.self, from: data)
        } catch {
            // Start fresh on decode failure
            return UsageStats()
        }
    }
}
