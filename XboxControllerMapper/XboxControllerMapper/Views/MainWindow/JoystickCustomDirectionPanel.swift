import SwiftUI

struct JoystickCustomDirectionPanel: View {
    @EnvironmentObject private var profileManager: ProfileManager

    let side: JoystickSide
    @Binding var horizontalSliceSize: Double
    @Binding var verticalSliceSize: Double
    @Binding var deadzone: Double
    @Binding var invertY: Bool

    private var sideLabel: String {
        switch side {
        case .left: return "Left Stick"
        case .right: return "Right Stick"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    directionPreview
                    controls
                }

                VStack(alignment: .leading, spacing: 14) {
                    directionPreview
                        .frame(maxWidth: .infinity, alignment: .center)
                    controls
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(sideLabel) custom direction tuning")
    }

    private var directionPreview: some View {
        JoystickDirectionRadialPreview(
            horizontalSliceSize: horizontalSliceSize,
            verticalSliceSize: verticalSliceSize,
            deadzone: deadzone,
            invertY: invertY
        )
        .frame(width: 216, height: 216)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            presetMenu

            JoystickTuningSlider(
                label: "Horizontal Slice Width",
                systemImage: "arrow.left.and.right.circle",
                value: $horizontalSliceSize,
                range: 0...1.0
            )

            JoystickTuningSlider(
                label: "Vertical Slice Width",
                systemImage: "arrow.up.and.down.circle",
                value: $verticalSliceSize,
                range: 0...1.0
            )

            JoystickTuningSlider(
                label: "Center Deadzone",
                systemImage: "circle.dashed",
                value: $deadzone,
                range: 0...0.5
            )

            Toggle("Invert Y Axis", isOn: $invertY)
                .toggleStyle(.switch)
        }
        .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
    }

    private var presetMenu: some View {
        let preset = profileManager.stickDirectionPreset(side: side)

        return HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text("Direction Keys")
                .font(.callout)

            Spacer()

            Menu {
                Button("WASD") {
                    profileManager.setStickDirectionPreset(.wasd, side: side)
                }
                Button("Arrow Keys") {
                    profileManager.setStickDirectionPreset(.arrows, side: side)
                }
            } label: {
                HStack(spacing: 5) {
                    Text(preset?.shortLabel ?? "Custom")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(0.7)
                }
                .frame(minWidth: 68)
            }
            .menuStyle(.borderlessButton)
            .help("Set all four custom stick directions")
            .accessibilityLabel("Set all four custom stick directions")
        }
    }
}

struct JoystickDirectionSelectionGrid<ButtonContent: View>: View {
    let side: JoystickSide
    let mode: StickMode
    let buttonContent: (ControllerButton) -> ButtonContent

    init(
        side: JoystickSide,
        mode: StickMode,
        @ViewBuilder buttonContent: @escaping (ControllerButton) -> ButtonContent
    ) {
        self.side = side
        self.mode = mode
        self.buttonContent = buttonContent
    }

    private var sideLabel: String {
        switch side {
        case .left: return "Left Stick Directions"
        case .right: return "Right Stick Directions"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: side == .left ? "l.circle" : "r.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(sideLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                Text(mode.displayName)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.75))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(spacing: 2) {
                buttonContent(ControllerButton.joystickDirectionButton(side: side, direction: .up))

                HStack(spacing: 25) {
                    buttonContent(ControllerButton.joystickDirectionButton(side: side, direction: .left))
                    buttonContent(ControllerButton.joystickDirectionButton(side: side, direction: .right))
                }

                buttonContent(ControllerButton.joystickDirectionButton(side: side, direction: .down))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(sideLabel), \(mode.displayName)")
    }
}

private struct JoystickTuningSlider: View {
    let label: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    private var percentage: Int {
        Int((value * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(label)
                    .font(.callout)

                Spacer()

                Text("\(percentage)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }

            Slider(value: $value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue("\(percentage)%")
        }
    }
}

private struct JoystickDirectionRadialPreview: View {
    let horizontalSliceSize: Double
    let verticalSliceSize: Double
    let deadzone: Double
    let invertY: Bool

    private var directions: [JoystickDirection] {
        [.up, .right, .down, .left]
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let rect = CGRect(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2,
                width: side,
                height: side
            )
            let radius = side / 2
            let deadzoneDiameter = max(18, side * CGFloat(clamped(deadzone)))

            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                    )
                    .frame(width: side, height: side)
                    .position(x: rect.midX, y: rect.midY)

                ForEach(directions, id: \.self) { direction in
                    JoystickDirectionSector(
                        centerDegrees: centerDegrees(for: direction),
                        sweepDegrees: sweepDegrees(for: direction)
                    )
                    .fill(fillColor(for: direction))
                    .frame(width: side, height: side)
                    .position(x: rect.midX, y: rect.midY)
                }

                ForEach(directions, id: \.self) { direction in
                    Text(direction.arrowLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        )
                        .position(labelPoint(for: direction, center: CGPoint(x: rect.midX, y: rect.midY), radius: radius * 0.72))
                }

                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: deadzoneDiameter, height: deadzoneDiameter)
                    .overlay(
                        Circle()
                            .stroke(Color.accentColor.opacity(0.82), lineWidth: 2)
                    )
                    .position(x: rect.midX, y: rect.midY)

                Circle()
                    .fill(Color.secondary.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: invertY ? "arrow.up.arrow.down.circle.fill" : "circle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                    )
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func fillColor(for direction: JoystickDirection) -> Color {
        return Color.accentColor.opacity(0.34)
    }

    private func labelPoint(for direction: JoystickDirection, center: CGPoint, radius: CGFloat) -> CGPoint {
        let radians = centerDegrees(for: direction) * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }

    private func centerDegrees(for direction: JoystickDirection) -> CGFloat {
        switch direction {
        case .right: return 0
        case .downRight: return 45
        case .down: return 90
        case .downLeft: return 135
        case .left: return 180
        case .upLeft: return 225
        case .up: return 270
        case .upRight: return 315
        }
    }

    private func sweepDegrees(for direction: JoystickDirection) -> CGFloat {
        switch direction {
        case .left, .right:
            return sliceSweepDegrees(horizontalSliceSize)
        case .up, .down:
            return sliceSweepDegrees(verticalSliceSize)
        case .upLeft, .upRight, .downLeft, .downRight:
            return 0
        }
    }

    private func sliceSweepDegrees(_ size: Double) -> CGFloat {
        CGFloat(clamped(size)) * 90
    }

    private func clamped(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

private struct JoystickDirectionSector: Shape {
    let centerDegrees: CGFloat
    let sweepDegrees: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = Angle.degrees(Double(centerDegrees - sweepDegrees / 2))
        let end = Angle.degrees(Double(centerDegrees + sweepDegrees / 2))

        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: start,
            endAngle: end,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
