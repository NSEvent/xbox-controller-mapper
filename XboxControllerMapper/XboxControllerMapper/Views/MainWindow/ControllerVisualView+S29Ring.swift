import SwiftUI

extension ControllerVisualView {
	var s29RingLayout: some View {
		HStack(alignment: .center, spacing: 38) {
			VStack(alignment: .trailing, spacing: 16) {
				referenceGroup(title: "Swipe / Hold", buttons: ControllerButton.s29RingDirectionButtons)
			}
			.frame(width: 250)

			VStack(spacing: 12) {
				// Chip above the card so it never covers the Camera/Home buttons
				// along the card's bottom edge.
				layerScopeChip(nameMaxWidth: 120)

				S29RingMinimapView(
					pressedButtons: Set(ControllerButton.s29RingButtons.filter(isPressed)),
					selectedButton: selectedButton,
					swapSourceButton: swapFirstButton,
					onButtonTap: onButtonTap,
					onButtonHover: handleButtonHover,
					onSwapRequest: performSwap
				)
				.accessibilityHidden(true)

				Text("BLUETOOTH BUTTON RING")
					.font(.system(size: 9, weight: .heavy, design: .rounded))
					.tracking(1.2)
					.foregroundStyle(.secondary)
			}
			.frame(width: S29RingMinimapView.previewSize.width)

			VStack(alignment: .leading, spacing: 16) {
				referenceGroup(title: "Buttons", buttons: ControllerButton.s29RingActionButtons)
			}
			.frame(width: 250)
		}
		.padding(28)
	}
}

/// Front-on drawing of the S29 button ring (Novzix "TikTok Scrolling Ring
/// S29"): a black oval face plate on an open finger band, four curved grey
/// arrow keys around an engraved center key, and a bottom row of Camera,
/// Heart and Home keys. Proportions follow the product photos.
///
/// The center (play/pause) and Heart keys are drawn for recognizability but
/// aren't mappable — the ring doesn't report them as distinct controls.
struct S29RingMinimapView: View {
	static let previewSize = CGSize(width: 300, height: 300)

	let pressedButtons: Set<ControllerButton>
	var selectedButton: ControllerButton? = nil
	var swapSourceButton: ControllerButton? = nil
	var onButtonTap: (ControllerButton) -> Void = { _ in }
	var onButtonHover: (ControllerButton, Bool) -> Void = { _, _ in }
	var onSwapRequest: ((ControllerButton, ControllerButton) -> Void)?

	// Geometry (points in the 300×300 preview frame).
	private static let plateCenter = CGPoint(x: 150, y: 134)
	private static let plateSize = CGSize(width: 180, height: 236)
	private static let clusterCenter = CGPoint(x: 150, y: 110)
	private static let arcInnerRadius: CGFloat = 34
	private static let arcOuterRadius: CGFloat = 70
	/// Angular width of each arrow key; the rest is the gap between keys.
	private static let arcSpan: Double = 68
	private static let centerKeySize: CGFloat = 52
	private static let bottomRowY: CGFloat = 206
	private static let bottomKeySize = CGSize(width: 46, height: 40)
	private static let bottomKeySpacing: CGFloat = 52

	private static let keyTop = Color(white: 0.86)
	private static let keyBottom = Color(white: 0.68)
	private static let glyphColor = Color.white

	var body: some View {
		ZStack {
			fingerBand
			facePlate
			statusPinhole

			arrowKey(.dpadUp, angle: -90)
			arrowKey(.dpadRight, angle: 0)
			arrowKey(.dpadDown, angle: 90)
			arrowKey(.dpadLeft, angle: 180)
			centerKey

			bottomKey(.s29Camera, systemImage: "camera", offset: -1)
			bottomKeyDecoration(systemImage: "heart", offset: 0)
			bottomKey(.s29Home, systemImage: "house", offset: 1)
		}
		.frame(width: Self.previewSize.width, height: Self.previewSize.height)
	}

	// MARK: Body

	/// The open finger band, seen from slightly above: a flattened loop
	/// hanging below the plate with its adjustable opening at the bottom.
	/// The loop's top half is hidden behind the plate.
	private var fingerBand: some View {
		let style = StrokeStyle(lineWidth: 14, lineCap: .round)
		let gradient = LinearGradient(
			colors: [Color(white: 0.24), Color(white: 0.06)],
			startPoint: .top, endPoint: .bottom
		)

		// Ellipse trim starts at 3 o'clock and runs clockwise, so 0.25 is
		// 6 o'clock: draw both sides of the loop, leaving that gap open.
		return ZStack {
			Ellipse().trim(from: 0.29, to: 1.0).stroke(gradient, style: style)
			Ellipse().trim(from: 0.0, to: 0.21).stroke(gradient, style: style)
		}
		.frame(width: 150, height: 74)
		.position(x: Self.plateCenter.x, y: Self.plateCenter.y + Self.plateSize.height / 2 + 4)
		.shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 3)
	}

	private var facePlate: some View {
		// Rounder at the top around the arrow cluster; tighter bottom corners
		// so the full-width Camera / Heart / Home row sits inside the plate.
		let plate = UnevenRoundedRectangle(
			topLeadingRadius: Self.plateSize.width * 0.46,
			bottomLeadingRadius: 40,
			bottomTrailingRadius: 40,
			topTrailingRadius: Self.plateSize.width * 0.46,
			style: .continuous
		)

		return plate
			.fill(
				LinearGradient(
					colors: [Color(white: 0.20), Color(white: 0.09), Color(white: 0.05)],
					startPoint: .top, endPoint: .bottom
				)
			)
			.overlay(
				// Soft top sheen on the glossy plastic
				plate
					.fill(
						LinearGradient(
							colors: [Color.white.opacity(0.10), .clear],
							startPoint: .top, endPoint: .center
						)
					)
			)
			.overlay(plate.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
			.frame(width: Self.plateSize.width, height: Self.plateSize.height)
			.position(Self.plateCenter)
			.shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 8)
	}

	private var statusPinhole: some View {
		Circle()
			.fill(Color.black)
			.overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
			.frame(width: 5, height: 5)
			.position(x: Self.plateCenter.x + Self.plateSize.width / 2 - 11, y: 160)
	}

	// MARK: Keys

	private func keyFill(active: Bool) -> LinearGradient {
		LinearGradient(
			colors: active
				? [Color.accentColor, Color.accentColor.opacity(0.78)]
				: [Self.keyTop, Self.keyBottom],
			startPoint: .top, endPoint: .bottom
		)
	}

	private func arrowKey(_ button: ControllerButton, angle: Double) -> some View {
		let pressed = pressedButtons.contains(button)
		let active = isActive(button)
		let geometry = S29ArcKeyGeometry(
			innerRadius: Self.arcInnerRadius,
			outerRadius: Self.arcOuterRadius,
			centerAngle: angle,
			span: Self.arcSpan
		)
		let shape = S29ArcKeyShape(geometry: geometry)
		let glyphPoint = geometry.localPoint(radius: (Self.arcInnerRadius + Self.arcOuterRadius) / 2)

		return ZStack {
			shape
				.fill(keyFill(active: active))
				.overlay(shape.stroke(Color.black.opacity(0.28), lineWidth: 0.8))
				.shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 2)
			Image(systemName: "arrowtriangle.up.fill")
				.font(.system(size: 11, weight: .bold))
				.foregroundStyle(active ? Color.white : Self.glyphColor)
				.shadow(color: .black.opacity(active ? 0 : 0.35), radius: 0.5, x: 0, y: 0.5)
				.rotationEffect(.degrees(angle + 90))
				.position(glyphPoint)
		}
		.frame(width: geometry.bounds.width, height: geometry.bounds.height)
		.scaleEffect(pressed ? 0.94 : 1.0)
		.modifier(S29RingTargetInteraction(
			button: button,
			shape: shape,
			isSwapSource: swapSourceButton == button,
			onButtonTap: onButtonTap,
			onButtonHover: onButtonHover,
			onSwapRequest: onSwapRequest
		))
		.position(
			x: Self.clusterCenter.x + geometry.bounds.midX,
			y: Self.clusterCenter.y + geometry.bounds.midY
		)
		.animation(.spring(response: 0.22, dampingFraction: 0.62), value: pressed)
	}

	private var centerKey: some View {
		ZStack {
			Circle()
				.fill(keyFill(active: false))
				.overlay(Circle().stroke(Color.black.opacity(0.28), lineWidth: 0.8))
				.shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 2)
			Circle()
				.stroke(Color.white.opacity(0.9), lineWidth: 2)
				.shadow(color: .black.opacity(0.3), radius: 0.5, x: 0, y: 0.5)
				.frame(width: Self.centerKeySize * 0.48, height: Self.centerKeySize * 0.48)
		}
		.frame(width: Self.centerKeySize, height: Self.centerKeySize)
		.position(Self.clusterCenter)
		.allowsHitTesting(false)
	}

	private func bottomKeyShape() -> RoundedRectangle {
		RoundedRectangle(cornerRadius: 11, style: .continuous)
	}

	private func bottomKeyFace(systemImage: String, active: Bool) -> some View {
		let shape = bottomKeyShape()

		return ZStack {
			shape
				.fill(keyFill(active: active))
				.overlay(shape.stroke(Color.black.opacity(0.28), lineWidth: 0.8))
				.shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 2)
			Image(systemName: systemImage)
				.font(.system(size: 15, weight: .semibold))
				.foregroundStyle(active ? Color.white : Self.glyphColor)
				.shadow(color: .black.opacity(active ? 0 : 0.35), radius: 0.5, x: 0, y: 0.5)
		}
		.frame(width: Self.bottomKeySize.width, height: Self.bottomKeySize.height)
	}

	private func bottomKeyPosition(offset: CGFloat) -> CGPoint {
		CGPoint(x: Self.plateCenter.x + offset * Self.bottomKeySpacing, y: Self.bottomRowY)
	}

	private func bottomKey(_ button: ControllerButton, systemImage: String, offset: CGFloat) -> some View {
		let pressed = pressedButtons.contains(button)

		return bottomKeyFace(systemImage: systemImage, active: isActive(button))
			.scaleEffect(pressed ? 0.94 : 1.0)
			.modifier(S29RingTargetInteraction(
				button: button,
				shape: bottomKeyShape(),
				isSwapSource: swapSourceButton == button,
				onButtonTap: onButtonTap,
				onButtonHover: onButtonHover,
				onSwapRequest: onSwapRequest
			))
			.position(bottomKeyPosition(offset: offset))
			.animation(.spring(response: 0.22, dampingFraction: 0.62), value: pressed)
	}

	private func bottomKeyDecoration(systemImage: String, offset: CGFloat) -> some View {
		bottomKeyFace(systemImage: systemImage, active: false)
			.position(bottomKeyPosition(offset: offset))
			.allowsHitTesting(false)
	}

	private func isActive(_ button: ControllerButton) -> Bool {
		pressedButtons.contains(button) || selectedButton == button
	}
}

/// An annular-sector arrow key, described relative to the key cluster's
/// center, with `bounds` (also cluster-relative) so each key can get its own
/// tight frame — connector anchors attach to the key, not the whole cluster.
struct S29ArcKeyGeometry {
	let innerRadius: CGFloat
	let outerRadius: CGFloat
	/// Degrees, 0 = right, 90 = down (screen coordinates).
	let centerAngle: Double
	let span: Double

	var startAngle: Double { centerAngle - span / 2 }
	var endAngle: Double { centerAngle + span / 2 }

	var bounds: CGRect {
		var points: [CGPoint] = []
		for step in 0...24 {
			let angle = startAngle + span * Double(step) / 24
			points.append(Self.point(radius: innerRadius, degrees: angle))
			points.append(Self.point(radius: outerRadius, degrees: angle))
		}
		let xs = points.map(\.x)
		let ys = points.map(\.y)
		return CGRect(
			x: xs.min()!, y: ys.min()!,
			width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!
		)
	}

	/// A point on the key's center line, in the key's local frame.
	func localPoint(radius: CGFloat) -> CGPoint {
		let point = Self.point(radius: radius, degrees: centerAngle)
		return CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
	}

	static func point(radius: CGFloat, degrees: Double) -> CGPoint {
		let radians = degrees * .pi / 180
		return CGPoint(x: radius * CGFloat(cos(radians)), y: radius * CGFloat(sin(radians)))
	}
}

/// Rounded annular sector drawn in the key's local frame.
struct S29ArcKeyShape: Shape {
	let geometry: S29ArcKeyGeometry
	var cornerInset: CGFloat = 5

	func path(in rect: CGRect) -> Path {
		let origin = CGPoint(x: -geometry.bounds.minX, y: -geometry.bounds.minY)
		// Shrink the sector by the corner radius, then round it back out with a
		// round-joined stroke so every corner is softened evenly.
		let inset = cornerInset
		let inner = geometry.innerRadius + inset
		let outer = geometry.outerRadius - inset
		let midRadius = (geometry.innerRadius + geometry.outerRadius) / 2
		let angularInset = Double(inset / midRadius) * 180 / .pi
		let start = Angle(degrees: geometry.startAngle + angularInset)
		let end = Angle(degrees: geometry.endAngle - angularInset)

		var core = Path()
		core.addArc(center: origin, radius: outer, startAngle: start, endAngle: end, clockwise: false)
		core.addArc(center: origin, radius: inner, startAngle: end, endAngle: start, clockwise: true)
		core.closeSubpath()

		let rounded = core.strokedPath(StrokeStyle(lineWidth: inset * 2, lineCap: .round, lineJoin: .round))
		// A true union: simply appending the stroke outline would leave a
		// winding-rule hole along the seam.
		return core.union(rounded)
	}
}

private struct S29RingTargetInteraction<KeyShape: Shape>: ViewModifier {
	let button: ControllerButton
	let shape: KeyShape
	let isSwapSource: Bool
	let onButtonTap: (ControllerButton) -> Void
	let onButtonHover: (ControllerButton, Bool) -> Void
	let onSwapRequest: ((ControllerButton, ControllerButton) -> Void)?

	func body(content: Content) -> some View {
		content
			.overlay(
				shape
					.stroke(Color.orange, lineWidth: 3)
					.opacity(isSwapSource ? 1 : 0)
			)
			.contentShape(shape)
			.controllerAnchor(button, role: .controller)
			.onTapGesture { onButtonTap(button) }
			.onHover { hovering in onButtonHover(button, hovering) }
			.swappable(button, onSwap: onSwapRequest)
	}
}
