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

/// Simple drawn stand-in for the S29 ring (no product artwork exists): the
/// finger loop peeking above a touch face with the four swipe directions,
/// plus the Camera and Home buttons below it.
struct S29RingMinimapView: View {
	static let previewSize = CGSize(width: 300, height: 300)

	let pressedButtons: Set<ControllerButton>
	var selectedButton: ControllerButton? = nil
	var swapSourceButton: ControllerButton? = nil
	var onButtonTap: (ControllerButton) -> Void = { _ in }
	var onButtonHover: (ControllerButton, Bool) -> Void = { _, _ in }
	var onSwapRequest: ((ControllerButton, ControllerButton) -> Void)?

	var body: some View {
		ZStack {
			ringBand
			touchFace
			directionTarget(.dpadUp, systemImage: "chevron.up")
				.offset(y: -54)
			directionTarget(.dpadDown, systemImage: "chevron.down")
				.offset(y: 54)
			directionTarget(.dpadLeft, systemImage: "chevron.left")
				.offset(x: -64)
			directionTarget(.dpadRight, systemImage: "chevron.right")
				.offset(x: 64)
			actionTarget(.s29Camera, systemImage: "camera.fill", label: "CAM")
				.offset(x: -40, y: 116)
			actionTarget(.s29Home, systemImage: "house.fill", label: "HOME")
				.offset(x: 40, y: 116)
		}
		.frame(width: Self.previewSize.width, height: Self.previewSize.height)
	}

	private var ringBand: some View {
		ZStack {
			Circle()
				.strokeBorder(
					AngularGradient(
						colors: [
							Color(white: 0.34),
							Color(white: 0.12),
							Color(white: 0.28),
							Color(white: 0.08),
							Color(white: 0.34),
						],
						center: .center
					),
					lineWidth: 18
				)
				.frame(width: 120, height: 120)
				.shadow(color: .black.opacity(0.36), radius: 12, x: 0, y: 8)

			Circle()
				.strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
				.frame(width: 120, height: 120)
		}
		.offset(y: -88)
	}

	private var touchFace: some View {
		RoundedRectangle(cornerRadius: 34, style: .continuous)
			.fill(
				LinearGradient(
					colors: [
						Color(red: 0.17, green: 0.21, blue: 0.28),
						Color(red: 0.07, green: 0.09, blue: 0.13),
					],
					startPoint: .top,
					endPoint: .bottom
				)
			)
			.overlay(
				RoundedRectangle(cornerRadius: 34, style: .continuous)
					.strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
			)
			.frame(width: 200, height: 172)
	}

	private func isActive(_ button: ControllerButton) -> Bool {
		pressedButtons.contains(button) || selectedButton == button
	}

	private func directionTarget(_ button: ControllerButton, systemImage: String) -> some View {
		let pressed = pressedButtons.contains(button)
		let active = isActive(button)

		return ZStack {
			Circle()
				.fill(active ? Color.accentColor : Color.white.opacity(0.06))
			Image(systemName: systemImage)
				.font(.system(size: 17, weight: .bold))
				.foregroundStyle(active ? Color.white : Color.white.opacity(0.72))
		}
		.frame(width: 42, height: 42)
		.scaleEffect(pressed ? 0.9 : 1.0)
		.modifier(S29RingTargetInteraction(
			button: button,
			isSwapSource: swapSourceButton == button,
			onButtonTap: onButtonTap,
			onButtonHover: onButtonHover,
			onSwapRequest: onSwapRequest
		))
		.animation(.spring(response: 0.22, dampingFraction: 0.62), value: pressed)
	}

	private func actionTarget(_ button: ControllerButton, systemImage: String, label: String) -> some View {
		let pressed = pressedButtons.contains(button)
		let active = isActive(button)

		return ZStack {
			Circle()
				.fill(active ? Color.accentColor : Color(white: 0.16))
				.shadow(
					color: active ? Color.accentColor.opacity(0.44) : .black.opacity(0.35),
					radius: active ? 10 : 5,
					x: 0,
					y: 3
				)
			Circle()
				.strokeBorder(Color.white.opacity(active ? 0.72 : 0.22), lineWidth: 1.2)
			VStack(spacing: 1) {
				Image(systemName: systemImage)
					.font(.system(size: 14, weight: .bold))
				Text(label)
					.font(.system(size: 7, weight: .black, design: .rounded))
			}
			.foregroundStyle(active ? Color.white : Color.white.opacity(0.78))
		}
		.frame(width: 54, height: 54)
		.scaleEffect(pressed ? 0.92 : 1.0)
		.modifier(S29RingTargetInteraction(
			button: button,
			isSwapSource: swapSourceButton == button,
			onButtonTap: onButtonTap,
			onButtonHover: onButtonHover,
			onSwapRequest: onSwapRequest
		))
		.animation(.spring(response: 0.22, dampingFraction: 0.62), value: pressed)
	}
}

private struct S29RingTargetInteraction: ViewModifier {
	let button: ControllerButton
	let isSwapSource: Bool
	let onButtonTap: (ControllerButton) -> Void
	let onButtonHover: (ControllerButton, Bool) -> Void
	let onSwapRequest: ((ControllerButton, ControllerButton) -> Void)?

	func body(content: Content) -> some View {
		content
			.overlay(
				Circle()
					.stroke(Color.orange, lineWidth: 3)
					.opacity(isSwapSource ? 1 : 0)
			)
			.contentShape(Circle())
			.controllerAnchor(button, role: .controller)
			.onTapGesture { onButtonTap(button) }
			.onHover { hovering in onButtonHover(button, hovering) }
			.swappable(button, onSwap: onSwapRequest)
	}
}
