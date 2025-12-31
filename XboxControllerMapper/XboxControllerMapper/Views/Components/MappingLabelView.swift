import SwiftUI

/// A view that displays a key mapping with colored icons for long hold and double tap
struct MappingLabelView: View {
    let mapping: KeyMapping
    var horizontal: Bool = false
    var font: Font = .system(size: 16, weight: .bold, design: .rounded)
    var foregroundColor: Color = .primary

    var body: some View {
        if horizontal {
            HStack(spacing: 16) {
                content
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !mapping.isEmpty {
            labelRow(text: mapping.displayString, icon: nil, color: .primary)
        } else if (mapping.longHoldMapping?.isEmpty ?? true) && (mapping.doubleTapMapping?.isEmpty ?? true) {
            Text("Unmapped")
                .font(font)
                .foregroundColor(.secondary)
                .italic()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }

        if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
            labelRow(text: longHold.displayString, icon: "⏱", color: .orange)
        }

        if let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty {
            labelRow(text: doubleTap.displayString, icon: "2×", color: .cyan)
        }
    }

    @ViewBuilder
    private func labelRow(text: String, icon: String?, color: Color) -> some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Text(icon)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(color)
                    .cornerRadius(3)
            }
            
            Text(text)
                .font(font)
                .foregroundColor(foregroundColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}
