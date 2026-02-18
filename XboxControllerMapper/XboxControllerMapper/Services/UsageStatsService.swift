import Foundation
import Combine

/// Tracks and persists controller usage statistics
class UsageStatsService: ObservableObject {
    @Published var stats: UsageStats = UsageStats()

    private let lock = NSLock()
    private var isDirty = false
    private var saveWorkItem: DispatchWorkItem?
    private var sessionStartDate: Date?

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
        load()
        startSession()
    }

    // MARK: - Recording (called from background inputQueue)

    /// Record a button press. Thread-safe via NSLock.
    func record(button: ControllerButton, type: InputEventType) {
        lock.lock()
        stats.buttonCounts[button.rawValue, default: 0] += 1
        stats.actionTypeCounts[type.rawValue, default: 0] += 1
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()

        if shouldSchedule {
            scheduleSave()
        }
    }

    /// Record a chord press (multiple buttons). Thread-safe.
    func recordChord(buttons: [ControllerButton], type: InputEventType) {
        lock.lock()
        for button in buttons {
            stats.buttonCounts[button.rawValue, default: 0] += 1
        }
        stats.actionTypeCounts[type.rawValue, default: 0] += 1
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()

        if shouldSchedule {
            scheduleSave()
        }
    }

    // MARK: - Output Action Recording

    /// Record a keyboard key press action.
    func recordKeyPress() {
        lock.lock()
        stats.keyPresses += 1
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()
        if shouldSchedule { scheduleSave() }
    }

    /// Record a mouse click action.
    func recordMouseClick() {
        lock.lock()
        stats.mouseClicks += 1
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()
        if shouldSchedule { scheduleSave() }
    }

    /// Record a macro execution with its step count.
    func recordMacro(stepCount: Int) {
        lock.lock()
        stats.macrosExecuted += 1
        stats.macroStepsAutomated += stepCount
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()
        if shouldSchedule { scheduleSave() }
    }

    /// Record a webhook/HTTP request.
    func recordWebhook() {
        lock.lock()
        stats.webhooksFired += 1
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()
        if shouldSchedule { scheduleSave() }
    }

    /// Record an app launch.
    func recordAppLaunch() {
        lock.lock()
        stats.appsLaunched += 1
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()
        if shouldSchedule { scheduleSave() }
    }

    /// Record a text snippet execution.
    func recordTextSnippet() {
        lock.lock()
        stats.textSnippetsRun += 1
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()
        if shouldSchedule { scheduleSave() }
    }

    /// Record a terminal command execution.
    func recordTerminalCommand() {
        lock.lock()
        stats.terminalCommandsRun += 1
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()
        if shouldSchedule { scheduleSave() }
    }

    /// Record a link/URL opened.
    func recordLinkOpened() {
        lock.lock()
        stats.linksOpened += 1
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()
        if shouldSchedule { scheduleSave() }
    }

    // MARK: - Distance Recording (called from 120Hz polling)

    /// Accumulate mouse distance from joystick input. Called at 120Hz.
    func recordJoystickMouseDistance(dx: Double, dy: Double) {
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }
        lock.lock()
        stats.joystickMousePixels += dist
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()
        if shouldSchedule { scheduleSave() }
    }

    /// Accumulate mouse distance from touchpad input.
    func recordTouchpadMouseDistance(dx: Double, dy: Double) {
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }
        lock.lock()
        stats.touchpadMousePixels += dist
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()
        if shouldSchedule { scheduleSave() }
    }

    /// Accumulate scroll distance.
    func recordScrollDistance(dx: Double, dy: Double) {
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }
        lock.lock()
        stats.scrollPixels += dist
        let shouldSchedule = !isDirty
        isDirty = true
        lock.unlock()
        if shouldSchedule { scheduleSave() }
    }

    // MARK: - Session Tracking

    func startSession() {
        sessionStartDate = Date()

        lock.lock()
        if stats.firstSessionDate == nil {
            stats.firstSessionDate = Date()
        }
        stats.totalSessions += 1
        updateStreak()
        isDirty = true
        lock.unlock()

        scheduleSave()
    }

    func endSession() {
        guard let start = sessionStartDate else { return }
        let duration = Date().timeIntervalSince(start)
        sessionStartDate = nil

        lock.lock()
        stats.totalSessionSeconds += duration
        stats.lastSessionDate = Date()
        isDirty = true
        lock.unlock()

        // Save immediately on session end
        saveNow()
    }

    // MARK: - Streak Logic

    private func updateStreak() {
        // Must be called while lock is held
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

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: item)
    }

    private func saveNow() {
        lock.lock()
        let snapshot = stats
        isDirty = false
        lock.unlock()

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

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.statsFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.statsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            stats = try decoder.decode(UsageStats.self, from: data)
        } catch {
            // Start fresh on decode failure
            stats = UsageStats()
        }
    }
}
