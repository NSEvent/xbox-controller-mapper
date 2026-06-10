import SwiftUI
import GameController

// MARK: - Controller Body Shapes

struct SteamControllerBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        path.move(to: CGPoint(x: width * 0.18, y: height * 0.13))
        path.addCurve(
            to: CGPoint(x: width * 0.82, y: height * 0.13),
            control1: CGPoint(x: width * 0.34, y: height * 0.03),
            control2: CGPoint(x: width * 0.66, y: height * 0.03)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.98, y: height * 0.44),
            control1: CGPoint(x: width * 0.94, y: height * 0.12),
            control2: CGPoint(x: width * 0.99, y: height * 0.25)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.78, y: height * 0.94),
            control1: CGPoint(x: width * 1.02, y: height * 0.66),
            control2: CGPoint(x: width * 0.92, y: height * 0.91)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.22, y: height * 0.94),
            control1: CGPoint(x: width * 0.62, y: height * 0.78),
            control2: CGPoint(x: width * 0.38, y: height * 0.78)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.02, y: height * 0.44),
            control1: CGPoint(x: width * 0.08, y: height * 0.91),
            control2: CGPoint(x: width * -0.02, y: height * 0.66)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.18, y: height * 0.13),
            control1: CGPoint(x: width * 0.01, y: height * 0.25),
            control2: CGPoint(x: width * 0.06, y: height * 0.12)
        )
        path.closeSubpath()
        return path
    }
}

struct ControllerBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        path.move(to: CGPoint(x: width * 0.2, y: height * 0.15))
        path.addCurve(to: CGPoint(x: width * 0.8, y: height * 0.15), control1: CGPoint(x: width * 0.35, y: height * 0.05), control2: CGPoint(x: width * 0.65, y: height * 0.05))
        path.addQuadCurve(to: CGPoint(x: width * 0.95, y: height * 0.35), control: CGPoint(x: width * 0.98, y: height * 0.2))
        path.addCurve(to: CGPoint(x: width * 0.75, y: height * 0.9), control1: CGPoint(x: width * 1.0, y: height * 0.6), control2: CGPoint(x: width * 0.9, y: height * 0.85))
        path.addQuadCurve(to: CGPoint(x: width * 0.25, y: height * 0.9), control: CGPoint(x: width * 0.5, y: height * 0.75))
        path.addCurve(to: CGPoint(x: width * 0.05, y: height * 0.35), control1: CGPoint(x: width * 0.1, y: height * 0.85), control2: CGPoint(x: width * 0.0, y: height * 0.6))
        path.addQuadCurve(to: CGPoint(x: width * 0.2, y: height * 0.15), control: CGPoint(x: width * 0.02, y: height * 0.2))
        path.closeSubpath()
        return path
    }
}

/// DualSense controller body shape - distinctive split design with wing-like grips
struct DualSenseBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        // DualSense key features: wing-like handles that flare out, split/V bottom

        // Start at top-left
        path.move(to: CGPoint(x: width * 0.18, y: height * 0.10))

        // Top edge - wide and flat
        path.addQuadCurve(
            to: CGPoint(x: width * 0.82, y: height * 0.10),
            control: CGPoint(x: width * 0.5, y: height * 0.05)
        )

        // Right shoulder - curves outward to the wing
        path.addCurve(
            to: CGPoint(x: width * 0.98, y: height * 0.45),
            control1: CGPoint(x: width * 0.92, y: height * 0.10),
            control2: CGPoint(x: width * 1.0, y: height * 0.28)
        )

        // Right wing/handle - flares out then curves back in dramatically
        path.addCurve(
            to: CGPoint(x: width * 0.62, y: height * 0.95),
            control1: CGPoint(x: width * 0.98, y: height * 0.70),
            control2: CGPoint(x: width * 0.78, y: height * 0.92)
        )

        // Bottom split - smooth convex curve bulging outward
        path.addQuadCurve(
            to: CGPoint(x: width * 0.38, y: height * 0.95),
            control: CGPoint(x: width * 0.5, y: height * 0.98)
        )

        // Left wing/handle - mirror of right
        path.addCurve(
            to: CGPoint(x: width * 0.02, y: height * 0.45),
            control1: CGPoint(x: width * 0.22, y: height * 0.92),
            control2: CGPoint(x: width * 0.02, y: height * 0.70)
        )

        // Left shoulder - curves back to top
        path.addCurve(
            to: CGPoint(x: width * 0.18, y: height * 0.10),
            control1: CGPoint(x: width * 0.0, y: height * 0.28),
            control2: CGPoint(x: width * 0.08, y: height * 0.10)
        )

        path.closeSubpath()
        return path
    }
}

/// Nintendo Switch Pro Controller body shape - wide, rounded rectangular form with smooth grips
struct NintendoProBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        // Pro Controller: wider and more rounded than Xbox, with straighter top edge
        // and smooth cylindrical grips that curve gently outward

        // Start at top-left
        path.move(to: CGPoint(x: width * 0.22, y: height * 0.12))

        // Top edge - wide and gently curved
        path.addQuadCurve(
            to: CGPoint(x: width * 0.78, y: height * 0.12),
            control: CGPoint(x: width * 0.5, y: height * 0.06)
        )

        // Right shoulder - smooth curve into grip
        path.addCurve(
            to: CGPoint(x: width * 0.96, y: height * 0.40),
            control1: CGPoint(x: width * 0.90, y: height * 0.12),
            control2: CGPoint(x: width * 0.97, y: height * 0.25)
        )

        // Right grip - smooth cylindrical shape, less angular than Xbox
        path.addCurve(
            to: CGPoint(x: width * 0.72, y: height * 0.92),
            control1: CGPoint(x: width * 0.97, y: height * 0.62),
            control2: CGPoint(x: width * 0.85, y: height * 0.88)
        )

        // Bottom edge - wide rounded curve connecting grips
        path.addQuadCurve(
            to: CGPoint(x: width * 0.28, y: height * 0.92),
            control: CGPoint(x: width * 0.5, y: height * 0.80)
        )

        // Left grip - mirror of right
        path.addCurve(
            to: CGPoint(x: width * 0.04, y: height * 0.40),
            control1: CGPoint(x: width * 0.15, y: height * 0.88),
            control2: CGPoint(x: width * 0.03, y: height * 0.62)
        )

        // Left shoulder - back to top
        path.addCurve(
            to: CGPoint(x: width * 0.22, y: height * 0.12),
            control1: CGPoint(x: width * 0.03, y: height * 0.25),
            control2: CGPoint(x: width * 0.10, y: height * 0.12)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Shared Components

struct BatteryView: View {
    let level: Float
    let state: GCDeviceBattery.State
    
    // Xbox controllers on macOS often report 0.0 with unknown state when data is unavailable
    private var isUnknown: Bool {
		!ControllerBatteryDisplayPolicy.isKnown(level: level, state: state)
    }

    private var percentage: Int? {
		ControllerBatteryDisplayPolicy.percentage(level: level, state: state)
    }
    
    var body: some View {
        HStack(spacing: 2) {
            if state == .charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
            }
            
            ZStack(alignment: .leading) {
                // Battery outline
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.primary.opacity(0.4), lineWidth: 1)
                    .frame(width: 30, height: 14)
                
                // Empty track background
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 28, height: 12)
                    .padding(.leading, 1)

                // Fill
                if !isUnknown {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(batteryColor)
                            .frame(width: max(2, 28 * CGFloat(level)), height: 12)
                        
						Text("\(percentage ?? 0)%")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0)
                            .frame(width: 28, alignment: .center)
                    }
                    .padding(.leading, 1)
                } else {
                    // Unknown level
                    Text("?")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 14, alignment: .center)
                }
            }
            
            // Battery tip
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.4))
                .frame(width: 2, height: 4)
        }
		.help(percentage.map { "Battery: \($0)%" } ?? "Battery level unavailable (common macOS limitation for Xbox controllers)")
		.accessibilityLabel(percentage.map { "Battery: \($0) percent" } ?? "Battery unavailable")
    }
    
    private var batteryColor: Color {
        if state == .charging { return .green }
        if level > 0.6 { return .green }
        if level > 0.2 { return .orange }
        return .red
    }
}
