import Foundation

/// Detects button sequences (e.g., A -> B -> X) with configurable per-step timeouts.
/// Extracted from MappingEngine.advanceSequenceTracking() for testability and reuse.
///
/// Thread safety: This class is NOT thread-safe. Callers must synchronize access externally
/// (e.g., via the MappingEngine's state lock).
final class SequenceDetector: GestureDetecting {
    typealias Input = ControllerButton
    typealias Result = SequenceMapping

    /// Tracks progress through a single sequence mapping.
    struct SequenceProgress {
        let sequenceId: UUID
        let steps: [ControllerButton]
        let stepTimeout: TimeInterval
        var matchedCount: Int
        var lastStepTime: TimeInterval
    }

    /// Currently active (partially matched) sequences.
    private(set) var activeSequences: [SequenceProgress] = []

    /// The configured sequence mappings to detect.
    private var sequences: [SequenceMapping] = []

    /// Additional time tolerance added to each step timeout (accounts for chord detection window).
    var chordWindowTolerance: TimeInterval = 0

    /// Configure the detector with the available sequence mappings.
    func configure(sequences: [SequenceMapping]) {
        self.sequences = sequences
        activeSequences.removeAll()
    }

    /// Process a button press and check if any sequence completed.
    ///
    /// - Parameters:
    ///   - button: The button that was pressed.
    ///   - time: Current timestamp (any monotonic time source).
    /// - Returns: The completed SequenceMapping if a sequence was fully matched, nil otherwise.
    func process(_ button: ControllerButton, at time: TimeInterval) -> SequenceMapping? {
        var survivingSequences: [SequenceProgress] = []
        for var seq in activeSequences {
            let sinceLastStep = time - seq.lastStepTime
            let effectiveTimeout = seq.stepTimeout + chordWindowTolerance
            if sinceLastStep <= effectiveTimeout && seq.matchedCount < seq.steps.count && button == seq.steps[seq.matchedCount] {
                seq.matchedCount += 1
                seq.lastStepTime = time
                survivingSequences.append(seq)
            }
        }

        let trackedIds = Set(survivingSequences.map { $0.sequenceId })
        for seq in sequences where seq.isValid {
            if !trackedIds.contains(seq.id) && seq.steps[0] == button {
                survivingSequences.append(SequenceProgress(
                    sequenceId: seq.id,
                    steps: seq.steps,
                    stepTimeout: seq.stepTimeout,
                    matchedCount: 1,
                    lastStepTime: time
                ))
            }
        }

        if let completedIdx = survivingSequences.firstIndex(where: { $0.matchedCount == $0.steps.count }) {
            let completed = survivingSequences[completedIdx]
            let sequence = sequences.first { $0.id == completed.sequenceId }

            survivingSequences.remove(at: completedIdx)
            activeSequences = survivingSequences
            return sequence
        }

        activeSequences = survivingSequences
        return nil
    }

    /// Reset all tracking state.
    func reset() {
        activeSequences.removeAll()
    }
}
