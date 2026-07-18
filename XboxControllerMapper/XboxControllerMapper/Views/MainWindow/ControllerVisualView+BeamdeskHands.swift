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
                BeamdeskHandsMinimapView(pressedButtons: controllerService.activeButtons)
                    .overlay(alignment: .bottom) {
                        layerScopeChip(nameMaxWidth: 120)
                            .frame(maxWidth: BeamdeskHandsMinimapView.previewSize.width - 40)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                            .allowsHitTesting(false)
                    }
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

    private var leftPressed: Bool {
        !pressedButtons.isDisjoint(with: ControllerButton.beamdeskLeftHandButtons)
    }

    private var rightPressed: Bool {
        !pressedButtons.isDisjoint(with: ControllerButton.beamdeskRightHandButtons)
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

            HStack(spacing: 34) {
                hand(side: "L", pressed: leftPressed, mirrored: true)
                hand(side: "R", pressed: rightPressed, mirrored: false)
            }
            .padding(.bottom, 16)

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
        }
        .frame(width: Self.previewSize.width, height: Self.previewSize.height)
    }

    private func hand(side: String, pressed: Bool, mirrored: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(pressed ? 0.20 : 0.06))
                    .frame(width: 112, height: 112)
                    .shadow(color: Color.cyan.opacity(pressed ? 0.65 : 0), radius: 18)

                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 70, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: pressed
                                ? [Color.white, Color.cyan]
                                : [Color.white.opacity(0.76), Color.cyan.opacity(0.38)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)

                directionGlyphs
            }

            Text("\(side) HAND")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(pressed ? Color.cyan : Color.secondary)
        }
        .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private var directionGlyphs: some View {
        ZStack {
            Image(systemName: "arrow.left").offset(x: -58)
            Image(systemName: "arrow.right").offset(x: 58)
            Image(systemName: "arrow.up").offset(y: -58)
            Image(systemName: "arrow.down").offset(y: 58)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Color.cyan.opacity(0.62))
    }
}
