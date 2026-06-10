import Foundation
import CoreGraphics

// MARK: - Universal Control relay policies
// Pure, stateless policy/encoding helpers used by UniversalControlMouseRelay
// (and UniversalControlPortalIndicator). Extracted so they can be read and
// tested without wading through the relay itself.

struct UniversalControlRelayKeyPressEncoding {
	static let sideAwareCapability = "kp2"
	static let capabilityLine = "caps \(sideAwareCapability)"

	static func line(keyCode: CGKeyCode, modifiers: CGEventFlags) -> String {
		"kp \(keyCode) \(modifiers.rawValue)"
	}

	static func line(
		keyCode: CGKeyCode,
		modifiers: ModifierFlags,
		peerSupportsKP2: Bool
	) -> String {
		guard peerSupportsKP2, hasExplicitSide(modifiers) else {
			return line(keyCode: keyCode, modifiers: modifiers.cgEventFlags)
		}

		return "kp2 \(keyCode) \(modifiers.cgEventFlags.rawValue) " +
			"\(wireValue(for: modifiers.commandSide)) " +
			"\(wireValue(for: modifiers.optionSide)) " +
			"\(wireValue(for: modifiers.shiftSide)) " +
			"\(wireValue(for: modifiers.controlSide))"
	}

	static func supportsSideAwareKeyPress(_ parts: [Substring]) -> Bool {
		guard parts.first == "caps" else { return false }
		return parts.dropFirst().contains { $0 == sideAwareCapability }
	}

	private static func hasExplicitSide(_ modifiers: ModifierFlags) -> Bool {
		modifiers.commandSide != nil ||
			modifiers.optionSide != nil ||
			modifiers.shiftSide != nil ||
			modifiers.controlSide != nil
	}

	private static func wireValue(for side: ModifierSide?) -> Int {
		switch side {
		case .left: return 1
		case .right: return 2
		case .none: return 0
		}
	}
}

struct UniversalControlRelayUIStateEchoPolicy {
	static func payload(
		keyboardVisible: Bool,
		keyboardNavigationActive: Bool,
		directoryNavigatorVisible: Bool,
		swipePredictionsVisible: Bool
	) -> String {
		"uiState \(keyboardVisible ? 1 : 0) \(keyboardNavigationActive ? 1 : 0) \(directoryNavigatorVisible ? 1 : 0) \(swipePredictionsVisible ? 1 : 0)"
	}

	static func shouldSend(payload: String, lastSentPayload: String?) -> Bool {
		payload != lastSentPayload
	}
}

struct UniversalControlHandoffEdgeDefaults {
	static let fallbackLocalEdges: [UniversalControlMouseRelay.HandoffEdge] = [.left, .right]

	static func localEdges(configuredRawValue: String?) -> [UniversalControlMouseRelay.HandoffEdge] {
		if let configuredRawValue,
		   let edge = UniversalControlMouseRelay.HandoffEdge(rawValue: configuredRawValue) {
			return [edge]
		}
		return fallbackLocalEdges
	}
}

struct UniversalControlRemoteMouseMovementPolicy {
	struct Movement: Equatable {
		let point: CGPoint
		let dx: Int
		let dy: Int

		var shouldPostEvent: Bool {
			dx != 0 || dy != 0
		}
	}

	static func boundedMovement(
		current: CGPoint,
		requestedDX: Int,
		requestedDY: Int,
		bounds: CGRect
	) -> Movement {
		guard isUsable(bounds), contains(current, in: bounds) else {
			return Movement(
				point: statusPoint(current: current, bounds: bounds),
				dx: 0,
				dy: 0
			)
		}

		let next = clampedPoint(
			CGPoint(
				x: current.x + CGFloat(requestedDX),
				y: current.y + CGFloat(requestedDY)
			),
			to: bounds
		)
		return Movement(
			point: next,
			dx: Int((next.x - current.x).rounded()),
			dy: Int((next.y - current.y).rounded())
		)
	}

	static func statusPoint(current: CGPoint, bounds: CGRect) -> CGPoint {
		guard isUsable(bounds) else { return current }
		return clampedPoint(current, to: bounds)
	}

	private static func contains(_ point: CGPoint, in bounds: CGRect) -> Bool {
		point.x >= bounds.minX
			&& point.x <= bounds.maxX - 1
			&& point.y >= bounds.minY
			&& point.y <= bounds.maxY - 1
	}

	private static func clampedPoint(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
		CGPoint(
			x: max(bounds.minX, min(bounds.maxX - 1, point.x)),
			y: max(bounds.minY, min(bounds.maxY - 1, point.y))
		)
	}

	private static func isUsable(_ bounds: CGRect) -> Bool {
		!bounds.isNull && !bounds.isInfinite && bounds.width >= 1 && bounds.height >= 1
	}
}
