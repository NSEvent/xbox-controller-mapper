import SwiftUI

extension ControllerVisualView {
	var footPedalLayout: some View {
		HStack(alignment: .center, spacing: 38) {
			VStack(alignment: .trailing, spacing: 16) {
				referenceGroup(title: "Left", buttons: [.footPedalLeft])
			}
			.frame(width: 250)

			VStack(spacing: 12) {
				layerScopeChip(nameMaxWidth: 120)

				FootPedalMinimapView(
					pressedButtons: Set(ControllerButton.footPedalButtons.filter(isPressed)),
					selectedButton: selectedButton,
					swapSourceButton: swapFirstButton,
					onButtonTap: onButtonTap,
					onButtonHover: handleButtonHover,
					onSwapRequest: performSwap
				)
				.accessibilityHidden(true)

				referenceGroup(title: "Middle", buttons: [.footPedalMiddle])
					.frame(width: 250)

				Text("VEC INFINITY")
					.font(.system(size: 9, weight: .heavy, design: .rounded))
					.tracking(1.2)
					.foregroundStyle(.secondary)
			}
			.frame(width: FootPedalMinimapView.previewSize.width)

			VStack(alignment: .leading, spacing: 16) {
				referenceGroup(title: "Right", buttons: [.footPedalRight])
			}
			.frame(width: 250)
		}
		.padding(28)
	}
}

/// Top-down drawing of the VEC Infinity 3 (IN-USB-3), following the product
/// photos: one rounded charcoal body split into three full-length pedals — a
/// broad center pedal between two narrow side pedals with gently bowed outer
/// edges. A seam crosses all three at the rear third; the rear is smooth, the
/// front (where the foot rests) textured, and the oval "VEC INFINITY 3" badge
/// sits on the center pedal's rear. The cable leaves the rear edge.
struct FootPedalMinimapView: View {
	static let previewSize = CGSize(width: 300, height: 220)

	let pressedButtons: Set<ControllerButton>
	var selectedButton: ControllerButton? = nil
	var swapSourceButton: ControllerButton? = nil
	var onButtonTap: (ControllerButton) -> Void = { _ in }
	var onButtonHover: (ControllerButton, Bool) -> Void = { _, _ in }
	var onSwapRequest: ((ControllerButton, ControllerButton) -> Void)?

	/// Body frame inside the preview; the cable stub uses the space above it.
	static let bodyRect = CGRect(x: 22, y: 40, width: 256, height: 168)
	/// Fraction of the body depth where the rear seam crosses the pedals.
	static let seamFraction: CGFloat = 0.34
	private static let groove: CGFloat = 3

	/// Left and right edges of each pedal in body-local x, as (rear, front)
	/// pairs. The center pedal flares wider toward the front, so the side
	/// pedals' inner edges curve outward; outer edges overshoot the body so
	/// its bowed sides stay inside the side pedals.
	static func edges(for button: ControllerButton) -> (left: FootPedalEdge, right: FootPedalEdge) {
		let width = bodyRect.width
		let rear: CGFloat = 46
		let front: CGFloat = 38
		let outer = FootPedalEdge(rear: -12, front: -12)
		switch button {
		case .footPedalLeft:
			return (outer, FootPedalEdge(rear: rear, front: front))
		case .footPedalRight:
			return (FootPedalEdge(rear: width - rear, front: width - front), outer.mirrored(width: width))
		default:
			return (
				FootPedalEdge(rear: rear + groove, front: front + groove),
				FootPedalEdge(rear: width - rear - groove, front: width - front - groove)
			)
		}
	}

	var body: some View {
		ZStack {
			cable
			FootPedalBodyShape()
				.fill(Color(white: 0.05))
				.frame(width: Self.bodyRect.width, height: Self.bodyRect.height)
				.position(x: Self.bodyRect.midX, y: Self.bodyRect.midY)
				.shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 6)
			ForEach(ControllerButton.footPedalButtons, id: \.self) { button in
				pedal(button)
			}
			badge
		}
		.frame(width: Self.previewSize.width, height: Self.previewSize.height)
	}

	private var cable: some View {
		Path { path in
			let start = CGPoint(x: Self.bodyRect.minX + 92, y: Self.bodyRect.minY + 2)
			path.move(to: start)
			path.addCurve(
				to: CGPoint(x: Self.bodyRect.minX + 150, y: 2),
				control1: CGPoint(x: start.x - 14, y: 18),
				control2: CGPoint(x: start.x + 70, y: 26)
			)
		}
		.stroke(Color(white: 0.12), style: StrokeStyle(lineWidth: 5, lineCap: .round))
	}

	private var badge: some View {
		VStack(spacing: -1) {
			Text("VEC").font(.system(size: 8, weight: .heavy))
			Text("INFINITY 3").font(.system(size: 6.5, weight: .bold))
		}
		.foregroundStyle(Color.white.opacity(0.42))
		.frame(width: 64, height: 24)
		.background(Ellipse().fill(Color.black.opacity(0.18)))
		.overlay(Ellipse().stroke(Color.white.opacity(0.22), lineWidth: 0.8))
		.position(x: Self.bodyRect.midX, y: Self.bodyRect.minY + Self.bodyRect.height * Self.seamFraction / 2 + 2)
		.allowsHitTesting(false)
	}

	private func pedal(_ button: ControllerButton) -> some View {
		let pressed = pressedButtons.contains(button)
		let active = pressed || selectedButton == button
		let edges = Self.edges(for: button)
		let clampedMin = max(edges.left.minX, 0)
		let clampedMax = min(edges.right.maxX, Self.bodyRect.width)
		let shape = FootPedalSegmentShape(left: edges.left, right: edges.right)
		let seamY = Self.bodyRect.height * Self.seamFraction

		return ZStack(alignment: .topLeading) {
			shape.fill(
				LinearGradient(
					colors: active
						? [Color.accentColor.opacity(0.85), Color.accentColor]
						: [Color(white: 0.30), Color(white: 0.24), Color(white: 0.17)],
					startPoint: .top, endPoint: .bottom
				)
			)
			// Textured front zone below the seam.
			shape.fill(Color.black.opacity(active ? 0.08 : 0.16))
				.mask(Rectangle().padding(.top, seamY))
			// Seam groove with a light catch on its lower lip.
			Rectangle()
				.fill(Color.black.opacity(0.55))
				.frame(height: 1.5)
				.offset(y: seamY - 1)
				.mask(shape)
			Rectangle()
				.fill(Color.white.opacity(0.16))
				.frame(height: 1)
				.offset(y: seamY + 1)
				.mask(shape)
			shape.stroke(Color.white.opacity(active ? 0.3 : 0.1), lineWidth: 0.8)
		}
		.frame(width: clampedMax - clampedMin, height: Self.bodyRect.height)
		.brightness(pressed ? -0.06 : 0)
		.scaleEffect(pressed ? 0.97 : 1.0, anchor: .top)
		.overlay(shape.stroke(Color.orange, lineWidth: 3).opacity(swapSourceButton == button ? 1 : 0))
		.contentShape(shape)
		.controllerAnchor(button, role: .controller)
		.onTapGesture { onButtonTap(button) }
		.onHover { hovering in onButtonHover(button, hovering) }
		.swappable(button, onSwap: onSwapRequest)
		.position(x: Self.bodyRect.minX + (clampedMin + clampedMax) / 2, y: Self.bodyRect.midY)
		.animation(.spring(response: 0.22, dampingFraction: 0.62), value: pressed)
	}
}

/// The pedal body in its own frame: a wide rounded rectangle whose left and
/// right edges bow slightly outward, as on the real IN-USB-3 shell.
private struct FootPedalBodyShape: Shape {
	func path(in rect: CGRect) -> Path {
		Self.outline(width: rect.width, height: rect.height)
	}

	static func outline(width w: CGFloat, height h: CGFloat) -> Path {
		let r: CGFloat = 26
		let bow: CGFloat = 5
		var path = Path()
		path.move(to: CGPoint(x: r, y: 0))
		path.addLine(to: CGPoint(x: w - r, y: 0))
		path.addQuadCurve(to: CGPoint(x: w + 1, y: r), control: CGPoint(x: w, y: 0))
		path.addQuadCurve(to: CGPoint(x: w, y: h - r), control: CGPoint(x: w + bow, y: h / 2))
		path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
		path.addLine(to: CGPoint(x: r, y: h))
		path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
		path.addQuadCurve(to: CGPoint(x: -1, y: r), control: CGPoint(x: -bow, y: h / 2))
		path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
		path.closeSubpath()
		return path
	}
}

/// A pedal's side boundary, running from the rear edge to the front edge.
struct FootPedalEdge {
	let rear: CGFloat
	let front: CGFloat

	var minX: CGFloat { min(rear, front) }
	var maxX: CGFloat { max(rear, front) }

	func mirrored(width: CGFloat) -> FootPedalEdge {
		FootPedalEdge(rear: width - rear, front: width - front)
	}

	/// Holds the rear line through the seam, then eases into the front flare.
	func control(height: CGFloat) -> CGPoint {
		CGPoint(x: rear, y: height * 0.55)
	}
}

/// One pedal: the body outline clipped between two edges, drawn in the
/// pedal's own frame so each pedal gets a tight hit area and connector anchor.
private struct FootPedalSegmentShape: Shape {
	let left: FootPedalEdge
	let right: FootPedalEdge

	func path(in rect: CGRect) -> Path {
		let body = FootPedalMinimapView.bodyRect
		let h = body.height
		let outline = FootPedalBodyShape.outline(width: body.width, height: h)
		var slab = Path()
		slab.move(to: CGPoint(x: left.rear, y: -2))
		slab.addLine(to: CGPoint(x: right.rear, y: -2))
		slab.addQuadCurve(to: CGPoint(x: right.front, y: h + 2), control: right.control(height: h))
		slab.addLine(to: CGPoint(x: left.front, y: h + 2))
		slab.addQuadCurve(to: CGPoint(x: left.rear, y: -2), control: left.control(height: h))
		slab.closeSubpath()
		let originX = max(left.minX, 0)
		return outline.intersection(slab)
			.applying(CGAffineTransform(translationX: -originX, y: 0))
	}
}
