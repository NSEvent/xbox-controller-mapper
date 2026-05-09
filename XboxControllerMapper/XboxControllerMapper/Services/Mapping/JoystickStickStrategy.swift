import Foundation
import CoreGraphics

/// Which physical stick is being processed. Used by mode strategies that need
/// per-side state (e.g. smoothing buffers, held-key sets, scroll boost).
enum JoystickSide {
    case left
    case right
}

/// Inputs to a stick mode strategy for one polling tick. Bundled into a struct
/// so strategy signatures stay short and so adding a new field doesn't ripple
/// through every implementation.
struct JoystickStickInput {
    let stick: CGPoint
    let side: JoystickSide
    let settings: JoystickSettings
    let dt: TimeInterval
    let now: CFAbsoluteTime
    let hasMotion: Bool
}

/// One strategy per `StickMode`. The strategy owns the per-tick logic for
/// converting raw stick input into output (mouse motion, scroll, key events).
///
/// Strategies are stateless value types — they call back into MappingEngine
/// for state mutation (smoothing buffers, held keys) and side effects
/// (inputSimulator, haptics). The pattern reduces stick-mode dispatch from
/// two parallel switch statements (left + right) to one strategy lookup.
protocol JoystickStickStrategy {
    /// Process one tick of stick input.
    /// - Precondition: the engine's state lock is held by the caller.
    func process(_ input: JoystickStickInput, on engine: MappingEngine)
}

extension StickMode {
    /// The strategy implementing this mode. Each StickMode picks exactly one.
    /// Strategies are stateless so caching as static singletons is safe.
    var strategy: JoystickStickStrategy {
        switch self {
        case .none:      return NoOpStickStrategy.shared
        case .mouse:     return MouseStickStrategy.shared
        case .scroll:    return ScrollStickStrategy.shared
        case .wasdKeys:  return DirectionKeyStickStrategy.wasd
        case .arrowKeys: return DirectionKeyStickStrategy.arrows
        }
    }
}
