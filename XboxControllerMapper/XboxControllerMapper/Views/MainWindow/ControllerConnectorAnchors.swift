import SwiftUI

/// Bounds remain the default for existing controller layouts. Curved controls
/// can provide a physical port instead of connecting to their bounding box.
enum ConnectorAttachment: Equatable {
	case bounds
	case horizontalEdge
	case circle
	case point(UnitPoint)

	func point(in rect: CGRect, towards target: CGPoint) -> CGPoint? {
		switch self {
		case .bounds: return nil
		case .horizontalEdge:
			return CGPoint(x: target.x < rect.midX ? rect.minX : rect.maxX, y: rect.midY)
		case .circle:
			// ConnectorPath has horizontal end tangents: meet the circle at its
			// left/right midpoint so the curve leaves the visible rim cleanly.
			let radius = min(rect.width, rect.height) / 2
			return CGPoint(x: rect.midX + (target.x < rect.midX ? -radius : radius), y: rect.midY)
		case .point(let point):
			return CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
		}
	}
}

struct ConnectorEndpoint {
	let button: ControllerButton
	let role: ConnectorRole
	let anchor: Anchor<CGRect>
	var attachment: ConnectorAttachment = .bounds
}

struct ControllerButtonAnchorPreferenceKey: PreferenceKey {
	static var defaultValue: [ConnectorEndpoint] = []
	static func reduce(value: inout [ConnectorEndpoint], nextValue: () -> [ConnectorEndpoint]) {
		value.append(contentsOf: nextValue())
	}
}

extension View {
	func controllerAnchor(_ button: ControllerButton, role: ConnectorRole,
		attachment: ConnectorAttachment = .bounds) -> some View {
		controllerAnchor([button], role: role, attachment: attachment)
	}

	/// Shared controls emit every identity from one preference; stacking
	/// individual anchor preferences can discard earlier endpoints.
	func controllerAnchor(_ buttons: [ControllerButton], role: ConnectorRole,
		attachment: ConnectorAttachment = .bounds) -> some View {
		anchorPreference(key: ControllerButtonAnchorPreferenceKey.self, value: .bounds) { anchor in
			buttons.map { ConnectorEndpoint(button: $0, role: role, anchor: anchor, attachment: attachment) }
		}
	}
}
