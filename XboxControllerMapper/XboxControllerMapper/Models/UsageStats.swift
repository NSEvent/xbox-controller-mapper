import Foundation

/// Persistent usage statistics tracked across all profiles
struct UsageStats: Codable {
    var buttonCounts: [String: Int] = [:]  // ControllerButton.rawValue -> count
    var actionTypeCounts: [String: Int] = [:]  // InputEventType.rawValue -> count
    var totalSessions: Int = 0
    var totalSessionSeconds: Double = 0
    var currentStreakDays: Int = 0
    var longestStreakDays: Int = 0
    var lastSessionDate: Date?
    var firstSessionDate: Date?

    // MARK: - Computed Properties

    var totalPresses: Int {
        buttonCounts.values.reduce(0, +)
    }

    /// Top buttons sorted by count descending
    var topButtons: [(button: ControllerButton, count: Int)] {
        buttonCounts.compactMap { key, count in
            guard let button = ControllerButton(rawValue: key) else { return nil }
            return (button, count)
        }
        .sorted { $0.count > $1.count }
    }

    /// Average session duration in seconds
    var averageSessionSeconds: Double {
        guard totalSessions > 0 else { return 0 }
        return totalSessionSeconds / Double(totalSessions)
    }

    /// Distribution of button presses by category
    var categoryDistribution: [ButtonCategory: Int] {
        var result: [ButtonCategory: Int] = [:]
        for (key, count) in buttonCounts {
            guard let button = ControllerButton(rawValue: key) else { continue }
            result[button.category, default: 0] += count
        }
        return result
    }

    /// Distribution of action types (single press, chord, double tap, etc.)
    var actionTypeDistribution: [String: Int] {
        actionTypeCounts
    }

    /// Fraction of presses that are "complex" (chords, double taps, long presses)
    var complexActionRatio: Double {
        let total = actionTypeCounts.values.reduce(0, +)
        guard total > 0 else { return 0 }
        let complex = (actionTypeCounts[InputEventType.chord.rawValue] ?? 0)
            + (actionTypeCounts[InputEventType.doubleTap.rawValue] ?? 0)
            + (actionTypeCounts[InputEventType.longPress.rawValue] ?? 0)
        return Double(complex) / Double(total)
    }

    /// Determine the user's controller personality
    var personality: ControllerPersonality {
        let total = totalPresses
        guard total >= 10 else { return .minimalist }

        let dist = categoryDistribution
        let totalCat = dist.values.reduce(0, +)
        guard totalCat > 0 else { return .minimalist }

        // Check complex action ratio first
        if complexActionRatio > 0.30 {
            return .strategist
        }

        // Check if any single category dominates > 40%
        let fractions = dist.mapValues { Double($0) / Double(totalCat) }

        let triggerFrac = fractions[.trigger, default: 0]
        let faceFrac = fractions[.face, default: 0]
        let dpadFrac = fractions[.dpad, default: 0]
        let bumperFrac = fractions[.bumper, default: 0]

        // Check if no single category > 40% → Multitasker
        let maxFrac = fractions.values.max() ?? 0
        if maxFrac < 0.40 {
            return .multitasker
        }

        if triggerFrac > 0.40 { return .sharpshooter }
        if faceFrac > 0.40 { return .brawler }
        if dpadFrac > 0.40 { return .navigator }
        if bumperFrac > 0.40 { return .sharpshooter }

        return .multitasker
    }

    // MARK: - Custom Codable

    enum CodingKeys: String, CodingKey {
        case buttonCounts, actionTypeCounts, totalSessions, totalSessionSeconds
        case currentStreakDays, longestStreakDays, lastSessionDate, firstSessionDate
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        buttonCounts = try container.decodeIfPresent([String: Int].self, forKey: .buttonCounts) ?? [:]
        actionTypeCounts = try container.decodeIfPresent([String: Int].self, forKey: .actionTypeCounts) ?? [:]
        totalSessions = try container.decodeIfPresent(Int.self, forKey: .totalSessions) ?? 0
        totalSessionSeconds = try container.decodeIfPresent(Double.self, forKey: .totalSessionSeconds) ?? 0
        currentStreakDays = try container.decodeIfPresent(Int.self, forKey: .currentStreakDays) ?? 0
        longestStreakDays = try container.decodeIfPresent(Int.self, forKey: .longestStreakDays) ?? 0
        lastSessionDate = try container.decodeIfPresent(Date.self, forKey: .lastSessionDate)
        firstSessionDate = try container.decodeIfPresent(Date.self, forKey: .firstSessionDate)
    }
}
