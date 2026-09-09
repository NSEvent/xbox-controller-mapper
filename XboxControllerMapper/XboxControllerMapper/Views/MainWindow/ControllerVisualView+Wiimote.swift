import SwiftUI
import Combine

// MARK: - Wii Remote

/// Product-accurate Wii Remote visual with live button state. Vertical like
/// the Apple TV remote view; proportions traced from the RVL-CNT-01
/// (36.2 × 148 mm). Used full-size in the Buttons tab and scaled down by the
/// stream overlay and pairing hint.
///
/// The B trigger lives on the underside of the real remote, so it renders as
/// a tab peeking out from the left edge at the A button's height. The power
/// button is hardware-only (it emits no HID reports; holding it switches the
/// remote off), so it draws as decoration and is not mappable.
struct WiimoteMinimapView: View {
	static let previewSize = CGSize(width: 130, height: 520)

	let controllerService: ControllerService
	var onButtonTap: (ControllerButton) -> Void = { _ in }
	var onButtonHover: (ControllerButton, Bool) -> Void = { _, _ in }
	var onSwapRequest: ((ControllerButton, ControllerButton) -> Void)? = nil

	@State private var activeButtons: Set<ControllerButton> = []
	@State private var isConnected: Bool = false

	var body: some View {
		ZStack(alignment: .topLeading) {
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.fill(
					LinearGradient(
						colors: [Color(white: 0.97), Color(white: 0.82)],
						startPoint: .top,
						endPoint: .bottom
					)
				)
				.overlay(
					RoundedRectangle(cornerRadius: 20, style: .continuous)
						.stroke(Color.white.opacity(0.65), lineWidth: 1)
				)
				.shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)

			VStack(spacing: 0) {
				HStack {
					powerButton
						.padding(.leading, 16)
					Spacer()
				}
				.padding(.top, 14)

				dpadCross
					.padding(.top, 10)

				letterButton(.a, label: "A", diameter: 46)
					.padding(.top, 16)

				HStack(spacing: 12) {
					glyphButton(.view, systemImage: "minus", diameter: 22)
					homeButton
					glyphButton(.menu, systemImage: "plus", diameter: 22)
				}
				.padding(.top, 22)

				speakerGrille
					.padding(.top, 20)

				letterButton(.x, label: "1", diameter: 32)
					.padding(.top, 20)
				letterButton(.y, label: "2", diameter: 32)
					.padding(.top, 12)

				playerLEDs
					.padding(.top, 18)

				Text("Wii")
					.font(.system(size: 15, weight: .semibold, design: .rounded))
					.foregroundStyle(Color(white: 0.55))
					.padding(.top, 6)

				Spacer(minLength: 0)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			bTriggerTab
				.offset(x: -9, y: 176)
		}
		.frame(width: Self.previewSize.width, height: Self.previewSize.height)
		.onReceive(controllerService.$activeButtons) { activeButtons = $0 }
		.onReceive(controllerService.$isConnected) { isConnected = $0 }
	}

	private func isPressed(_ button: ControllerButton) -> Bool {
		activeButtons.contains(button) ||
			button.physicalEquivalentButtons.contains { activeButtons.contains($0) }
	}

	// MARK: Buttons

	/// Cream face button with an engraved label (A, 1, 2), like the real remote.
	private func letterButton(_ button: ControllerButton, label: String, diameter: CGFloat) -> some View {
		Text(label)
			.font(.system(size: diameter * 0.42, weight: .semibold, design: .rounded))
			.foregroundStyle(isPressed(button) ? .white : Color(white: 0.42))
			.frame(width: diameter, height: diameter)
			.background(
				Circle()
					.fill(
						buttonGradient(
							isPressed(button) ? Color.accentColor : Color(white: 0.90),
							pressed: isPressed(button)
						)
					)
			)
			.overlay(Circle().stroke(Color.black.opacity(0.14), lineWidth: 1))
			.shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 1.5)
			.contentShape(Circle())
			.controllerAnchor(button, role: .controller)
			.onTapGesture { onButtonTap(button) }
			.onHover { hovering in onButtonHover(button, hovering) }
			.swappable(button, onSwap: onSwapRequest)
			.help(button.displayName(forWiimote: true))
	}

	private func glyphButton(_ button: ControllerButton, systemImage: String, diameter: CGFloat) -> some View {
		Image(systemName: systemImage)
			.font(.system(size: diameter * 0.5, weight: .bold))
			.foregroundStyle(isPressed(button) ? .white : Color(white: 0.42))
			.frame(width: diameter, height: diameter)
			.background(
				Circle()
					.fill(
						buttonGradient(
							isPressed(button) ? Color.accentColor : Color(white: 0.90),
							pressed: isPressed(button)
						)
					)
			)
			.overlay(Circle().stroke(Color.black.opacity(0.14), lineWidth: 1))
			.shadow(color: .black.opacity(0.14), radius: 1.5, x: 0, y: 1)
			.contentShape(Circle())
			.controllerAnchor(button, role: .controller)
			.onTapGesture { onButtonTap(button) }
			.onHover { hovering in onButtonHover(button, hovering) }
			.swappable(button, onSwap: onSwapRequest)
			.help(button.displayName(forWiimote: true))
	}

	/// Home: the real button carries a house glyph inside a blue-lit ring.
	private var homeButton: some View {
		Image(systemName: "house.fill")
			.font(.system(size: 13, weight: .semibold))
			.foregroundStyle(isPressed(.xbox) ? .white : Color(red: 0.25, green: 0.55, blue: 0.85))
			.frame(width: 28, height: 28)
			.background(
				Circle()
					.fill(
						buttonGradient(
							isPressed(.xbox) ? Color.accentColor : Color(white: 0.90),
							pressed: isPressed(.xbox)
						)
					)
			)
			.overlay(Circle().stroke(Color(red: 0.35, green: 0.6, blue: 0.9).opacity(0.5), lineWidth: 1.2))
			.shadow(color: .black.opacity(0.14), radius: 1.5, x: 0, y: 1)
			.contentShape(Circle())
			.controllerAnchor(.xbox, role: .controller)
			.onTapGesture { onButtonTap(.xbox) }
			.onHover { hovering in onButtonHover(.xbox, hovering) }
			.swappable(.xbox, onSwap: onSwapRequest)
			.help(ControllerButton.xbox.displayName(forWiimote: true))
	}

	/// Glossy black plus-shaped d-pad with four interactive arms.
	private var dpadCross: some View {
		let span: CGFloat = 74
		let arm: CGFloat = 25

		return ZStack {
			// Cross body
			RoundedRectangle(cornerRadius: 5, style: .continuous)
				.fill(dpadFill)
				.frame(width: arm, height: span)
			RoundedRectangle(cornerRadius: 5, style: .continuous)
				.fill(dpadFill)
				.frame(width: span, height: arm)
			RoundedRectangle(cornerRadius: 5, style: .continuous)
				.stroke(Color.black.opacity(0.35), lineWidth: 1)
				.frame(width: arm, height: span)
			RoundedRectangle(cornerRadius: 5, style: .continuous)
				.stroke(Color.black.opacity(0.35), lineWidth: 1)
				.frame(width: span, height: arm)

			dpadArm(.dpadUp, x: 0, y: -span / 2 + arm / 2, chevron: "chevron.up")
			dpadArm(.dpadDown, x: 0, y: span / 2 - arm / 2, chevron: "chevron.down")
			dpadArm(.dpadLeft, x: -span / 2 + arm / 2, y: 0, chevron: "chevron.left")
			dpadArm(.dpadRight, x: span / 2 - arm / 2, y: 0, chevron: "chevron.right")
		}
		.frame(width: span, height: span)
	}

	private var dpadFill: LinearGradient {
		LinearGradient(
			colors: [Color(white: 0.30), Color(white: 0.14)],
			startPoint: .top,
			endPoint: .bottom
		)
	}

	private func dpadArm(_ button: ControllerButton, x: CGFloat, y: CGFloat, chevron: String) -> some View {
		ZStack {
			if isPressed(button) {
				RoundedRectangle(cornerRadius: 4, style: .continuous)
					.fill(Color.accentColor.opacity(0.88))
			}
			Image(systemName: chevron)
				.font(.system(size: 8, weight: .bold))
				.foregroundStyle(.white.opacity(isPressed(button) ? 1.0 : 0.55))
		}
		.frame(width: 22, height: 22)
		.controllerAnchor(button, role: .controller)
		.offset(x: x, y: y)
		.contentShape(Rectangle())
		.onTapGesture { onButtonTap(button) }
		.onHover { hovering in onButtonHover(button, hovering) }
		.swappable(button, onSwap: onSwapRequest)
		.help(button.displayName(forWiimote: true))
	}

	/// B trigger peeking out from under the left edge at the A button's height.
	private var bTriggerTab: some View {
		Text("B")
			.font(.system(size: 11, weight: .semibold, design: .rounded))
			.foregroundStyle(isPressed(.b) ? .white : Color(white: 0.92))
			.frame(width: 18, height: 52)
			.background(
				Capsule()
					.fill(isPressed(.b) ? Color.accentColor : Color(white: 0.30))
			)
			.overlay(Capsule().stroke(Color.black.opacity(0.25), lineWidth: 1))
			.shadow(color: .black.opacity(0.2), radius: 2, x: -1, y: 1)
			.contentShape(Capsule())
			.controllerAnchor(.b, role: .controller)
			.onTapGesture { onButtonTap(.b) }
			.onHover { hovering in onButtonHover(.b, hovering) }
			.swappable(.b, onSwap: onSwapRequest)
			.help("B (underside trigger)")
	}

	// MARK: Decoration

	/// Hardware-only: no HID report, so decorative — not mappable.
	private var powerButton: some View {
		Image(systemName: "power")
			.font(.system(size: 9, weight: .bold))
			.foregroundStyle(Color(red: 0.75, green: 0.25, blue: 0.22))
			.frame(width: 20, height: 20)
			.overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
			.help("Power — hardware only (hold to switch the remote off); not mappable")
	}

	/// Diamond-ish speaker dot grid.
	private var speakerGrille: some View {
		VStack(spacing: 3.5) {
			ForEach(Array([3, 5, 7, 5, 3].enumerated()), id: \.offset) { _, count in
				HStack(spacing: 3.5) {
					ForEach(0..<count, id: \.self) { _ in
						Circle()
							.fill(Color(white: 0.55))
							.frame(width: 2.6, height: 2.6)
					}
				}
			}
		}
		.allowsHitTesting(false)
	}

	/// Four player LEDs; LED 1 lights blue while connected (ControllerKeys
	/// sets player LED 1 on attach).
	private var playerLEDs: some View {
		HStack(spacing: 9) {
			ForEach(0..<4, id: \.self) { index in
				RoundedRectangle(cornerRadius: 1.2)
					.fill(
						index == 0 && isConnected
							? Color(red: 0.3, green: 0.65, blue: 0.95)
							: Color(white: 0.62)
					)
					.frame(width: 5.5, height: 5.5)
					.shadow(
						color: index == 0 && isConnected
							? Color(red: 0.3, green: 0.65, blue: 0.95).opacity(0.8)
							: .clear,
						radius: 2
					)
			}
		}
		.allowsHitTesting(false)
	}

	private func buttonGradient(_ color: Color, pressed: Bool) -> LinearGradient {
		LinearGradient(
			colors: [
				pressed ? color.opacity(0.82) : color.opacity(1.0),
				pressed ? color.opacity(0.58) : color.opacity(0.76)
			],
			startPoint: .topLeading,
			endPoint: .bottomTrailing
		)
	}
}

extension ControllerVisualView {
	@ViewBuilder
	var wiimoteLayout: some View {
		HStack(alignment: .center, spacing: 26) {
			VStack(alignment: .trailing, spacing: 16) {
				directionCluster(
					title: "D-Pad",
					up: .dpadUp,
					left: .dpadLeft,
					center: .dpadPreset,
					right: .dpadRight,
					down: .dpadDown
				)
				referenceGroup(title: "Face", buttons: [.a, .b])
			}
			.frame(width: 250)

			VStack(spacing: 12) {
				WiimoteMinimapView(
					controllerService: controllerService,
					onButtonTap: onButtonTap,
					onButtonHover: handleButtonHover,
					onSwapRequest: performSwap
				)
				.overlay(alignment: .bottom) {
					layerScopeChip(nameMaxWidth: 60)
						.frame(maxWidth: WiimoteMinimapView.previewSize.width - 24)
						.padding(.horizontal, 12)
						.padding(.bottom, 12)
						.allowsHitTesting(false)
				}
				.accessibilityHidden(true)

				if controllerService.isConnected {
					BatteryView(level: controllerService.batteryLevel, state: controllerService.batteryState)
				}
			}

			VStack(alignment: .leading, spacing: 16) {
				referenceGroup(title: "1 · 2", buttons: [.x, .y])
				referenceGroup(title: "System", buttons: [.menu, .view, .xbox])
			}
			.frame(width: 250)
		}
		.padding(28)
	}
}
