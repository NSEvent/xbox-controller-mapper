import Foundation
import Combine

/// Tracks and persists controller usage statistics
class UsageStatsService: ObservableObject {
    @Published private(set) var stats: UsageStats

    private let lock = NSLock()
    private var workingStats: UsageStats
    private var isDirty = false
    private var isPublishScheduled = false
    private var saveWorkItem: DispatchWorkItem?
    private var publishWorkItem: DispatchWorkItem?
    private var sessionStartDate: Date?
    private static let saveDelaySeconds: TimeInterval = 30
    private static let publishDelaySeconds: TimeInterval = 0.25

    private static let statsDirectory: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".controllerkeys")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let statsFileURL: URL = {
        statsDirectory.appendingPathComponent("stats.json")
    }()

    init() {
        let loaded = Self.loadFromDisk()
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
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }
        mutateStats { $0.joystickMousePixels += dist }
    }

    /// Accumulate mouse distance from touchpad input.
    func recordTouchpadMouseDistance(dx: Double, dy: Double) {
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }
        mutateStats { $0.touchpadMousePixels += dist }
    }

    /// Accumulate scroll distance.
    func recordScrollDistance(dx: Double, dy: Double) {
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }
        mutateStats { $0.scrollPixels += dist }
    }

    // MARK: - Session Tracking

    func startSession() {
        sessionStartDate = Date()
        mutateStats { stats in
            if stats.firstSessionDate == nil {
                stats.firstSessionDate = Date()
            }
            stats.totalSessions += 1
            updateStreak(&stats)
        }
    }

    func endSession() {
        guard let start = sessionStartDate else { return }
        let duration = Date().timeIntervalSince(start)
        sessionStartDate = nil
        mutateStats { stats in
            stats.totalSessionSeconds += duration
            stats.lastSessionDate = Date()
        }

        // Save immediately on session end
        saveNow()
    }

    // MARK: - Streak Logic

    private func updateStreak(_ stats: inout UsageStats) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let lastDate = stats.lastSessionDate else {
            // First ever session
            stats.currentStreakDays = 1
            stats.longestStreakDays = 1
            stats.lastSessionDate = Date()
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
        stats.lastSessionDate = Date()
    }

    // MARK: - Persistence

    private func mutateStats(_ mutation: (inout UsageStats) -> Void) {
        lock.lock()
        mutation(&workingStats)
        let shouldScheduleSave = !isDirty
        let shouldSchedulePublish = !isPublishScheduled
        isDirty = true
        isPublishScheduled = true
        lock.unlock()

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
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.saveDelaySeconds, execute: item)
    }

    private func schedulePublish() {
        publishWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.publishSnapshot()
        }
        publishWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.publishDelaySeconds, execute: item)
    }

    private func publishSnapshot() {
        lock.lock()
        let snapshot = workingStats
        isPublishScheduled = false
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.stats = snapshot
        }
    }

    private func saveNow() {
        lock.lock()
        let snapshot = workingStats
        isDirty = false
        isPublishScheduled = false
        lock.unlock()
        publishWorkItem?.cancel()
        publishWorkItem = nil

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: Self.statsFileURL, options: .atomic)
        } catch {
            // Silently fail - stats are non-critical
        }

        // Publish on main thread
        DispatchQueue.main.async { [weak self] in
            self?.stats = snapshot
        }
    }

    private static func loadFromDisk() -> UsageStats {
        guard FileManager.default.fileExists(atPath: Self.statsFileURL.path) else { return UsageStats() }
        do {
            let data = try Data(contentsOf: Self.statsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(UsageStats.self, from: data)
        } catch {
            // Start fresh on decode failure
            return UsageStats()
        }
    }
}
