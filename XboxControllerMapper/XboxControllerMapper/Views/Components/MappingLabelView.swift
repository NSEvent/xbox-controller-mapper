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
            if let hint = mapping.hint, !hint.isEmpty {
                labelRow(text: hint, icon: nil, color: .primary, tooltip: mapping.displayString)
            } else {
                labelRow(text: mapping.displayString, icon: nil, color: .primary, tooltip: nil)
            }
        } else if (mapping.longHoldMapping?.isEmpty ?? true) && (mapping.doubleTapMapping?.isEmpty ?? true) {
            Text("Unmapped")
                .font(font)
                .foregroundColor(.secondary)
                .italic()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }

        if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
            if let hint = longHold.hint, !hint.isEmpty {
                labelRow(text: hint, icon: "⏱", color: .orange, tooltip: longHold.displayString)
            } else {
                labelRow(text: longHold.displayString, icon: "⏱", color: .orange, tooltip: nil)
            }
        }

        if let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty {
            if let hint = doubleTap.hint, !hint.isEmpty {
                labelRow(text: hint, icon: "2×", color: .cyan, tooltip: doubleTap.displayString)
            } else {
                labelRow(text: doubleTap.displayString, icon: "2×", color: .cyan, tooltip: nil)
            }
        }
    }

    @ViewBuilder
    private func labelRow(text: String, icon: String?, color: Color, tooltip: String?) -> some View {
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
        .help(tooltip ?? "")
    }
}
