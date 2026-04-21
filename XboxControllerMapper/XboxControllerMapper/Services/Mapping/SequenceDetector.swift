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
    /// Uses an index into the `sequences` array to avoid copying the steps array.
    struct SequenceProgress {
        let sequenceIndex: Int
        let stepCount: Int
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
        // Phase 1: Filter active sequences in-place — advance matching ones, discard the rest.
        var writeIdx = 0
        for i in 0..<activeSequences.count {
            let seq = activeSequences[i]
            let sinceLastStep = time - seq.lastStepTime
            let effectiveTimeout = seq.stepTimeout + chordWindowTolerance
            if sinceLastStep <= effectiveTimeout
                && seq.matchedCount < seq.stepCount
                && button == sequences[seq.sequenceIndex].steps[seq.matchedCount]
            {
                activeSequences[writeIdx] = seq
                activeSequences[writeIdx].matchedCount += 1
                activeSequences[writeIdx].lastStepTime = time
                writeIdx += 1
            }
        }
        activeSequences.removeSubrange(writeIdx...)

        // Phase 2: Start tracking new sequences whose first step matches.
        // Linear scan for duplicate check — faster than Set for typical sequence counts (<20).
        let survivingCount = writeIdx
        for (seqIdx, seq) in sequences.enumerated() where seq.isValid {
            let alreadyTracked = activeSequences[0..<survivingCount].contains { $0.sequenceIndex == seqIdx }
            if !alreadyTracked && seq.steps[0] == button {
                activeSequences.append(SequenceProgress(
                    sequenceIndex: seqIdx,
                    stepCount: seq.steps.count,
                    stepTimeout: seq.stepTimeout,
                    matchedCount: 1,
                    lastStepTime: time
                ))
            }
        }

        // Phase 3: Check for a completed sequence.
        if let completedIdx = activeSequences.firstIndex(where: { $0.matchedCount == $0.stepCount }) {
            let completed = activeSequences[completedIdx]
            let sequence = sequences[completed.sequenceIndex]

            activeSequences.remove(at: completedIdx)
            return sequence
        }

        return nil
    }

    /// Reset all tracking state.
    func reset() {
        activeSequences.removeAll()
    }
}
