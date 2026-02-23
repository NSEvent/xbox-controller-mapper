import Foundation

/// Protocol for stateful gesture detectors.
/// Each detector tracks its own state machine and emits results when patterns complete.
protocol GestureDetecting {
    associatedtype Input
    associatedtype Result

    /// Process a new input sample at the given timestamp.
    /// Returns a result if a gesture pattern completed, nil otherwise.
    func process(_ input: Input, at time: TimeInterval) -> Result?

    /// Reset all internal state.
    func reset()
}
