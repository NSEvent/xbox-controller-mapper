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

/// Product-accurate Siri Remote visual with live button/touch state.
/// Used full-size in the Buttons tab and scaled down by the stream
/// overlay, so both always show the same remote.
struct AppleTVRemoteMinimapView: View {
	static let previewSize = CGSize(width: 154, height: 520)

	let controllerService: ControllerService
	var onButtonTap: (ControllerButton) -> Void = { _ in }
	var onButtonHover: (ControllerButton, Bool) -> Void = { _, _ in }
	var onSwapRequest: ((ControllerButton, ControllerButton) -> Void)? = nil

	@State private var activeButtons: Set<ControllerButton> = []

	private var roundButtonSize: CGFloat { 46 }
	private var clickpadSize: CGFloat { 126 }
	private var clickpadCenterButtonSize: CGFloat { 72 }
	private var volumeRockerHeight: CGFloat { roundButtonSize * 2 + 26 }

	var body: some View {
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
						powerButton
							.padding(.trailing, 13)
					}
				}
				.frame(height: 34)
				.padding(.top, 14)

				clickpad
					.padding(.top, 28)

				HStack(spacing: 26) {
					roundButton(.view, systemImage: "chevron.left")
					roundButton(.xbox, systemImage: "tv.fill")
				}
				.padding(.top, 24)

				HStack(alignment: .top, spacing: 26) {
					VStack(spacing: 26) {
						roundButton(.menu, systemImage: "playpause.fill")
						roundButton(.appleTVRemoteMute, systemImage: "speaker.slash.fill")
					}

					volumeRocker
				}
				.padding(.top, 24)

				Spacer(minLength: 0)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			siriSideButton
				.offset(x: 9, y: 112)
		}
		.frame(width: Self.previewSize.width, height: Self.previewSize.height)
		.onReceive(controllerService.$activeButtons) { activeButtons = $0 }
	}

	private func isPressed(_ button: ControllerButton) -> Bool {
		activeButtons.contains(button) ||
			button.physicalEquivalentButtons.contains { activeButtons.contains($0) }
	}

	private var clickpad: some View {
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
			clickpadDot(.dpadUp, x: 0, y: -55)
			clickpadDot(.dpadDown, x: 0, y: 55)
			clickpadDot(.dpadLeft, x: -55, y: 0)
			clickpadDot(.dpadRight, x: 55, y: 0)
			Circle()
				.fill(
					buttonGradient(
						isPressed(.touchpadButton) ? Color.accentColor : Color(white: 0.10),
						pressed: isPressed(.touchpadButton)
					)
				)
				.overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1.2))
				.frame(width: clickpadCenterButtonSize, height: clickpadCenterButtonSize)
				.controllerAnchor([.touchpadButton, .touchpadTap], role: .controller)
				.contentShape(Circle())
				.onTapGesture { onButtonTap(.touchpadButton) }
				.onHover { hovering in onButtonHover(.touchpadButton, hovering) }
				.swappable(.touchpadButton, onSwap: onSwapRequest)
				.help("Clickpad Click")
			AppleTVRemoteTouchIndicator(
				controllerService: controllerService,
				clickpadSize: clickpadSize
			)
		}
		.frame(width: clickpadSize, height: clickpadSize)
		.help("Clickpad")
	}

	private func clickpadDot(
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
		.onHover { hovering in onButtonHover(button, hovering) }
		.swappable(button, onSwap: onSwapRequest)
		.help(button.displayName(forAppleTVRemote: true))
	}

	private var siriSideButton: some View {
		Capsule()
			.fill(isPressed(.siri) ? Color.accentColor : Color(white: 0.72))
			.frame(width: 10, height: 66)
			.overlay(Capsule().stroke(Color.black.opacity(0.16), lineWidth: 1))
			.controllerAnchor(.siri, role: .controller)
			.contentShape(Rectangle())
			.onTapGesture { onButtonTap(.siri) }
			.onHover { hovering in onButtonHover(.siri, hovering) }
			.help("Siri")
	}

	private var volumeRocker: some View {
		VStack(spacing: 0) {
			volumeRockerSegment(.appleTVRemoteVolumeUp, systemImage: "plus")
			Rectangle()
				.fill(Color.white.opacity(0.12))
				.frame(height: 1)
			volumeRockerSegment(.appleTVRemoteVolumeDown, systemImage: "minus")
		}
		.frame(width: roundButtonSize, height: volumeRockerHeight)
		.background(
			RoundedRectangle(cornerRadius: roundButtonSize / 2, style: .continuous)
				.fill(Color(white: 0.09))
		)
		.clipShape(RoundedRectangle(cornerRadius: roundButtonSize / 2, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: roundButtonSize / 2, style: .continuous)
				.stroke(Color.white.opacity(0.16), lineWidth: 1)
		)
	}

	private func volumeRockerSegment(_ button: ControllerButton, systemImage: String) -> some View {
		Image(systemName: systemImage)
			.font(.system(size: 18, weight: .bold))
			.foregroundStyle(.white.opacity(0.85))
			.frame(width: roundButtonSize, height: (volumeRockerHeight - 1) / 2)
			.background(isPressed(button) ? Color.accentColor : Color.clear)
			.contentShape(Rectangle())
			.controllerAnchor(button, role: .controller)
			.onTapGesture { onButtonTap(button) }
			.onHover { hovering in onButtonHover(button, hovering) }
			.swappable(button, onSwap: onSwapRequest)
			.help(button.displayName(forAppleTVRemote: true))
	}

	private var powerButton: some View {
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
			.onHover { hovering in onButtonHover(.appleTVRemotePower, hovering) }
			.swappable(.appleTVRemotePower, onSwap: onSwapRequest)
			.help("Power")
	}

	private func roundButton(_ button: ControllerButton, systemImage: String) -> some View {
		Image(systemName: systemImage)
			.font(.system(size: button == .menu ? 14 : 17, weight: .semibold))
			.foregroundStyle(.white.opacity(0.9))
			.frame(width: roundButtonSize, height: roundButtonSize)
			.background(
				Circle()
					.fill(
						buttonGradient(
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
			.onHover { hovering in onButtonHover(button, hovering) }
			.swappable(button, onSwap: onSwapRequest)
			.help(button.displayName(forAppleTVRemote: true))
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
				AppleTVRemoteMinimapView(
					controllerService: controllerService,
					onButtonTap: onButtonTap,
					onButtonHover: handleButtonHover,
					onSwapRequest: performSwap
				)
				.overlay(alignment: .bottom) {
					layerScopeChip(nameMaxWidth: 68)
						.frame(maxWidth: AppleTVRemoteMinimapView.previewSize.width - 28)
						.padding(.horizontal, 14)
						.padding(.bottom, 14)
						.allowsHitTesting(false)
				}
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
}
