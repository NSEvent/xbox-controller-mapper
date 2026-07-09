import SwiftUI

extension ControllerVisualView {
	var ouraRingLayout: some View {
		HStack(alignment: .center, spacing: 38) {
			VStack(alignment: .trailing, spacing: 16) {
				referenceGroup(title: "Tap", buttons: ControllerButton.ouraRingTapButtons)
			}
			.frame(width: 250)

			VStack(spacing: 12) {
				OuraRingMinimapView(
					isTapPressed: ControllerButton.ouraRingButtons.contains(where: isPressed),
					isTapSelected: selectedButton.map { ControllerButton.ouraRingButtons.contains($0) } ?? false,
					isSwapSource: swapFirstButton.map { ControllerButton.ouraRingButtons.contains($0) } ?? false,
					onButtonTap: onButtonTap,
					onButtonHover: handleButtonHover,
					onSwapRequest: performSwap
				)
				.overlay(alignment: .bottom) {
					layerScopeChip(nameMaxWidth: 80)
						.frame(maxWidth: OuraRingMinimapView.previewSize.width - 40)
						.padding(.horizontal, 20)
						.padding(.bottom, 18)
						.allowsHitTesting(false)
				}
				.accessibilityHidden(true)

				if controllerService.isConnected {
					BatteryView(level: controllerService.batteryLevel, state: controllerService.batteryState)
				}
			}
			.frame(width: OuraRingMinimapView.previewSize.width)

			VStack(alignment: .leading, spacing: 16) {
				ouraMotionOutputSection
				referenceGroup(title: "Flick", buttons: ControllerButton.ouraRingFlickButtons)
			}
			.frame(width: 250)
		}
		.padding(28)
	}

	private var ouraMotionOutputSection: some View {
		let output = profileManager.activeProfile?.joystickSettings.ouraMotionOutputMode ?? .off

		return VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .center, spacing: 8) {
				Text("Motion")
					.textCase(.uppercase)
					.font(.system(size: 10, weight: .bold))
					.foregroundColor(.secondary)

				Spacer(minLength: 4)
				ouraMotionOutputMenu(selectedOutput: output)
			}
			.padding(.horizontal, 4)

			Label(output.detailText, systemImage: output.systemImageName)
				.font(.system(size: 10, weight: .medium))
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.horizontal, 4)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private func ouraMotionOutputMenu(selectedOutput: OuraMotionOutputMode) -> some View {
		Menu {
			ForEach(OuraMotionOutputMode.allCases) { output in
				Button {
					setOuraMotionOutputMode(output)
				} label: {
					if output == selectedOutput {
						Label(output.displayName, systemImage: "checkmark")
					} else {
						Text(output.displayName)
					}
				}
			}
		} label: {
			HStack(spacing: 4) {
				Image(systemName: selectedOutput.systemImageName)
					.font(.system(size: 8, weight: .bold))
				Text(selectedOutput.displayName)
					.font(.system(size: 9, weight: .heavy, design: .rounded))
					.lineLimit(1)
					.minimumScaleFactor(0.7)
				Image(systemName: "chevron.up.chevron.down")
					.font(.system(size: 7, weight: .bold))
					.opacity(0.7)
			}
			.foregroundStyle(.secondary)
			.padding(.horizontal, 7)
			.frame(height: 20)
			.background(
				RoundedRectangle(cornerRadius: 6)
					.fill(Color.primary.opacity(0.06))
			)
			.overlay(
				RoundedRectangle(cornerRadius: 6)
					.stroke(Color.primary.opacity(0.10), lineWidth: 1)
			)
		}
		.menuStyle(.borderlessButton)
		.fixedSize()
		.help("Set what ring motion does")
	}

	private func setOuraMotionOutputMode(_ output: OuraMotionOutputMode) {
		guard var settings = profileManager.activeProfile?.joystickSettings else { return }
		settings.setOuraMotionOutputMode(output)
		profileManager.updateJoystickSettings(settings)
	}
}

struct OuraRingMinimapView: View {
	static let previewSize = CGSize(width: 300, height: 300)

	let isTapPressed: Bool
	var isTapSelected: Bool = false
	var isSwapSource: Bool = false
	var onButtonTap: (ControllerButton) -> Void = { _ in }
	var onButtonHover: (ControllerButton, Bool) -> Void = { _, _ in }
	var onSwapRequest: ((ControllerButton, ControllerButton) -> Void)?

	var body: some View {
		ZStack {
			ringBody
			tapTarget
				.offset(x: 82, y: 72)
		}
		.frame(width: Self.previewSize.width, height: Self.previewSize.height)
	}

	private var ringBody: some View {
		ZStack {
			Circle()
				.strokeBorder(
					AngularGradient(
						colors: [
							Color.white.opacity(0.72),
							Color(red: 0.58, green: 0.66, blue: 0.72),
							Color(red: 0.14, green: 0.16, blue: 0.18),
							Color.white.opacity(0.58),
							Color(red: 0.58, green: 0.66, blue: 0.72)
						],
						center: .center
					),
					lineWidth: 34
				)
				.frame(width: 210, height: 210)
				.shadow(color: .black.opacity(0.36), radius: 18, x: 0, y: 14)

			Circle()
				.strokeBorder(Color.white.opacity(0.32), lineWidth: 1.2)
				.frame(width: 190, height: 190)

			Circle()
				.strokeBorder(Color.black.opacity(0.42), lineWidth: 1.2)
				.frame(width: 230, height: 230)
		}
	}

	private var tapTarget: some View {
		let active = isTapPressed || isTapSelected

		return ZStack {
			Circle()
				.fill(active ? Color.accentColor : Color(white: 0.16))
				.shadow(color: active ? Color.accentColor.opacity(0.44) : .black.opacity(0.35), radius: active ? 12 : 6, x: 0, y: 4)

			Circle()
				.strokeBorder(Color.white.opacity(active ? 0.72 : 0.22), lineWidth: 1.4)

			VStack(spacing: 2) {
				Image(systemName: "hand.tap.fill")
					.font(.system(size: 17, weight: .bold))
				Text("TAP")
					.font(.system(size: 9, weight: .black, design: .rounded))
			}
			.foregroundStyle(active ? Color.white : Color.white.opacity(0.78))
		}
		.frame(width: 66, height: 66)
		.scaleEffect(isTapPressed ? 0.92 : 1.0)
		.overlay(
			Circle()
				.stroke(Color.orange, lineWidth: 3)
				.opacity(isSwapSource ? 1 : 0)
		)
		.contentShape(Circle())
		.controllerAnchor(.ouraTap, role: .controller)
		.onTapGesture { onButtonTap(.ouraTap) }
		.onHover { hovering in onButtonHover(.ouraTap, hovering) }
		.swappable(.ouraTap, onSwap: onSwapRequest)
		.animation(.spring(response: 0.22, dampingFraction: 0.62), value: isTapPressed)
		.animation(.easeOut(duration: 0.12), value: isTapSelected)
	}
}
