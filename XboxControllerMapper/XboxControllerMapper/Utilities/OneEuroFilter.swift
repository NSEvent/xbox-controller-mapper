import Foundation

/// Implementation of the 1€ (One Euro) Filter for noise reduction with minimal latency.
///
/// The filter adapts its cutoff frequency based on input speed:
/// - Slow movements get heavy smoothing (jitter reduction)
/// - Fast movements pass through with minimal lag (responsiveness)
///
/// Reference: Géry Casiez, Nicolas Roussel, Daniel Vogel.
/// "1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input in Interactive Systems"
/// CHI 2012. https://gery.casiez.net/1euro/
struct OneEuroFilter {
    /// Minimum cutoff frequency in Hz. Lower = more smoothing at rest.
    private let fcmin: Double
    /// Speed coefficient. Higher = less lag during fast movement.
    private let beta: Double
    /// Cutoff frequency for the derivative low-pass filter (Hz).
    private let dcutoff: Double

    private var xFilter = LowPassFilter()
    private var dxFilter = LowPassFilter()
    private var prevX: Double?

    init(fcmin: Double = 1.0, beta: Double = 0.007, dcutoff: Double = 1.0) {
        self.fcmin = fcmin
        self.beta = beta
        self.dcutoff = dcutoff
    }

    mutating func filter(_ x: Double, dt: Double) -> Double {
        guard dt > 0 else { return x }

        // Estimate derivative
        let dx: Double
        if let prev = prevX {
            dx = (x - prev) / dt
        } else {
            dx = 0
        }
        prevX = x

        // Low-pass filter the derivative
        let edx = dxFilter.filter(dx, alpha: Self.alpha(cutoff: dcutoff, dt: dt))

        // Compute adaptive cutoff frequency
        let cutoff = fcmin + beta * abs(edx)

        // Apply the main low-pass filter
        return xFilter.filter(x, alpha: Self.alpha(cutoff: cutoff, dt: dt))
    }

    mutating func reset() {
        xFilter.reset()
        dxFilter.reset()
        prevX = nil
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}

// MARK: - Low-Pass Filter (internal building block)

private struct LowPassFilter {
    private var hatXPrev: Double = 0
    private var initialized: Bool = false

    mutating func filter(_ x: Double, alpha: Double) -> Double {
        if initialized {
            let result = alpha * x + (1 - alpha) * hatXPrev
            hatXPrev = result
            return result
        } else {
            initialized = true
            hatXPrev = x
            return x
        }
    }

    mutating func reset() {
        initialized = false
        hatXPrev = 0
    }
}
