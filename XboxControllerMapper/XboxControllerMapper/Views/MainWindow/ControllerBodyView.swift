import SwiftUI

// MARK: - Controller Body View
//
// Styled, non-interactive controller body: traced silhouette filled with
// the product's material colors plus decorative details (two-tone decks,
// light bars, speaker grilles, grip shading). Interactive controls are
// layered on top by `ControllerAnalogOverlay` using the same
// `ControllerMinimapLayout` coordinates.

struct ControllerBodyView: View {
    let style: ControllerMinimapStyle

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                bodyFill
                decorations(in: size)
            }
            .clipShape(AnyControllerBodyShape(style: style))
            .overlay(
                AnyControllerBodyShape(style: style)
                    .stroke(rimColor, lineWidth: 1)
            )
        }
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
    }

    // MARK: Materials

    @ViewBuilder
    private var bodyFill: some View {
        switch style {
        case .xbox:
            // Carbon black
            LinearGradient(
                colors: [Color(white: 0.30), Color(white: 0.16)],
                startPoint: .top, endPoint: .bottom
            )
        case .xboxElite:
            LinearGradient(
                colors: [Color(white: 0.24), Color(white: 0.10)],
                startPoint: .top, endPoint: .bottom
            )
        case .dualSense, .dualSenseEdge:
            // PlayStation white
            LinearGradient(
                colors: [Color(white: 0.98), Color(white: 0.80)],
                startPoint: .top, endPoint: .bottom
            )
        case .dualShock:
            LinearGradient(
                colors: [Color(white: 0.26), Color(white: 0.12)],
                startPoint: .top, endPoint: .bottom
            )
        case .nintendo:
            LinearGradient(
                colors: [Color(white: 0.25), Color(white: 0.13)],
                startPoint: .top, endPoint: .bottom
            )
        case .steam:
            LinearGradient(
                colors: [Color(white: 0.28), Color(white: 0.14)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var rimColor: Color {
        switch style {
        case .dualSense, .dualSenseEdge:
            return Color.white.opacity(0.65)
        default:
            return Color.white.opacity(0.16)
        }
    }

    // MARK: Decorations

    @ViewBuilder
    private func decorations(in size: CGSize) -> some View {
        switch style {
        case .xbox, .xboxElite:
            xboxDecor(in: size)
        case .dualSense:
            dualSenseDecor(in: size, edge: false)
        case .dualSenseEdge:
            dualSenseDecor(in: size, edge: true)
        case .dualShock:
            dualShockDecor(in: size)
        case .nintendo:
            nintendoDecor(in: size)
        case .steam:
            steamDecor(in: size)
        }
    }

    /// Soft top sheen + darker grip lobes shared by the dark controllers.
    private func darkBodySheen(in size: CGSize, gripY: CGFloat = 0.72) -> some View {
        ZStack {
            // Top sheen
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: size.width * 0.9, height: size.height * 0.5)
                .position(x: size.width * 0.5, y: size.height * 0.12)

            // Grip lobes, slightly darker than the face
            ForEach([0.13, 0.87], id: \.self) { x in
                Ellipse()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: size.width * 0.26, height: size.height * 0.62)
                    .rotationEffect(.degrees(x < 0.5 ? 24 : -24))
                    .position(x: size.width * x, y: size.height * gripY)
                    .blur(radius: 10)
            }
        }
    }

    private func xboxDecor(in size: CGSize) -> some View {
        darkBodySheen(in: size)
    }

    private func dualSenseDecor(in size: CGSize, edge: Bool) -> some View {
        let layout = DualSenseMinimapLayout.self
        return ZStack {
            // Black center deck wrapping the sticks, mic and PS button
            DualSenseDeckShape()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.13), Color(white: 0.05)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            // Soft shading where the wings meet the deck
            DualSenseDeckShape()
                .stroke(Color.black.opacity(0.18), lineWidth: 3)
                .blur(radius: 3)

            // Light bar strips hugging the touchpad's slanted edges
            ForEach([true, false], id: \.self) { isLeft in
                DualSenseLightBarShape(leftSide: isLeft)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.25, green: 0.5, blue: 1.0).opacity(0.9),
                                     Color(red: 0.15, green: 0.35, blue: 0.95).opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .shadow(color: Color(red: 0.2, green: 0.45, blue: 1.0).opacity(0.6), radius: 3)
            }

            // Mic grille dots below the touchpad
            VStack(spacing: size.width * 0.008) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: size.width * 0.012) {
                        ForEach(0..<7, id: \.self) { _ in
                            Circle()
                                .fill(Color(white: 0.30))
                                .frame(width: size.width * 0.006, height: size.width * 0.006)
                        }
                    }
                    .offset(x: row % 2 == 0 ? 0 : size.width * 0.006)
                }
            }
            .minimapPosition(layout.micGrille, in: size)
        }
    }

    private func dualShockDecor(in size: CGSize) -> some View {
        let layout = DualShockMinimapLayout.self
        return ZStack {
            darkBodySheen(in: size, gripY: 0.75)

            // Speaker grille between the sticks
            VStack(spacing: size.width * 0.010) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: size.width * 0.014) {
                        ForEach(0..<(5 - row % 2), id: \.self) { _ in
                            Circle()
                                .fill(Color(white: 0.07))
                                .frame(width: size.width * 0.008, height: size.width * 0.008)
                        }
                    }
                }
            }
            .minimapPosition(layout.speakerGrille, in: size)
        }
    }

    private func nintendoDecor(in size: CGSize) -> some View {
        ZStack {
            darkBodySheen(in: size, gripY: 0.74)

            // The Pro's glossy faceplate is slightly lighter than the grips
            Ellipse()
                .fill(Color.white.opacity(0.05))
                .frame(width: size.width * 0.74, height: size.height * 0.62)
                .position(x: size.width * 0.5, y: size.height * 0.30)
                .blur(radius: 12)
        }
    }

    private func steamDecor(in size: CGSize) -> some View {
        darkBodySheen(in: size, gripY: 0.78)
    }
}

/// Type-erasing wrapper so the same modifier chain can clip/stroke whichever
/// silhouette the style calls for.
struct AnyControllerBodyShape: Shape {
    let style: ControllerMinimapStyle

    func path(in rect: CGRect) -> Path {
        switch style {
        case .xbox: return ControllerBodyShape().path(in: rect)
        case .xboxElite: return XboxEliteBodyShape().path(in: rect)
        case .dualSense, .dualSenseEdge: return DualSenseBodyShape().path(in: rect)
        case .dualShock: return DualShockBodyShape().path(in: rect)
        case .nintendo: return NintendoProBodyShape().path(in: rect)
        case .steam: return SteamControllerBodyShape().path(in: rect)
        }
    }
}

// MARK: - DualSense detail shapes

/// The black center deck of the DualSense: tucks under the touchpad,
/// wraps both stick wells and dips into the bottom V notch.
struct DualSenseDeckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        p.move(to: CGPoint(x: w * 0.262, y: h * 0.43))
        // Up alongside the touchpad's left edge (the visible strip carries
        // the light bar)
        p.addCurve(
            to: CGPoint(x: w * 0.355, y: h * 0.27),
            control1: CGPoint(x: w * 0.285, y: h * 0.37),
            control2: CGPoint(x: w * 0.325, y: h * 0.295)
        )
        // Across behind the touchpad (hidden by the pad itself)
        p.addLine(to: CGPoint(x: w * 0.645, y: h * 0.27))
        // Down the right edge to the wing notch
        p.addCurve(
            to: CGPoint(x: w * 0.738, y: h * 0.43),
            control1: CGPoint(x: w * 0.675, y: h * 0.295),
            control2: CGPoint(x: w * 0.715, y: h * 0.37)
        )
        // Right side bulge around the stick
        p.addCurve(
            to: CGPoint(x: w * 0.715, y: h * 0.565),
            control1: CGPoint(x: w * 0.755, y: h * 0.475),
            control2: CGPoint(x: w * 0.745, y: h * 0.525)
        )
        // Down into the bottom V
        p.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.66),
            control1: CGPoint(x: w * 0.665, y: h * 0.635),
            control2: CGPoint(x: w * 0.585, y: h * 0.66)
        )
        // Mirror: left side of the V
        p.addCurve(
            to: CGPoint(x: w * 0.285, y: h * 0.565),
            control1: CGPoint(x: w * 0.415, y: h * 0.66),
            control2: CGPoint(x: w * 0.335, y: h * 0.635)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.262, y: h * 0.43),
            control1: CGPoint(x: w * 0.255, y: h * 0.525),
            control2: CGPoint(x: w * 0.245, y: h * 0.475)
        )
        p.closeSubpath()
        return p
    }
}

/// One of the two blue light strips flanking the DualSense touchpad.
struct DualSenseLightBarShape: Shape {
    let leftSide: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        func x(_ v: CGFloat) -> CGFloat { leftSide ? w * v : w * (1 - v) }

        // Strip hugging the touchpad's near-vertical side edge, widening
        // slightly toward the bottom like the real light bar.
        p.move(to: CGPoint(x: x(0.330), y: h * 0.085))
        p.addQuadCurve(
            to: CGPoint(x: x(0.338), y: h * 0.335),
            control: CGPoint(x: x(0.330), y: h * 0.21)
        )
        p.addLine(to: CGPoint(x: x(0.358), y: h * 0.33))
        p.addQuadCurve(
            to: CGPoint(x: x(0.342), y: h * 0.09),
            control: CGPoint(x: x(0.342), y: h * 0.21)
        )
        p.closeSubpath()
        return p
    }
}
