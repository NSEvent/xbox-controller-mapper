import Foundation
import CoreGraphics

/// Pure stateless analysis engine that computes Shannon-optimal binding costs
/// and generates concrete recommendations for improving controller mappings.
struct BindingAnalysisEngine {

    /// Minimum total actions before analysis is meaningful
    static let minimumActions = 50

    /// Minimum uses for an action to be included in the analysis
    static let minimumOccurrences = 3

    // MARK: - Public API

    static func analyze(
        actionDetailCounts: [String: Int],
        profile: Profile
    ) -> BindingAnalysisResult {
        let totalActions = actionDetailCounts.values.reduce(0, +)

        guard totalActions >= minimumActions else {
            return BindingAnalysisResult(
                entries: [],
                recommendations: [],
                efficiencyScore: 1.0,
                totalActions: totalActions,
                hasEnoughData: false
            )
        }

        // Build entries for actions with enough occurrences
        let filteredCounts = actionDetailCounts.filter { $0.value >= minimumOccurrences }

        // Sort by count descending to assign optimal costs
        let sortedByFrequency = filteredCounts.sorted { $0.value > $1.value }

        // Compute available cost slots sorted ascending
        let optimalCosts = availableCostSlots(count: sortedByFrequency.count)

        var entries: [BindingAnalysisEntry] = []
        for (index, item) in sortedByFrequency.enumerated() {
            let probability = Double(item.value) / Double(totalActions)
            let actualCost = inputCost(forActionKey: item.key, profile: profile)
            let optimalCost = index < optimalCosts.count ? optimalCosts[index] : actualCost

            entries.append(BindingAnalysisEntry(
                actionKey: item.key,
                count: item.value,
                probability: probability,
                actualCost: actualCost,
                optimalCost: optimalCost,
                waste: actualCost - optimalCost,
                actionDescription: descriptionForActionKey(item.key, profile: profile)
            ))
        }

        // Generate recommendations
        let rawRecommendations = generateRecommendations(entries: entries, profile: profile)
        let filteredRecommendations = filterConflicting(rawRecommendations)

        // Compute efficiency score
        let efficiency = computeEfficiencyScore(entries: entries)

        return BindingAnalysisResult(
            entries: entries,
            recommendations: filteredRecommendations,
            efficiencyScore: efficiency,
            totalActions: totalActions,
            hasEnoughData: true
        )
    }

    // MARK: - Cost Function

    /// Returns the ergonomic input cost for a given interaction type and button
    static func inputCost(forActionKey actionKey: String, profile: Profile) -> Double {
        let parts = actionKey.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return 1.0 }

        let buttonPart = String(parts[0])
        let typePart = String(parts[1])

        // Check if this is a chord (contains "+")
        if buttonPart.contains("+") {
            return chordCost(buttonPart: buttonPart)
        }

        guard let button = ControllerButton(rawValue: buttonPart) else { return 1.0 }
        return singleButtonCost(button: button, type: typePart)
    }

    /// Cost for a single button interaction
    static func singleButtonCost(button: ControllerButton, type: String) -> Double {
        let baseCost: Double
        switch type {
        case "Press":
            baseCost = 1.0
        case "Double Tap":
            baseCost = 1.5
        case "Long Press":
            baseCost = 2.0
        default:
            baseCost = 1.0
        }

        return baseCost + buttonAdjustment(button)
    }

    /// Additional cost based on button ergonomics
    static func buttonAdjustment(_ button: ControllerButton) -> Double {
        switch button.category {
        case .dpad:
            return 0.1
        case .thumbstick:
            return 0.3
        case .special:
            return 0.4
        case .face, .bumper, .trigger, .touchpad, .paddle:
            return 0.0
        }
    }

    /// Cost for a chord (multi-button press)
    static func chordCost(buttonPart: String) -> Double {
        let buttonNames = buttonPart.split(separator: "+").map { String($0) }
        let buttons = buttonNames.compactMap { ControllerButton(rawValue: $0) }

        guard buttons.count >= 2 else { return 1.0 }

        if buttons.count >= 3 {
            return 2.2
        }

        // 2-button chord: check if cross-hand
        return isCrossHand(buttons[0], buttons[1]) ? 1.3 : 1.8
    }

    /// Cross-hand: one button on bumper/trigger side, other on face/dpad side
    static func isCrossHand(_ a: ControllerButton, _ b: ControllerButton) -> Bool {
        let shoulderCategories: Set<ButtonCategory> = [.bumper, .trigger]
        let faceCategories: Set<ButtonCategory> = [.face, .dpad]

        let aIsShoulder = shoulderCategories.contains(a.category)
        let bIsShoulder = shoulderCategories.contains(b.category)
        let aIsFace = faceCategories.contains(a.category)
        let bIsFace = faceCategories.contains(b.category)

        return (aIsShoulder && bIsFace) || (aIsFace && bIsShoulder)
    }

    // MARK: - Optimal Cost Slots

    /// Returns a sorted array of available cost slots for the given number of actions
    private static func availableCostSlots(count: Int) -> [Double] {
        // Generate a pool of available input costs, sorted ascending
        var slots: [Double] = []

        // Face buttons (4): single press
        for button in [ControllerButton.a, .b, .x, .y] {
            slots.append(singleButtonCost(button: button, type: "Press"))
        }
        // Bumpers (2): single press
        for button in [ControllerButton.leftBumper, .rightBumper] {
            slots.append(singleButtonCost(button: button, type: "Press"))
        }
        // Triggers (2): single press
        for button in [ControllerButton.leftTrigger, .rightTrigger] {
            slots.append(singleButtonCost(button: button, type: "Press"))
        }
        // D-pad (4): single press
        for button in [ControllerButton.dpadUp, .dpadDown, .dpadLeft, .dpadRight] {
            slots.append(singleButtonCost(button: button, type: "Press"))
        }
        // Special (4): single press
        for button in [ControllerButton.menu, .view, .share, .xbox] {
            slots.append(singleButtonCost(button: button, type: "Press"))
        }
        // Cross-hand chords
        for _ in 0..<4 {
            slots.append(1.3)
        }
        // Double taps on face/bumper buttons
        for button in [ControllerButton.a, .b, .x, .y] {
            slots.append(singleButtonCost(button: button, type: "Double Tap"))
        }
        // Same-hand chords
        for _ in 0..<4 {
            slots.append(1.8)
        }
        // Long presses
        for button in [ControllerButton.a, .b, .x, .y] {
            slots.append(singleButtonCost(button: button, type: "Long Press"))
        }
        // 3+ button chords
        for _ in 0..<4 {
            slots.append(2.2)
        }

        slots.sort()
        // Pad if needed
        while slots.count < count {
            slots.append(slots.last ?? 2.5)
        }
        return Array(slots.prefix(count))
    }

    // MARK: - Recommendation Generation

    private static func generateRecommendations(
        entries: [BindingAnalysisEntry],
        profile: Profile
    ) -> [BindingRecommendation] {
        var recommendations: [BindingRecommendation] = []

        recommendations.append(contentsOf: generateSwapRecommendations(entries: entries, profile: profile))
        recommendations.append(contentsOf: generatePromoteRecommendations(entries: entries, profile: profile))
        recommendations.append(contentsOf: generateDemoteRecommendations(entries: entries, profile: profile))

        return recommendations.sorted { $0.priority > $1.priority }
    }

    /// Swap: pair a high-cost frequent action with a low-cost infrequent action
    private static func generateSwapRecommendations(
        entries: [BindingAnalysisEntry],
        profile: Profile
    ) -> [BindingRecommendation] {
        var recommendations: [BindingRecommendation] = []

        // Only consider single-press entries for swaps
        let pressEntries = entries.filter { $0.actionKey.hasSuffix(":Press") }
        guard pressEntries.count >= 2 else { return [] }

        // Find pairs where a frequent action has high cost and infrequent has low cost
        for i in 0..<pressEntries.count {
            for j in (i + 1)..<pressEntries.count {
                let frequent = pressEntries[i]
                let infrequent = pressEntries[j]

                // frequent should have more uses AND higher cost than infrequent
                guard frequent.count > infrequent.count,
                      frequent.actualCost > infrequent.actualCost,
                      frequent.waste > 0.3 else { continue }

                guard let button1 = buttonFromActionKey(frequent.actionKey),
                      let button2 = buttonFromActionKey(infrequent.actionKey) else { continue }

                let priority = abs(frequent.waste - infrequent.waste) * Double(frequent.count)

                recommendations.append(BindingRecommendation(
                    type: .swap(button1: button1, button2: button2),
                    priority: priority,
                    actionDescription1: frequent.actionDescription,
                    actionDescription2: infrequent.actionDescription
                ))
            }
        }

        return recommendations
    }

    /// Promote: frequent long-hold/double-tap → cross-hand chord
    private static func generatePromoteRecommendations(
        entries: [BindingAnalysisEntry],
        profile: Profile
    ) -> [BindingRecommendation] {
        var recommendations: [BindingRecommendation] = []

        let alternateEntries = entries.filter {
            $0.actionKey.hasSuffix(":Long Press") || $0.actionKey.hasSuffix(":Double Tap")
        }

        let chordPartners: [ControllerButton] = [.leftBumper, .rightBumper]

        for entry in alternateEntries {
            guard entry.waste > 0.3,
                  let sourceButton = buttonFromActionKey(entry.actionKey) else { continue }

            let isLongHold = entry.actionKey.hasSuffix(":Long Press")
            let sourceType: PromoteSourceType = isLongHold ? .longHold : .doubleTap

            // Find the mapping to promote
            let keyCode: CGKeyCode?
            let modifiers: ModifierFlags
            if isLongHold, let lh = profile.buttonMappings[sourceButton]?.longHoldMapping {
                keyCode = lh.keyCode
                modifiers = lh.modifiers
            } else if !isLongHold, let dt = profile.buttonMappings[sourceButton]?.doubleTapMapping {
                keyCode = dt.keyCode
                modifiers = dt.modifiers
            } else {
                continue
            }

            // Try to find a free chord slot using LB or RB + source button
            for partner in chordPartners {
                guard partner != sourceButton else { continue }

                let chordButtons: Set<ControllerButton> = [partner, sourceButton]
                let existingConflict = profile.chordMappings.contains { $0.buttons == chordButtons }
                guard !existingConflict else { continue }

                let priority = entry.waste * Double(entry.count)
                let typeLabel = isLongHold ? "long hold" : "double tap"

                recommendations.append(BindingRecommendation(
                    type: .promoteToChord(
                        fromButton: sourceButton,
                        fromType: sourceType,
                        toChordButtons: chordButtons,
                        keyCode: keyCode,
                        modifiers: modifiers
                    ),
                    priority: priority,
                    actionDescription1: entry.actionDescription
                ))
                break // Only suggest one chord option per entry
            }
        }

        return recommendations
    }

    /// Demote: infrequent single-press → long hold (frees the single-press slot)
    private static func generateDemoteRecommendations(
        entries: [BindingAnalysisEntry],
        profile: Profile
    ) -> [BindingRecommendation] {
        var recommendations: [BindingRecommendation] = []

        let pressEntries = entries.filter { $0.actionKey.hasSuffix(":Press") }

        for entry in pressEntries {
            guard entry.waste > 0.5,
                  let button = buttonFromActionKey(entry.actionKey),
                  let mapping = profile.buttonMappings[button],
                  !mapping.isEmpty,
                  mapping.longHoldMapping == nil || mapping.longHoldMapping?.isEmpty == true else { continue }

            let priority = entry.waste * Double(entry.count) * 0.5 // Lower priority than swaps

            recommendations.append(BindingRecommendation(
                type: .demoteToLongHold(button: button, keyCode: mapping.keyCode, modifiers: mapping.modifiers),
                priority: priority,
                actionDescription1: entry.actionDescription
            ))
        }

        return recommendations
    }

    // MARK: - Conflict Filtering

    /// Greedy pass: accept recommendations in priority order, skip conflicting ones
    static func filterConflicting(_ recommendations: [BindingRecommendation]) -> [BindingRecommendation] {
        var accepted: [BindingRecommendation] = []
        var usedButtons: Set<ControllerButton> = []

        for rec in recommendations.sorted(by: { $0.priority > $1.priority }) {
            let buttons = rec.type.involvedButtons
            if buttons.isDisjoint(with: usedButtons) {
                accepted.append(rec)
                usedButtons.formUnion(buttons)
            }
        }

        return accepted
    }

    // MARK: - Efficiency Score

    private static func computeEfficiencyScore(entries: [BindingAnalysisEntry]) -> Double {
        let totalCount = entries.reduce(0) { $0 + $1.count }
        guard totalCount > 0 else { return 1.0 }

        // Weighted average of absolute waste
        let weightedAbsWaste = entries.reduce(0.0) { sum, entry in
            sum + abs(entry.waste) * Double(entry.count)
        }
        let avgAbsWaste = weightedAbsWaste / Double(totalCount)

        // Max possible waste is roughly the difference between cheapest and most expensive inputs
        let maxPossibleWaste = 1.5
        let score = 1.0 - (avgAbsWaste / maxPossibleWaste)
        return max(0.0, min(1.0, score))
    }

    // MARK: - Helpers

    /// Extract the button from an action key like "a:Press" or "leftBumper:Long Press"
    static func buttonFromActionKey(_ actionKey: String) -> ControllerButton? {
        let parts = actionKey.split(separator: ":", maxSplits: 1)
        guard let first = parts.first else { return nil }
        let buttonPart = String(first)
        // Skip chord keys
        guard !buttonPart.contains("+") else { return nil }
        return ControllerButton(rawValue: buttonPart)
    }

    /// Build a human-readable description for an action key using profile mappings
    static func descriptionForActionKey(_ actionKey: String, profile: Profile) -> String {
        let parts = actionKey.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return actionKey }

        let buttonPart = String(parts[0])
        let typePart = String(parts[1])

        // Chord
        if buttonPart.contains("+") {
            let buttonNames = buttonPart.split(separator: "+").map { String($0) }
            let buttons = buttonNames.compactMap { ControllerButton(rawValue: $0) }
            let buttonSet = Set(buttons)
            if let chord = profile.chordMappings.first(where: { $0.buttons == buttonSet }) {
                return chord.hint ?? chord.displayString
            }
            return buttons.map(\.shortLabel).joined(separator: "+") + " chord"
        }

        // Single button
        guard let button = ControllerButton(rawValue: buttonPart),
              let mapping = profile.buttonMappings[button] else {
            return buttonPart + " " + typePart.lowercased()
        }

        switch typePart {
        case "Press":
            return mapping.hint ?? mapping.displayString
        case "Long Press":
            if let lh = mapping.longHoldMapping {
                return lh.hint ?? lh.displayString
            }
            return mapping.hint ?? mapping.displayString
        case "Double Tap":
            if let dt = mapping.doubleTapMapping {
                return dt.hint ?? dt.displayString
            }
            return mapping.hint ?? mapping.displayString
        default:
            return mapping.hint ?? mapping.displayString
        }
    }
}
