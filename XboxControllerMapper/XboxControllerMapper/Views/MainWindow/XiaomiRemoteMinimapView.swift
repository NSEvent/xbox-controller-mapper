import SwiftUI

/// Measured from the straight-on RC003 product photo retained in
/// docs/internal/controller-references/xiaomi-rc003-front.jpg. All coordinates
/// are fractions of the 145×570 px body, not an imagined Siri Remote layout.
enum XiaomiRemoteMinimapLayout {
	static let bodyWidth: CGFloat = 126
	static let aspectRatio: CGFloat = 0.2548
	static let bodyHeight = bodyWidth / aspectRatio
	static let bodySize = CGSize(width: bodyWidth, height: bodyHeight)
	static let previewSize = CGSize(width: 190, height: bodyHeight + 16)
	static let ringCenter = CGPoint(x: 0.497, y: 0.226)
	static let ringRadius: CGFloat = bodyWidth * 60 / 145
	static let centerRadius: CGFloat = bodyWidth * 31 / 145
	static let keyDiameter: CGFloat = bodyWidth * 47 / 145
	static let topKeyDiameter: CGFloat = bodyWidth * 32 / 145

	static func arrowGeometry(for button: ControllerButton) -> S29ArcKeyGeometry {
		let angle: Double
		switch button {
		case .dpadUp: angle = -90
		case .dpadDown: angle = 90
		case .dpadLeft: angle = 180
		default: angle = 0
		}
		return S29ArcKeyGeometry(innerRadius: centerRadius + 2,
			outerRadius: ringRadius - 1, centerAngle: angle, span: 86)
	}

	static func arrowAttachment(for button: ControllerButton) -> ConnectorAttachment {
		let geometry = arrowGeometry(for: button)
		let point = geometry.localPoint(radius: ringRadius)
		return .point(UnitPoint(x: point.x / geometry.bounds.width, y: point.y / geometry.bounds.height))
	}
	static let keyCenters: [ControllerButton: CGPoint] = [
		.xiaomiPower: CGPoint(x: 0.241, y: 0.067),
		.xiaomiMicrophone: CGPoint(x: 0.759, y: 0.067),
		.xiaomiOK: ringCenter,
		.xiaomiBack: CGPoint(x: 0.290, y: 0.381),
		.xiaomiHome: CGPoint(x: 0.290, y: 0.476),
		.xiaomiMenu: CGPoint(x: 0.290, y: 0.575),
		.xiaomiVolumeUp: CGPoint(x: 0.703, y: 0.381),
		.xiaomiVolumeDown: CGPoint(x: 0.703, y: 0.478),
		.xiaomiTV: CGPoint(x: 0.703, y: 0.575),
	]
}

struct XiaomiRemoteMinimapView: View {
	static let previewSize = XiaomiRemoteMinimapLayout.previewSize
	let pressedButtons: Set<ControllerButton>
	var selectedButton: ControllerButton? = nil
	var swapSourceButton: ControllerButton? = nil
	var onButtonTap: (ControllerButton) -> Void = { _ in }
	var onButtonHover: (ControllerButton, Bool) -> Void = { _, _ in }
	var onSwapRequest: ((ControllerButton, ControllerButton) -> Void)?
	private typealias Layout = XiaomiRemoteMinimapLayout

	var body: some View {
		ZStack {
			ZStack {
				XiaomiRemoteBodyShape()
					.fill(LinearGradient(stops: [
						.init(color: Color(white: 0.52), location: 0),
						.init(color: Color(white: 0.94), location: 0.035),
						.init(color: Color(white: 0.70), location: 0.10),
						.init(color: Color(white: 0.75), location: 0.88),
						.init(color: Color(white: 0.48), location: 0.98),
						.init(color: Color(white: 0.26), location: 1),
					], startPoint: .leading, endPoint: .trailing))
					.overlay(XiaomiRemoteBodyShape().stroke(Color.black.opacity(0.30), lineWidth: 0.7))
					.shadow(color: .black.opacity(0.22), radius: 6, x: 2, y: 4)

				Circle().fill(keyGradient(active: false))
					.overlay(Circle().stroke(Color.black.opacity(0.8), lineWidth: 1))
					.frame(width: Layout.ringRadius * 2, height: Layout.ringRadius * 2)
					.position(point(Layout.ringCenter))
				arrow(.dpadUp)
				arrow(.dpadRight)
				arrow(.dpadDown)
				arrow(.dpadLeft)

				// Physical center has no printed Play/Pause or OK glyph.
				key(.xiaomiOK, diameter: Layout.centerRadius * 2, showGlyph: false)
				key(.xiaomiPower, diameter: Layout.topKeyDiameter, silver: true)
				key(.xiaomiMicrophone, diameter: Layout.topKeyDiameter, silver: true)
				key(.xiaomiBack, diameter: Layout.keyDiameter)
				key(.xiaomiHome, diameter: Layout.keyDiameter)
				key(.xiaomiMenu, diameter: Layout.keyDiameter)
				key(.xiaomiTV, diameter: Layout.keyDiameter)

				// The volume rocker is a single capsule with two round key faces.
				Capsule().fill(Color(white: 0.13))
					.frame(width: Layout.keyDiameter, height: Layout.keyDiameter + Layout.bodyHeight * 0.097)
					.position(point(CGPoint(x: 0.703, y: 0.4295)))
				key(.xiaomiVolumeUp, diameter: Layout.keyDiameter)
				key(.xiaomiVolumeDown, diameter: Layout.keyDiameter)

				Text("N").font(.system(size: 7, weight: .medium))
					.foregroundStyle(Color.black.opacity(0.58))
					.overlay(Rectangle().stroke(Color.black.opacity(0.45), lineWidth: 0.5).padding(-1))
					.position(point(CGPoint(x: 0.497, y: 0.748)))
				Text("xiaomi").font(.system(size: 11, weight: .medium, design: .rounded))
					.foregroundStyle(Color.black.opacity(0.65))
					.position(point(CGPoint(x: 0.497, y: 0.919)))
			}
			.frame(width: Layout.bodyWidth, height: Layout.bodyHeight)
		}
		.frame(width: Self.previewSize.width, height: Self.previewSize.height)
	}

	private func point(_ normalized: CGPoint) -> CGPoint {
		CGPoint(x: normalized.x * Layout.bodyWidth, y: normalized.y * Layout.bodyHeight)
	}
	private func active(_ button: ControllerButton) -> Bool {
		pressedButtons.contains(button) || selectedButton == button
	}
	private func keyGradient(active: Bool) -> LinearGradient {
		LinearGradient(colors: active ? [Color.accentColor, Color.accentColor.opacity(0.78)]
			: [Color(white: 0.19), Color(white: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
	}
	private func key(_ button: ControllerButton, diameter: CGFloat, silver: Bool = false, showGlyph: Bool = true) -> some View {
		let pressed = pressedButtons.contains(button)
		return ZStack {
			Circle().fill(silver && !active(button)
				? LinearGradient(colors: [Color(white: 0.84), Color(white: 0.72)], startPoint: .top, endPoint: .bottom)
				: keyGradient(active: active(button)))
				.overlay(Circle().stroke(Color.black.opacity(0.70), lineWidth: 0.7))
				.shadow(color: .white.opacity(0.3), radius: 0.4, x: 0, y: -0.5)
			if showGlyph {
				XiaomiRemoteButtonGlyph(button: button)
					.font(.system(size: diameter * 0.37, weight: .regular))
					.foregroundStyle(silver && !active(button) ? Color.black.opacity(0.78) : Color(white: 0.78))
					.frame(width: diameter * 0.45, height: diameter * 0.45)
			}
		}
		.frame(width: diameter, height: diameter)
		.scaleEffect(pressed ? 0.96 : 1)
		.modifier(XiaomiRemoteTarget(button: button, shape: Circle(), swapSource: swapSourceButton,
			onTap: onButtonTap, onHover: onButtonHover, onSwap: onSwapRequest))
		.position(point(Layout.keyCenters[button]!))
		.animation(.spring(response: 0.20, dampingFraction: 0.72), value: pressed)
	}

	private func arrow(_ button: ControllerButton) -> some View {
		let geometry = Layout.arrowGeometry(for: button)
		let shape = S29ArcKeyShape(geometry: geometry, cornerInset: 1)
		let center = point(Layout.ringCenter)
		return ZStack {
			shape.fill(active(button) ? Color.accentColor : Color.clear)
			// The real ring has tiny cardinal marks, not printed arrow glyphs.
			Circle().fill(active(button) ? Color.white.opacity(0.9) : Color.black.opacity(0.8))
				.frame(width: 1.8, height: 1.8)
				.position(geometry.localPoint(radius: Layout.ringRadius - 5))
		}
		.frame(width: geometry.bounds.width, height: geometry.bounds.height)
		.modifier(XiaomiRemoteTarget(button: button, shape: shape, attachment: Layout.arrowAttachment(for: button), swapSource: swapSourceButton,
			onTap: onButtonTap, onHover: onButtonHover, onSwap: onSwapRequest))
		.position(x: center.x + geometry.bounds.midX, y: center.y + geometry.bounds.midY)
	}
}

private struct XiaomiRemoteTarget<KeyShape: Shape>: ViewModifier {
	let button: ControllerButton
	let shape: KeyShape
	var attachment: ConnectorAttachment = .circle
	let swapSource: ControllerButton?
	let onTap: (ControllerButton) -> Void
	let onHover: (ControllerButton, Bool) -> Void
	let onSwap: ((ControllerButton, ControllerButton) -> Void)?
	func body(content: Content) -> some View {
		content.overlay(shape.stroke(Color.orange, lineWidth: 2).opacity(swapSource == button ? 1 : 0))
			.contentShape(shape).controllerAnchor(button, role: .controller, attachment: attachment)
			.onTapGesture { onTap(button) }.onHover { onHover(button, $0) }
			.swappable(button, onSwap: onSwap).help(button.displayName)
	}
}

/// Cleaned photo silhouette: straight sides with approximately 2 px corners
/// in the 145 px reference width. Use a circular radius in view coordinates;
/// scaling a normalized corner by the tall body's height distorts its edge.
struct XiaomiRemoteBodyShape: Shape {
	func path(in rect: CGRect) -> Path {
		RoundedRectangle(cornerRadius: rect.width * 2 / 145, style: .circular).path(in: rect)
	}
}

extension ControllerVisualView {
	var xiaomiRemoteLayout: some View {
		HStack(alignment: .center, spacing: 26) {
			VStack(alignment: .trailing, spacing: 16) {
				referenceGroup(title: "Navigation", buttons: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight, .xiaomiOK])
				referenceGroup(title: "Home / Back / Menu", buttons: [.xiaomiBack, .xiaomiHome, .xiaomiMenu])
			}.frame(width: 250)
			VStack(spacing: 8) {
				layerScopeChip(nameMaxWidth: 135)
				XiaomiRemoteMinimapView(pressedButtons: Set(ControllerButton.xiaomiRemoteButtons.filter(isPressed)),
					selectedButton: selectedButton, swapSourceButton: swapFirstButton,
					onButtonTap: onButtonTap, onButtonHover: handleButtonHover, onSwapRequest: performSwap)
					.accessibilityHidden(true)
				Text("XIAOMI REMOTE 2 PRO").font(.system(size: 9, weight: .heavy, design: .rounded))
					.tracking(0.8).foregroundStyle(.secondary)
			}.frame(width: XiaomiRemoteMinimapView.previewSize.width)
			VStack(alignment: .leading, spacing: 16) {
				referenceGroup(title: "Remote", buttons: [.xiaomiPower, .xiaomiMicrophone])
				referenceGroup(title: "Volume", buttons: [.xiaomiVolumeUp, .xiaomiVolumeDown])
				referenceGroup(title: "TV", buttons: [.xiaomiTV])
			}.frame(width: 250)
		}.padding(24)
	}
}
