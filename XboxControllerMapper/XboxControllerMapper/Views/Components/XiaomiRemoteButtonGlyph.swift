import SwiftUI

/// Product-like thin etched symbols shared by the minimap and editor badges.
struct XiaomiRemoteButtonGlyph: View {
	let button: ControllerButton
	@ViewBuilder var body: some View {
		if button.category == .dpad {
			ZStack {
				Circle().stroke(lineWidth: 0.8)
				Circle().stroke(lineWidth: 0.8).padding(4)
				Circle().fill().frame(width: 2.5, height: 2.5).offset(y: -6)
			}.rotationEffect(.degrees(directionAngle))
		} else if button == .xiaomiTV {
			Text("TV").font(.system(size: 8, weight: .medium, design: .rounded))
				.fixedSize()
				.padding(.horizontal, 2).padding(.vertical, 1)
				.overlay(RoundedRectangle(cornerRadius: 2).stroke(lineWidth: 0.8))
		} else if button == .xiaomiOK {
			Circle().stroke(lineWidth: 1.2).padding(3)
		} else if let symbol = button.xiaomiRemoteSystemImage {
			Image(systemName: symbol)
		}
	}
	private var directionAngle: Double {
		switch button {
		case .dpadRight: return 90
		case .dpadDown: return 180
		case .dpadLeft: return 270
		default: return 0
		}
	}
}

struct XiaomiRemoteButtonBadge: View {
	let button: ControllerButton
	let pressed: Bool
	private var silver: Bool { button == .xiaomiPower || button == .xiaomiMicrophone }
	var body: some View {
		ZStack {
			Circle().fill(LinearGradient(colors: pressed ? [Color.accentColor, Color.accentColor.opacity(0.7)]
				: silver ? [Color(white: 0.84), Color(white: 0.66)] : [Color(white: 0.23), Color(white: 0.10)],
				startPoint: .topLeading, endPoint: .bottomTrailing))
				.overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 0.7))
			XiaomiRemoteButtonGlyph(button: button).font(.system(size: 12, weight: .regular))
				.foregroundStyle(silver && !pressed ? Color.black.opacity(0.8) : Color(white: 0.88))
				.frame(width: 15, height: 15)
		}.frame(width: 28, height: 28).scaleEffect(pressed ? 0.94 : 1)
			.accessibilityHidden(true)
	}
}
