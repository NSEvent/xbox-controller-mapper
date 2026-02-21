import Foundation
import Combine
import CoreGraphics

// MARK: - State

enum SwipeTypingState: Equatable {
    case idle
    case active            // Mode entered (cursor visible), waiting for touchpad touch
    case swiping
    case predicting
    case showingPredictions
}

// MARK: - SwipeTypingEngine

/// Central coordinator for swipe typing on the on-screen keyboard.
/// Collects joystick/touchpad samples, runs ML inference, and presents predictions.
@MainActor
class SwipeTypingEngine: ObservableObject {
    static let shared = SwipeTypingEngine()

    @Published private(set) var state: SwipeTypingState = .idle
    @Published private(set) var swipePath: [CGPoint] = []
    @Published private(set) var predictions: [SwipeTypingPrediction] = []
    @Published var selectedPredictionIndex: Int = 0
    @Published var cursorPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)

    // MARK: - Thread-Safe Locked Storage

    /// All mutable state shared between the polling thread and the main actor is held
    /// inside this lock-protected storage. Every access goes through `withStorage`,
    /// eliminating the possibility of forgetting to acquire the lock.
    private final class LockedStorage: @unchecked Sendable {
        private let lock = NSLock()

        var state: SwipeTypingState = .idle
        var cursorPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
        var swipePath: [CGPoint] = []
        var samples: [SwipeSample] = []
        var lastSampleTime: CFAbsoluteTime = 0
        var swipeStartTime: CFAbsoluteTime = 0
        var smoothedDx: Double = 0
        var smoothedDy: Double = 0

        /// Minimum interval between samples (~60Hz)
        let sampleInterval: CFAbsoluteTime = 1.0 / 60.0

        func withLock<T>(_ body: (LockedStorage) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(self)
        }
    }

    private nonisolated let storage = LockedStorage()

    nonisolated var threadSafeState: SwipeTypingState {
        storage.withLock { $0.state }
    }

    nonisolated var threadSafeCursorPosition: CGPoint {
        storage.withLock { $0.cursorPosition }
    }

    // MARK: - Model

    private var model: SwipeTypingModel?
    private var modelLoaded = false

    private func ensureModelLoaded() {
        guard !modelLoaded else { return }
        modelLoaded = true
        let m = SwipeTypingModel()
        model = m
        m.loadModel()
    }

    /// Thread-safe snapshot of the model reference for use from background queues.
    /// Must be called from `@MainActor` (compile-time enforced) so the read is safe.
    private func modelSnapshot() -> SwipeTypingModel? {
        return model
    }

    private init() {}

    // MARK: - Mode Lifecycle

    /// Enter swipe mode — cursor becomes visible, waiting for touchpad touch.
    nonisolated func activateMode() {
        let didActivate = storage.withLock { s -> Bool in
            guard s.state == .idle else { return false }
            s.state = .active
            return true
        }
        guard didActivate else { return }

        DispatchQueue.main.async { [self] in
            self.ensureModelLoaded()
            self.state = .active
            self.swipePath = []
            self.predictions = []
            self.selectedPredictionIndex = 0
        }
    }

    /// Exit swipe mode entirely — cancel any in-progress swipe or predictions.
    nonisolated func deactivateMode() {
        storage.withLock { s in
            s.state = .idle
            s.swipePath = []
            s.samples = []
        }

        DispatchQueue.main.async { [self] in
            self.state = .idle
            self.swipePath = []
            self.predictions = []
            self.selectedPredictionIndex = 0
        }
    }

    /// Set the cursor position (e.g. from the system mouse position mapped to normalized coords).
    /// Called from the controller polling thread before beginSwipe().
    nonisolated func setCursorPosition(_ pos: CGPoint) {
        storage.withLock { s in
            s.cursorPosition = pos
        }

        DispatchQueue.main.async { [self] in
            self.cursorPosition = pos
        }
    }

    // MARK: - Swipe Lifecycle

    /// Begin a new swipe gesture. Resets path and samples, sets state to swiping.
    /// Can be called from `.active` or `.showingPredictions` (to start next word).
    nonisolated func beginSwipe() {
        let now = CFAbsoluteTimeGetCurrent()
        let didBegin = storage.withLock { s -> Bool in
            guard s.state == .active || s.state == .showingPredictions else { return false }
            s.state = .swiping
            s.swipePath = [s.cursorPosition]
            s.samples = [SwipeSample(x: Double(s.cursorPosition.x), y: Double(s.cursorPosition.y), dt: 0)]
            s.lastSampleTime = now
            s.swipeStartTime = now
            s.smoothedDx = 0
            s.smoothedDy = 0
            return true
        }
        guard didBegin else { return }

        DispatchQueue.main.async { [self] in
            self.ensureModelLoaded()
            self.state = .swiping
            self.swipePath = [self.cursorPosition]
            self.predictions = []
            self.selectedPredictionIndex = 0
        }
    }

    /// Add a position sample to the current swipe. Rate-limited to ~60Hz.
    /// Called from the controller polling thread.
    nonisolated func addSample(x: Double, y: Double) {
        let now = CFAbsoluteTimeGetCurrent()

        let pathSnapshot: [CGPoint]? = storage.withLock { s -> [CGPoint]? in
            guard s.state == .swiping else { return nil }

            let elapsed = now - s.lastSampleTime
            guard elapsed >= s.sampleInterval else { return nil }

            let dt = now - s.lastSampleTime
            s.lastSampleTime = now

            let point = CGPoint(x: x, y: y)
            s.swipePath.append(point)
            s.samples.append(SwipeSample(x: x, y: y, dt: dt))

            return s.swipePath
        }

        if let pathSnapshot {
            DispatchQueue.main.async { [self] in
                self.swipePath = pathSnapshot
            }
        }
    }

    /// End the current swipe and trigger inference.
    nonisolated func endSwipe() {
        let samples: [SwipeSample]? = storage.withLock { s -> [SwipeSample]? in
            guard s.state == .swiping else { return nil }
            s.state = .predicting
            return s.samples
        }
        guard let samples else { return }

        DispatchQueue.main.async { [self] in
            self.state = .predicting

            // Capture model reference on MainActor (safe) before dispatching to background
            let modelRef = self.modelSnapshot()

            // Run inference on background queue
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let results: [SwipeTypingPrediction]
                if let m = modelRef {
                    results = m.predict(samples: samples)
                } else {
                    results = []
                }

                DispatchQueue.main.async { [self] in
                    self.predictions = results
                    self.selectedPredictionIndex = 0
                    if results.isEmpty {
                        // No predictions — return to active mode (cursor visible)
                        self.state = .active
                        self.storage.withLock { s in
                            s.state = .active
                        }
                    } else {
                        self.state = .showingPredictions
                        self.storage.withLock { s in
                            s.state = .showingPredictions
                        }
                    }
                }
            }
        }
    }

    // MARK: - Prediction Selection

    func selectNextPrediction() {
        guard !predictions.isEmpty else { return }
        selectedPredictionIndex = (selectedPredictionIndex + 1) % predictions.count
    }

    func selectPreviousPrediction() {
        guard !predictions.isEmpty else { return }
        selectedPredictionIndex = (selectedPredictionIndex - 1 + predictions.count) % predictions.count
    }

    /// Confirm the currently selected prediction and return to active mode.
    /// Returns the selected word, or nil if no predictions are available.
    func confirmSelection() -> String? {
        guard state == .showingPredictions, !predictions.isEmpty else { return nil }
        let word = predictions[selectedPredictionIndex].word
        resetToActive()
        return word
    }

    /// Cancel predictions and return to active mode (still in swipe mode).
    func cancelPredictions() {
        resetToActive()
    }

    private func resetToActive() {
        state = .active
        swipePath = []
        predictions = []
        selectedPredictionIndex = 0

        storage.withLock { s in
            s.state = .active
            s.swipePath = []
            s.samples = []
        }
    }

    // MARK: - Cursor Control

    /// Update cursor position from joystick axis values.
    /// Called from the controller polling thread.
    nonisolated func updateCursorFromJoystick(x: Double, y: Double, sensitivity: Double) {
        let scale = sensitivity * 0.02  // per-frame displacement at max deflection

        let result: (pos: CGPoint, pathSnapshot: [CGPoint])? = storage.withLock { s -> (CGPoint, [CGPoint])? in
            guard s.state == .swiping else { return nil }
            var pos = s.cursorPosition
            pos.x += CGFloat(x * scale)
            pos.y += CGFloat(y * scale)
            // No clamping — allow swiping freely beyond the keyboard letter area
            s.cursorPosition = pos

            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - s.lastSampleTime
            if elapsed >= s.sampleInterval {
                let dt = now - s.lastSampleTime
                s.lastSampleTime = now
                s.swipePath.append(pos)
                s.samples.append(SwipeSample(x: Double(pos.x), y: Double(pos.y), dt: dt))
            }
            return (pos, s.swipePath)
        }

        if let result {
            DispatchQueue.main.async { [self] in
                self.cursorPosition = result.pos
                self.swipePath = result.pathSnapshot
            }
        }
    }

    /// Update cursor position from touchpad delta values.
    /// Called from the controller polling thread. Applies EMA smoothing for fluid motion.
    nonisolated func updateCursorFromTouchpadDelta(dx: Double, dy: Double, sensitivity: Double) {
        let scaleX = sensitivity * 2.0
        let scaleY = sensitivity * 3.0  // Slight Y boost: keyboard rows are close together, touchpad is wide but short

        // EMA smoothing (alpha=0.4 — responsive but smooth)
        let alpha = 0.4

        let result: (pos: CGPoint, pathSnapshot: [CGPoint])? = storage.withLock { s -> (CGPoint, [CGPoint])? in
            let smoothDx = s.smoothedDx + (dx - s.smoothedDx) * alpha
            let smoothDy = s.smoothedDy + (dy - s.smoothedDy) * alpha
            s.smoothedDx = smoothDx
            s.smoothedDy = smoothDy

            guard s.state == .swiping else { return nil }
            var pos = s.cursorPosition
            pos.x += CGFloat(smoothDx * scaleX)
            pos.y += CGFloat(smoothDy * scaleY)
            // No clamping — allow swiping freely beyond the keyboard letter area
            s.cursorPosition = pos

            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - s.lastSampleTime
            if elapsed >= s.sampleInterval {
                let dt = now - s.lastSampleTime
                s.lastSampleTime = now
                s.swipePath.append(pos)
                s.samples.append(SwipeSample(x: Double(pos.x), y: Double(pos.y), dt: dt))
            }
            return (pos, s.swipePath)
        }

        if let result {
            DispatchQueue.main.async { [self] in
                self.cursorPosition = result.pos
                self.swipePath = result.pathSnapshot
            }
        }
    }
}
