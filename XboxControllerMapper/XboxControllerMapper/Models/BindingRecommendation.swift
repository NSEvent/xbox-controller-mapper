import Foundation
import CoreGraphics

// MARK: - Recommendation Type

/// Describes a concrete change to the user's profile bindings
enum RecommendationType: Equatable {
    /// Swap two button mappings (high-frequency expensive action ↔ low-frequency cheap action)
    case swap(button1: ControllerButton, button2: ControllerButton)

    /// Move a long-hold or double-tap action to a cross-hand chord (frees sub-slot)
    case promoteToChord(
        fromButton: ControllerButton,
        fromType: PromoteSourceType,
        toChordButtons: Set<ControllerButton>,
        keyCode: CGKeyCode?,
        modifiers: ModifierFlags
    )

    /// Move an infrequent single-press to long hold, freeing the single-press slot
    case demoteToLongHold(button: ControllerButton, keyCode: CGKeyCode?, modifiers: ModifierFlags)

    /// The set of buttons this recommendation touches
    var involvedButtons: Set<ControllerButton> {
        switch self {
        case .swap(let b1, let b2):
            return [b1, b2]
        case .promoteToChord(let fromButton, _, let toChordButtons, _, _):
            return toChordButtons.union([fromButton])
        case .demoteToLongHold(let button, _, _):
            return [button]
        }
    }

    /// Whether this recommendation conflicts with another (shares buttons)
    func conflictsWith(_ other: RecommendationType) -> Bool {
        !involvedButtons.isDisjoint(with: other.involvedButtons)
    }
}

/// Source interaction type for chord promotion
enum PromoteSourceType: Equatable {
    case longHold
    case doubleTap
}

// MARK: - Recommendation

/// A single actionable recommendation with display info
struct BindingRecommendation: Identifiable, Equatable {
    let id: UUID
    let type: RecommendationType
    /// Higher priority = more impactful (waste difference)
    let priority: Double
    /// Controller-agnostic action description for the first button (e.g. "Copy Selection", "⌘ + A")
    let actionDescription1: String
    /// Controller-agnostic action description for the second button (only used for swaps)
    let actionDescription2: String

    init(
        id: UUID = UUID(),
        type: RecommendationType,
        priority: Double,
        actionDescription1: String,
        actionDescription2: String = ""
    ) {
        self.id = id
        self.type = type
        self.priority = priority
        self.actionDescription1 = actionDescription1
        self.actionDescription2 = actionDescription2
    }
}

// MARK: - Analysis Entry

/// Per-action row in the analysis table
struct BindingAnalysisEntry: Identifiable, Equatable {
    let id: UUID
    let actionKey: String
    let count: Int
    let probability: Double
    let actualCost: Double
    let optimalCost: Double
    /// actualCost - optimalCost (positive = wasted effort)
    let waste: Double
    let actionDescription: String

    init(
        id: UUID = UUID(),
        actionKey: String,
        count: Int,
        probability: Double,
        actualCost: Double,
        optimalCost: Double,
        waste: Double,
        actionDescription: String
    ) {
        self.id = id
        self.actionKey = actionKey
        self.count = count
        self.probability = probability
        self.actualCost = actualCost
        self.optimalCost = optimalCost
        self.waste = waste
        self.actionDescription = actionDescription
    }
}

// MARK: - Analysis Result

/// Complete analysis output
struct BindingAnalysisResult: Equatable {
    let entries: [BindingAnalysisEntry]
    let recommendations: [BindingRecommendation]
    /// 0–1 efficiency score (1 = perfectly optimal)
    let efficiencyScore: Double
    let totalActions: Int
    /// Minimum 50 actions required for meaningful analysis
    let hasEnoughData: Bool
}
