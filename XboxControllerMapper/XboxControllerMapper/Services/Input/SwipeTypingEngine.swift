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

    // MARK: - Thread-Safe State

    private nonisolated(unsafe) let stateLock = NSLock()
    private nonisolated(unsafe) var tsState: SwipeTypingState = .idle
    private nonisolated(unsafe) var tsCursorPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private nonisolated(unsafe) var tsSwipePath: [CGPoint] = []
    private nonisolated(unsafe) var _samples: [SwipeSample] = []
    private nonisolated(unsafe) var _lastSampleTime: CFAbsoluteTime = 0
    private nonisolated(unsafe) var _swipeStartTime: CFAbsoluteTime = 0
    private nonisolated(unsafe) var _smoothedDx: Double = 0
    private nonisolated(unsafe) var _smoothedDy: Double = 0

    /// Minimum interval between samples (~60Hz)
    private nonisolated(unsafe) let sampleInterval: CFAbsoluteTime = 1.0 / 60.0

    nonisolated var threadSafeState: SwipeTypingState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return tsState
    }

    nonisolated var threadSafeCursorPosition: CGPoint {
        stateLock.lock()
        defer { stateLock.unlock() }
        return tsCursorPosition
    }

    // MARK: - Model

    private nonisolated(unsafe) var model: SwipeTypingModel?
    private nonisolated(unsafe) var modelLoaded = false

    private func ensureModelLoaded() {
        guard !modelLoaded else { return }
        modelLoaded = true
        let m = SwipeTypingModel()
        model = m
        m.loadModel()
    }

    private init() {}

    // MARK: - Mode Lifecycle

    /// Enter swipe mode — cursor becomes visible, waiting for touchpad touch.
    nonisolated func activateMode() {
        stateLock.lock()
        guard tsState == .idle else {
            stateLock.unlock()
            return
        }
        tsState = .active
        stateLock.unlock()

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
        stateLock.lock()
        tsState = .idle
        tsSwipePath = []
        _samples = []
        stateLock.unlock()

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
        stateLock.lock()
        tsCursorPosition = pos
        stateLock.unlock()

        DispatchQueue.main.async { [self] in
            self.cursorPosition = pos
        }
    }

    // MARK: - Swipe Lifecycle

    /// Begin a new swipe gesture. Resets path and samples, sets state to swiping.
    /// Can be called from `.active` or `.showingPredictions` (to start next word).
    nonisolated func beginSwipe() {
        let now = CFAbsoluteTimeGetCurrent()
        stateLock.lock()
        guard tsState == .active || tsState == .showingPredictions else {
            stateLock.unlock()
            return
        }
        tsState = .swiping
        tsSwipePath = [tsCursorPosition]
        _samples = [SwipeSample(x: Double(tsCursorPosition.x), y: Double(tsCursorPosition.y), dt: 0)]
        _lastSampleTime = now
        _swipeStartTime = now
        _smoothedDx = 0
        _smoothedDy = 0
        stateLock.unlock()

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

        stateLock.lock()
        guard tsState == .swiping else {
            stateLock.unlock()
            return
        }

        let elapsed = now - _lastSampleTime
        guard elapsed >= sampleInterval else {
            stateLock.unlock()
            return
        }

        let dt = now - _lastSampleTime
        _lastSampleTime = now

        let point = CGPoint(x: x, y: y)
        tsSwipePath.append(point)
        _samples.append(SwipeSample(x: x, y: y, dt: dt))

        let pathSnapshot = tsSwipePath
        stateLock.unlock()

        DispatchQueue.main.async { [self] in
            self.swipePath = pathSnapshot
        }
    }

    /// End the current swipe and trigger inference.
    nonisolated func endSwipe() {
        stateLock.lock()
        guard tsState == .swiping else {
            stateLock.unlock()
            return
        }
        tsState = .predicting
        let samples = _samples
        stateLock.unlock()

        DispatchQueue.main.async { [self] in
            self.state = .predicting
        }

        // Run inference on background queue
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let results: [SwipeTypingPrediction]
            if let m = self.model {
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
                    self.stateLock.lock()
                    self.tsState = .active
                    self.stateLock.unlock()
                } else {
                    self.state = .showingPredictions
                    self.stateLock.lock()
                    self.tsState = .showingPredictions
                    self.stateLock.unlock()
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

        stateLock.lock()
        tsState = .active
        tsSwipePath = []
        _samples = []
        stateLock.unlock()
    }

    // MARK: - Cursor Control

    /// Update cursor position from joystick axis values.
    /// Called from the controller polling thread.
    nonisolated func updateCursorFromJoystick(x: Double, y: Double, sensitivity: Double) {
        let scale = sensitivity * 0.02  // per-frame displacement at max deflection
        stateLock.lock()
        guard tsState == .swiping else {
            stateLock.unlock()
            return
        }
        var pos = tsCursorPosition
        pos.x += CGFloat(x * scale)
        pos.y += CGFloat(y * scale)
        // No clamping — allow swiping freely beyond the keyboard letter area
        tsCursorPosition = pos

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - _lastSampleTime
        if elapsed >= sampleInterval {
            let dt = now - _lastSampleTime
            _lastSampleTime = now
            tsSwipePath.append(pos)
            _samples.append(SwipeSample(x: Double(pos.x), y: Double(pos.y), dt: dt))
        }
        let pathSnapshot = tsSwipePath
        stateLock.unlock()

        DispatchQueue.main.async { [self] in
            self.cursorPosition = pos
            self.swipePath = pathSnapshot
        }
    }

    /// Update cursor position from touchpad delta values.
    /// Called from the controller polling thread. Applies EMA smoothing for fluid motion.
    nonisolated func updateCursorFromTouchpadDelta(dx: Double, dy: Double, sensitivity: Double) {
        let scaleX = sensitivity * 2.0
        let scaleY = sensitivity * 3.0  // Slight Y boost: keyboard rows are close together, touchpad is wide but short

        // EMA smoothing (alpha=0.4 — responsive but smooth)
        let alpha = 0.4
        let smoothDx = _smoothedDx + (dx - _smoothedDx) * alpha
        let smoothDy = _smoothedDy + (dy - _smoothedDy) * alpha
        _smoothedDx = smoothDx
        _smoothedDy = smoothDy

        stateLock.lock()
        guard tsState == .swiping else {
            stateLock.unlock()
            return
        }
        var pos = tsCursorPosition
        pos.x += CGFloat(smoothDx * scaleX)
        pos.y += CGFloat(smoothDy * scaleY)
        // No clamping — allow swiping freely beyond the keyboard letter area
        tsCursorPosition = pos

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - _lastSampleTime
        if elapsed >= sampleInterval {
            let dt = now - _lastSampleTime
            _lastSampleTime = now
            tsSwipePath.append(pos)
            _samples.append(SwipeSample(x: Double(pos.x), y: Double(pos.y), dt: dt))
        }
        let pathSnapshot = tsSwipePath
        stateLock.unlock()

        DispatchQueue.main.async { [self] in
            self.cursorPosition = pos
            self.swipePath = pathSnapshot
        }
    }
}
