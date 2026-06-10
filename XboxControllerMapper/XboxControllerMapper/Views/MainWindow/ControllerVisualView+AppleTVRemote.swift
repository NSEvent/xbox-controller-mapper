import SwiftUI
import Combine

// MARK: - Apple TV Remote

private struct AppleTVRemoteTouchIndicator: View {
	let controllerService: ControllerService
	let clickpadSize: CGFloat

	@State private var isTouching = false
	@State private var position: CGPoint = .zero

	var body: some View {
		Group {
			if isTouching {
				Circle()
					.fill(Color.white.opacity(0.82))
					.frame(width: 10, height: 10)
					.shadow(color: .white.opacity(0.5), radius: 3)
					.offset(
						x: boundedPosition.x * (clickpadSize / 2 - 8),
						y: -boundedPosition.y * (clickpadSize / 2 - 8)
					)
			}
		}
		.frame(width: clickpadSize, height: clickpadSize)
		.allowsHitTesting(false)
		.onReceive(controllerService.displayIsTouchpadTouchingSubject) { isTouching = $0 }
		.onReceive(controllerService.displayTouchpadPositionSubject) { position = $0 }
	}

	private var boundedPosition: CGPoint {
		let x = min(max(position.x, -1), 1)
		let y = min(max(position.y, -1), 1)
		let distance = hypot(x, y)
		guard distance > 1 else {
			return CGPoint(x: x, y: y)
		}
		return CGPoint(x: x / distance, y: y / distance)
	}
}

extension ControllerVisualView {
	@ViewBuilder
	var appleTVRemoteLayout: some View {
		HStack(alignment: .center, spacing: 26) {
			VStack(alignment: .trailing, spacing: 16) {
				referenceGroup(title: "Clickpad", buttons: [.touchpadButton, .touchpadTap])
				directionCluster(
					title: "Clickpad",
					up: .dpadUp,
					left: .dpadLeft,
					center: .dpadPreset,
					right: .dpadRight,
					down: .dpadDown
				)
				referenceGroup(title: "System", buttons: [.view, .menu])
			}
			.frame(width: 250)

			VStack(spacing: 12) {
				appleTVRemoteBodyView
					.frame(width: appleTVRemotePreviewWidth, height: appleTVRemotePreviewHeight)
					.accessibilityHidden(true)

				if controllerService.isConnected {
					BatteryView(level: controllerService.batteryLevel, state: controllerService.batteryState)
				}
			}

			VStack(alignment: .leading, spacing: 16) {
				referenceGroup(title: "System", buttons: [.appleTVRemotePower, .siri, .xbox])
				referenceGroup(title: "Volume", buttons: [.appleTVRemoteVolumeUp, .appleTVRemoteVolumeDown, .appleTVRemoteMute])
			}
			.frame(width: 250)
		}
		.padding(28)
	}

	private var appleTVRemotePreviewWidth: CGFloat { 154 }
	private var appleTVRemotePreviewHeight: CGFloat { 520 }
	private var appleTVRemoteRoundButtonSize: CGFloat { 46 }
	private var appleTVRemoteClickpadSize: CGFloat { 126 }
	private var appleTVRemoteClickpadCenterButtonSize: CGFloat { 72 }
	private var appleTVRemoteVolumeRockerHeight: CGFloat { appleTVRemoteRoundButtonSize * 2 + 26 }

	private var appleTVRemoteBodyView: some View {
		ZStack(alignment: .topTrailing) {
			RoundedRectangle(cornerRadius: 28, style: .continuous)
				.fill(
					LinearGradient(
						colors: [Color(white: 0.88), Color(white: 0.64)],
						startPoint: .top,
						endPoint: .bottom
					)
				)
				.overlay(
					RoundedRectangle(cornerRadius: 28, style: .continuous)
						.stroke(Color.white.opacity(0.62), lineWidth: 1)
				)
				.shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)

			VStack(spacing: 0) {
				ZStack {
					Capsule()
						.fill(Color.black.opacity(0.72))
						.frame(width: 15, height: 5)

					HStack {
						Spacer()
						appleTVRemotePowerButton
							.padding(.trailing, 13)
					}
				}
				.frame(height: 34)
				.padding(.top, 14)

				appleTVRemoteClickpad
					.padding(.top, 28)

				HStack(spacing: 26) {
					appleTVRemoteRoundButton(.view, systemImage: "chevron.left")
					appleTVRemoteRoundButton(.xbox, systemImage: "tv.fill")
				}
				.padding(.top, 24)

				HStack(alignment: .top, spacing: 26) {
					VStack(spacing: 26) {
						appleTVRemoteRoundButton(.menu, systemImage: "playpause.fill")
						appleTVRemoteRoundButton(.appleTVRemoteMute, systemImage: "speaker.slash.fill")
					}

					appleTVRemoteVolumeRocker
				}
				.padding(.top, 24)

				Spacer(minLength: 0)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			appleTVRemoteSiriSideButton
				.offset(x: 9, y: 112)

			VStack {
				Spacer()
				layerScopeChip(nameMaxWidth: 68)
					.frame(maxWidth: appleTVRemotePreviewWidth - 28)
					.padding(.horizontal, 14)
					.padding(.bottom, 14)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.allowsHitTesting(false)
		}
		.frame(width: appleTVRemotePreviewWidth, height: appleTVRemotePreviewHeight)
	}

	private var appleTVRemoteClickpad: some View {
		ZStack {
			Circle()
				.fill(
					LinearGradient(
						colors: [Color(white: 0.14), Color(white: 0.05)],
						startPoint: .topLeading,
						endPoint: .bottomTrailing
					)
				)
				.overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
			Circle()
				.strokeBorder(Color.white.opacity(0.08), lineWidth: 22)
			appleTVRemoteClickpadDot(.dpadUp, x: 0, y: -55)
			appleTVRemoteClickpadDot(.dpadDown, x: 0, y: 55)
			appleTVRemoteClickpadDot(.dpadLeft, x: -55, y: 0)
			appleTVRemoteClickpadDot(.dpadRight, x: 55, y: 0)
			Circle()
				.fill(
					appleTVRemoteButtonGradient(
						isPressed(.touchpadButton) ? Color.accentColor : Color(white: 0.10),
						pressed: isPressed(.touchpadButton)
					)
				)
				.overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1.2))
				.frame(width: appleTVRemoteClickpadCenterButtonSize, height: appleTVRemoteClickpadCenterButtonSize)
				.controllerAnchor([.touchpadButton, .touchpadTap], role: .controller)
				.contentShape(Circle())
				.onTapGesture { onButtonTap(.touchpadButton) }
				.onHover { hovering in handleButtonHover(.touchpadButton, hovering) }
				.swappable(.touchpadButton, onSwap: performSwap)
				.help("Clickpad Click")
			AppleTVRemoteTouchIndicator(
				controllerService: controllerService,
				clickpadSize: appleTVRemoteClickpadSize
			)
		}
		.frame(width: appleTVRemoteClickpadSize, height: appleTVRemoteClickpadSize)
		.help("Clickpad")
	}

	private func appleTVRemoteClickpadDot(
		_ button: ControllerButton,
		x: CGFloat,
		y: CGFloat
	) -> some View {
		ZStack {
			if isPressed(button) {
				Circle()
					.fill(Color.accentColor.opacity(0.86))
					.frame(width: 18, height: 18)
			}

			Circle()
				.fill(Color.white.opacity(0.88))
				.frame(width: 4, height: 4)
				.controllerAnchor(button, role: .controller)
		}
		.frame(width: 30, height: 30)
		.offset(x: x, y: y)
		.contentShape(Circle())
		.onTapGesture { onButtonTap(button) }
		.onHover { hovering in handleButtonHover(button, hovering) }
		.swappable(button, onSwap: performSwap)
		.help(button.displayName(forAppleTVRemote: true))
	}

	private var appleTVRemoteSiriSideButton: some View {
		Capsule()
			.fill(isPressed(.siri) ? Color.accentColor : Color(white: 0.72))
			.frame(width: 10, height: 66)
			.overlay(Capsule().stroke(Color.black.opacity(0.16), lineWidth: 1))
			.controllerAnchor(.siri, role: .controller)
			.contentShape(Rectangle())
			.onTapGesture { onButtonTap(.siri) }
			.onHover { hovering in handleButtonHover(.siri, hovering) }
			.help("Siri")
	}

	private var appleTVRemoteVolumeRocker: some View {
		VStack(spacing: 0) {
			appleTVRemoteVolumeRockerSegment(.appleTVRemoteVolumeUp, systemImage: "plus")
			Rectangle()
				.fill(Color.white.opacity(0.12))
				.frame(height: 1)
			appleTVRemoteVolumeRockerSegment(.appleTVRemoteVolumeDown, systemImage: "minus")
		}
		.frame(width: appleTVRemoteRoundButtonSize, height: appleTVRemoteVolumeRockerHeight)
		.background(
			RoundedRectangle(cornerRadius: appleTVRemoteRoundButtonSize / 2, style: .continuous)
				.fill(Color(white: 0.09))
		)
		.clipShape(RoundedRectangle(cornerRadius: appleTVRemoteRoundButtonSize / 2, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: appleTVRemoteRoundButtonSize / 2, style: .continuous)
				.stroke(Color.white.opacity(0.16), lineWidth: 1)
		)
	}

	private func appleTVRemoteVolumeRockerSegment(_ button: ControllerButton, systemImage: String) -> some View {
		Image(systemName: systemImage)
			.font(.system(size: 18, weight: .bold))
			.foregroundStyle(.white.opacity(0.85))
			.frame(width: appleTVRemoteRoundButtonSize, height: (appleTVRemoteVolumeRockerHeight - 1) / 2)
			.background(isPressed(button) ? Color.accentColor : Color.clear)
			.contentShape(Rectangle())
			.controllerAnchor(button, role: .controller)
			.onTapGesture { onButtonTap(button) }
			.onHover { hovering in handleButtonHover(button, hovering) }
			.swappable(button, onSwap: performSwap)
			.help(button.displayName(forAppleTVRemote: true))
	}

	private var appleTVRemotePowerButton: some View {
		Image(systemName: "power")
			.font(.system(size: 15, weight: .semibold))
			.foregroundStyle(isPressed(.appleTVRemotePower) ? .white : Color.black.opacity(0.82))
			.frame(width: 34, height: 34)
			.background(
				Circle()
					.fill(isPressed(.appleTVRemotePower) ? Color.accentColor : Color.clear)
			)
			.overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1.2))
			.contentShape(Circle())
			.controllerAnchor(.appleTVRemotePower, role: .controller)
			.onTapGesture { onButtonTap(.appleTVRemotePower) }
			.onHover { hovering in handleButtonHover(.appleTVRemotePower, hovering) }
			.swappable(.appleTVRemotePower, onSwap: performSwap)
			.help("Power")
	}

	private func appleTVRemoteRoundButton(_ button: ControllerButton, systemImage: String) -> some View {
		Image(systemName: systemImage)
			.font(.system(size: button == .menu ? 14 : 17, weight: .semibold))
			.foregroundStyle(.white.opacity(0.9))
			.frame(width: appleTVRemoteRoundButtonSize, height: appleTVRemoteRoundButtonSize)
			.background(
				Circle()
					.fill(
						appleTVRemoteButtonGradient(
							isPressed(button) ? Color.accentColor : Color(white: 0.09),
							pressed: isPressed(button)
						)
					)
			)
			.overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
			.shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1.5)
			.contentShape(Circle())
			.controllerAnchor(button, role: .controller)
			.onTapGesture { onButtonTap(button) }
			.onHover { hovering in handleButtonHover(button, hovering) }
			.swappable(button, onSwap: performSwap)
			.help(button.displayName(forAppleTVRemote: true))
	}

	private func appleTVRemoteButtonGradient(_ color: Color, pressed: Bool) -> LinearGradient {
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
