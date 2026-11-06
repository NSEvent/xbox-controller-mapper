import CoreGraphics
import Foundation

/// Turns Wii Remote IR camera blobs into cursor moves.
///
/// Aiming is absolute, as on a Wii: the camera frame (inset by a margin)
/// maps onto the screen, so the cursor goes where the remote points and
/// every screen edge is reachable while the sensor bar is still in view —
/// however the session started. (An earlier design anchored the cursor to
/// wherever the bar sat at the first IR fix; that fix often lands as the
/// bar enters at the frame edge, leaving almost no camera room in one
/// direction — the "invisible ceiling".) Dropped reports and dropouts can't
/// accumulate drift because nothing is summed. Moves are still emitted as
/// deltas so the input simulator's drag handling keeps working.
///
/// The aim reference is the sensor bar's midpoint. When only one end is
/// visible (off-axis viewing dims one cluster, or it leaves the camera's
/// narrow vertical field) the midpoint is reconstructed from the last seen
/// bar geometry, so 2↔1 blob flicker neither drops motion nor jumps the
/// cursor. The bar's tilt in the image gives the remote's roll, which is
/// undone so up-down hand motion stays vertical however the remote is held.
nonisolated struct WiimoteIRTracker {
    static let cameraWidth: CGFloat = 1024
    static let cameraHeight: CGFloat = 768
    static let cameraCenter = CGPoint(x: 512, y: 384)
    /// A pair tilted further than this is not a level sensor bar.
    static let maxPairTilt: CGFloat = .pi / 3
    /// Closer blobs are one bar end split in two, not the two ends.
    static let minPairSeparation: CGFloat = 12
    /// A pair this far off the remembered bar geometry is treated as stray
    /// light (lamps, reflections) rather than the bar.
    static let maxPairMismatch: CGFloat = 0.75
    /// Rejecting every pair for this long means the remembered geometry is
    /// stale (the user moved) rather than the pairs being stray light.
    static let staleGeometryInterval: TimeInterval = 0.5
    /// After a dropout this long the cursor snaps to the reacquired aim
    /// instead of easing toward it.
    static let reacquireSnapInterval: TimeInterval = 0.4
    /// The screen edges map this far inside the camera frame, so they're
    /// reached while the bar is still in view (it's lost at the frame edge).
    static let frameMargin: CGFloat = 40

    struct Blob: Equatable {
        let point: CGPoint
        let size: Int
    }

    struct Pair: Equatable {
        let left: CGPoint
        let right: CGPoint
        var midpoint: CGPoint { CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2) }
        var halfSpan: CGPoint { CGPoint(x: (right.x - left.x) / 2, y: (right.y - left.y) / 2) }
    }

    /// True once IR has been seen this session (tilt never takes over after).
    private(set) var hasSeenIR = false
    /// (right − left) / 2 of the last trusted bar pair, in camera space.
    private var halfSpan: CGPoint?
    /// Last camera-space aim reference (bar midpoint, or a lone blob before
    /// the bar geometry is known).
    private var lastReference: CGPoint?
    private var roll: CGFloat = 0
    private var pairRejectedSince: TimeInterval?
    private var smoothedAim: CGPoint?
    private var lastSampleTime: TimeInterval = -.infinity
    private var emittedCursor: CGPoint?
    /// Latest smoothed aim and cursor target, for the diagnostic trace.
    private(set) var lastAim: CGPoint?
    private(set) var lastTarget: CGPoint?

    /// Feed one report's blobs; returns the cursor delta to post (nil when
    /// nothing should move).
    mutating func update(
        blobs: [Blob],
        at time: TimeInterval,
        baseAlpha: CGFloat,
        gain: CGFloat,
        bounds: CGRect,
        currentCursor: () -> CGPoint
    ) -> CGPoint? {
        guard !blobs.isEmpty, let resolved = resolveReference(blobs, at: time) else { return nil }
        let aim = derotate(resolved)
        hasSeenIR = true

        let reacquired = smoothedAim == nil || time - lastSampleTime >= Self.reacquireSnapInterval
        let smoothed: CGPoint
        if let previous = smoothedAim, !reacquired {
            // Speed-adaptive (One-Euro-style): a still hand gets heavy
            // smoothing so sensor noise parks the cursor; sweeps stay responsive.
            let distance = hypot(aim.x - previous.x, aim.y - previous.y)
            let alpha = min(0.85, baseAlpha + distance * 0.015)
            smoothed = CGPoint(
                x: previous.x + (aim.x - previous.x) * alpha,
                y: previous.y + (aim.y - previous.y) * alpha
            )
        } else {
            smoothed = aim
        }
        smoothedAim = smoothed
        lastSampleTime = time

        let target = Self.screenPosition(aim: smoothed, bounds: bounds, gain: gain)
        lastAim = smoothed
        lastTarget = target
        // On (re)acquiring, measure from the real cursor in case something
        // else (a trackpad) moved it while IR wasn't steering.
        let emitted = (reacquired ? nil : emittedCursor) ?? Self.clamp(currentCursor(), to: bounds)
        emittedCursor = target
        return CGPoint(x: target.x - emitted.x, y: target.y - emitted.y)
    }

    /// Absolute aim → screen position. The inset camera frame spans the
    /// screen at 1× gain; higher gain spans it with less hand movement
    /// (centered), and gain is floored at 1× so the edges stay reachable.
    /// Camera X is mirrored: pointing right moves the bar's image left.
    static func screenPosition(aim: CGPoint, bounds: CGRect, gain: CGFloat) -> CGPoint {
        let g = max(1, gain)
        let u = (cameraWidth - 1 - frameMargin - aim.x) / (cameraWidth - 1 - 2 * frameMargin)
        let v = (aim.y - frameMargin) / (cameraHeight - 1 - 2 * frameMargin)
        return clamp(CGPoint(
            x: bounds.minX + (0.5 + (u - 0.5) * g) * (bounds.width - 1),
            y: bounds.minY + (0.5 + (v - 0.5) * g) * (bounds.height - 1)
        ), to: bounds)
    }

    // MARK: Reference resolution

    /// The camera-space aim reference for this report.
    private mutating func resolveReference(_ blobs: [Blob], at time: TimeInterval) -> CGPoint? {
        if let pair = acceptPair(blobs, at: time) {
            halfSpan = pair.halfSpan
            roll = atan2(pair.halfSpan.y, pair.halfSpan.x)
            lastReference = pair.midpoint
            return pair.midpoint
        }

        if let halfSpan {
            // One bar end visible: each blob could be either end, so take
            // the implied midpoint nearest the previous one.
            let previous = lastReference ?? Self.cameraCenter
            var best: CGPoint?
            var bestDistance = CGFloat.infinity
            for blob in blobs {
                for candidate in [
                    CGPoint(x: blob.point.x + halfSpan.x, y: blob.point.y + halfSpan.y),
                    CGPoint(x: blob.point.x - halfSpan.x, y: blob.point.y - halfSpan.y),
                ] {
                    let d = Self.distance(candidate, previous)
                    if d < bestDistance {
                        bestDistance = d
                        best = candidate
                    }
                }
            }
            if let best { lastReference = best }
            return best
        }

        // No bar geometry yet: aim with a lone blob until both ends appear.
        let blob: Blob
        if let last = lastReference {
            blob = blobs.min { Self.distance($0.point, last) < Self.distance($1.point, last) }!
        } else {
            blob = blobs.max { $0.size < $1.size }!
        }
        lastReference = blob.point
        return blob.point
    }

    /// The best bar pair this report, gated against the remembered bar
    /// geometry — unless that geometry has rejected every pair for long
    /// enough that it's the geometry that's wrong.
    private mutating func acceptPair(_ blobs: [Blob], at time: TimeInterval) -> Pair? {
        guard blobs.count >= 2 else {
            pairRejectedSince = nil
            return nil
        }
        guard let candidate = Self.bestPair(blobs, previousHalfSpan: halfSpan) else {
            pairRejectedSince = nil
            return nil
        }
        let (pair, cost) = candidate
        if halfSpan == nil || cost <= Self.maxPairMismatch {
            pairRejectedSince = nil
            return pair
        }
        let since = pairRejectedSince ?? time
        pairRejectedSince = since
        return time - since >= Self.staleGeometryInterval ? pair : nil
    }

    /// Most bar-like pair among the blobs, with its mismatch cost against
    /// the previous geometry (without history: the widest level pair).
    static func bestPair(_ blobs: [Blob], previousHalfSpan: CGPoint?) -> (Pair, CGFloat)? {
        var best: (Pair, CGFloat)?
        for i in blobs.indices {
            for j in blobs.indices where j > i {
                let a = blobs[i].point
                let b = blobs[j].point
                let pair = a.x <= b.x ? Pair(left: a, right: b) : Pair(left: b, right: a)
                let dx = pair.right.x - pair.left.x
                let dy = pair.right.y - pair.left.y
                let separation = hypot(dx, dy)
                let tilt = atan2(dy, dx)
                guard separation >= minPairSeparation, abs(tilt) <= maxPairTilt else { continue }
                let cost: CGFloat
                if let previous = previousHalfSpan {
                    let previousSeparation = max(1, hypot(previous.x, previous.y) * 2)
                    cost = abs(separation - previousSeparation) / previousSeparation
                        + abs(tilt - atan2(previous.y, previous.x))
                } else {
                    cost = -separation
                }
                if best == nil || cost < best!.1 {
                    best = (pair, cost)
                }
            }
        }
        return best
    }

    // MARK: Geometry

    /// Undo the remote's roll by rotating about the camera center so the
    /// bar lies level.
    private func derotate(_ point: CGPoint) -> CGPoint {
        let c = Self.cameraCenter
        let vx = point.x - c.x
        let vy = point.y - c.y
        let cosine = cos(-roll)
        let sine = sin(-roll)
        return CGPoint(x: c.x + vx * cosine - vy * sine, y: c.y + vx * sine + vy * cosine)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX - 1),
            y: min(max(point.y, bounds.minY), bounds.maxY - 1)
        )
    }
}
