import Foundation
import CoreGraphics

/// Pure policy that determines how mouse events should be posted.
///
/// During Accessibility Zoom, mouse-down/up/drag events need
/// kIOHIDSetCursorPosition to keep click targeting correct without the zoom
/// compositor's software cursor flashing at the virtual/absolute position.
/// Plain mouse moves stay on the CGEvent path; Universal Control can at least
/// begin handoff there, while IOHID relative moves stay trapped on the local edge.
struct ZoomMouseEventPolicy {
    enum MouseEventCategory {
        case move       // .mouseMoved (no button held)
        case drag       // .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
        case buttonDown // .leftMouseDown, .rightMouseDown, .otherMouseDown
        case buttonUp   // .leftMouseUp, .rightMouseUp, .otherMouseUp
    }

    /// Returns true if the event should be posted via IOHIDPostEvent instead of CGEvent.
    /// When false, the normal CGEvent path should be used.
    static func shouldUseIOHIDPostEvent(zoomActive: Bool, category: MouseEventCategory) -> Bool {
        guard zoomActive else { return false }
        switch category {
        case .move:
            return false
        case .drag, .buttonDown, .buttonUp:
            return true
        }
    }

    /// Returns true when IOHIDPostEvent should force the cursor position.
    static func shouldSetCursorPositionInIOHIDEvent(zoomActive: Bool, category: MouseEventCategory) -> Bool {
        guard zoomActive else { return false }
        switch category {
        case .move:
            return false
        case .drag, .buttonDown, .buttonUp:
            return true
        }
    }
}

struct UniversalControlRelayLocalMousePolicy {
    static func eventPoint(
		proposed: CGPoint,
		clamped: CGPoint,
		zoomActive: Bool,
		isDrag: Bool,
		relayCanHandleEdge: Bool
    ) -> CGPoint {
		guard !zoomActive, !isDrag, !relayCanHandleEdge else {
			return clamped
		}
		return proposed
    }

	static func trackedPoint(clamped: CGPoint) -> CGPoint {
		clamped
	}

	static func appliedDelta(from current: CGPoint, to eventPoint: CGPoint) -> CGPoint {
		CGPoint(
			x: eventPoint.x - current.x,
			y: eventPoint.y - current.y
		)
	}
}

struct UniversalControlRelayRolePolicy {
	static func canSendToRemote(acceptsRemoteInput: Bool) -> Bool {
		true
	}

	static func canStartRemoteHandoff(
		hasConfiguredRelayTarget: Bool,
		remoteHandoffSuppressed: Bool
	) -> Bool {
		hasConfiguredRelayTarget && !remoteHandoffSuppressed
	}

	static func handlesIncomingRemoteInput(acceptsRemoteInput: Bool) -> Bool {
		acceptsRemoteInput
	}
}

struct UniversalControlRelaySessionPolicy {
	static let confirmationTimeout: CFTimeInterval = 1.5

	static func shouldCancelForMissingInitialCursorStatus(
		sessionActive: Bool,
		hasReceivedCursorStatus: Bool,
		elapsedSinceStart: CFTimeInterval?
	) -> Bool {
		guard sessionActive, !hasReceivedCursorStatus, let elapsedSinceStart else {
			return false
		}
		return elapsedSinceStart > confirmationTimeout
	}
}

struct RemoteCursorVisibilityRestorePolicy {
	static let restoreThrottleInterval: CFTimeInterval = 0.25
	static let reconnectIdleRepairInterval: CFTimeInterval = 5.0

	struct Decision: Equatable {
		let shouldRestore: Bool
		let shouldRepairPotentialStaleHide: Bool
	}

	static func decision(
		now: CFTimeInterval,
		lastRestoreAt: CFTimeInterval?
	) -> Decision {
		guard let lastRestoreAt else {
			return Decision(shouldRestore: true, shouldRepairPotentialStaleHide: true)
		}

		let elapsed = now - lastRestoreAt
		if elapsed <= restoreThrottleInterval {
			return Decision(shouldRestore: false, shouldRepairPotentialStaleHide: false)
		}

		return Decision(
			shouldRestore: true,
			shouldRepairPotentialStaleHide: elapsed > reconnectIdleRepairInterval
		)
	}
}
