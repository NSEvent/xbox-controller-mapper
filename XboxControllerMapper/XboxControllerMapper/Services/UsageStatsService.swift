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
