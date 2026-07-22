import SwiftUI

extension ControllerVisualView {
	var beamdeskHandsLayout: some View {
		HStack(alignment: .center, spacing: 38) {
			VStack(alignment: .trailing, spacing: 16) {
				referenceGroup(
					title: "Left Hand",
					buttons: ControllerButton.beamdeskLeftHandButtons
				)
			}
			.frame(width: 270)

			VStack(spacing: 12) {
				// Like the main controller layout, the layer chip sits above the
				// card so it never covers the live gesture caption rendered at
				// the card's bottom edge.
				layerScopeChip(nameMaxWidth: 120)

				BeamdeskHandsMinimapView(pressedButtons: controllerService.activeButtons)
					.accessibilityHidden(true)

				Text("META QUEST MICROGESTURES")
					.font(.system(size: 9, weight: .heavy, design: .rounded))
					.tracking(1.2)
					.foregroundStyle(.secondary)
			}
			.frame(width: BeamdeskHandsMinimapView.previewSize.width)

			VStack(alignment: .leading, spacing: 16) {
				referenceGroup(
					title: "Right Hand",
					buttons: ControllerButton.beamdeskRightHandButtons
				)
			}
			.frame(width: 270)
		}
		.padding(28)
	}
}

struct BeamdeskHandsMinimapView: View {
	static let previewSize = CGSize(width: 320, height: 250)

	let pressedButtons: Set<ControllerButton>
	@State private var displayedGesture: BeamdeskGesturePresentation?
	@State private var activationID = 0

	private var activeGesture: BeamdeskGesturePresentation? {
		BeamdeskGesturePresentation.active(in: pressedButtons)
	}

	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: 34, style: .continuous)
				.fill(
					LinearGradient(
						colors: [
							Color(red: 0.03, green: 0.12, blue: 0.16),
							Color(red: 0.04, green: 0.06, blue: 0.10),
						],
						startPoint: .topLeading,
						endPoint: .bottomTrailing
					)
				)
				.overlay {
					RoundedRectangle(cornerRadius: 34, style: .continuous)
						.stroke(Color.cyan.opacity(0.22), lineWidth: 1)
				}

			Group {
				if AppRuntime.isRunningTests {
					BeamdeskHandsRenderFallback()
				} else {
					BeamdeskHandGestureScene(
						presentation: displayedGesture ?? activeGesture,
						activationID: activationID
					)
				}
			}
			.frame(width: 292, height: 190)
			.padding(.top, 20)

			VStack {
				HStack(spacing: 6) {
					Circle()
						.fill(Color.cyan)
						.frame(width: 6, height: 6)
					Text("BEAMDESK")
						.font(.system(size: 10, weight: .black, design: .rounded))
						.tracking(1.6)
				}
				.foregroundStyle(Color.cyan.opacity(0.9))
				.padding(.top, 18)
				Spacer()
			}

			VStack(spacing: 3) {
				Spacer()
				if let gesture = displayedGesture ?? activeGesture {
					Label(gesture.gesture.displayName, systemImage: gesture.gesture.systemImage)
						.font(.system(size: 10, weight: .black, design: .rounded))
						.tracking(0.8)
						.foregroundStyle(Color.cyan)
					Text(gesture.side.displayName)
						.font(.system(size: 8, weight: .bold, design: .rounded))
						.tracking(1.2)
						.foregroundStyle(.secondary)
				} else {
					Text("THUMB ON INDEX TO BEGIN")
						.font(.system(size: 8, weight: .bold, design: .rounded))
						.tracking(1.1)
						.foregroundStyle(.secondary)
				}
			}
			.padding(.bottom, 14)
		}
		.frame(width: Self.previewSize.width, height: Self.previewSize.height)
		.onAppear { recognize(activeGesture) }
		.onChange(of: activeGesture) { _, gesture in
			recognize(gesture)
		}
	}

	private func recognize(_ gesture: BeamdeskGesturePresentation?) {
		guard let gesture else { return }
		displayedGesture = gesture
		activationID &+= 1
	}
}

private struct BeamdeskHandsRenderFallback: View {
	var body: some View {
		HStack(spacing: 36) {
			hand(mirrored: false)
			hand(mirrored: true)
		}
		.foregroundStyle(
			LinearGradient(
				colors: [Color.white.opacity(0.88), Color.cyan.opacity(0.55)],
				startPoint: .top,
				endPoint: .bottom
			)
		)
	}

	private func hand(mirrored: Bool) -> some View {
		Image(systemName: "hand.thumbsup.fill")
			.font(.system(size: 74, weight: .medium))
			.scaleEffect(x: mirrored ? -1 : 1, y: 1)
	}
}
