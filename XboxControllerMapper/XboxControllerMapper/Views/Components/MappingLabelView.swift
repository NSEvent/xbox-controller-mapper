import SwiftUI

/// A view that displays a key mapping with colored icons for long hold and double tap
struct MappingLabelView: View {
    let mapping: KeyMapping
    var font: Font = .system(size: 14, weight: .bold) // Increased base font size
    var foregroundColor: Color = .primary
    var horizontal: Bool = false

    var body: some View {
        if horizontal {
            HStack(spacing: 12) {
                content
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !mapping.isEmpty {
            labelRow(text: mapping.displayString, icon: nil, color: .primary)
        }

        if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
            labelRow(text: longHold.displayString, icon: "⏱", color: .orange)
        }

        if let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty {
            labelRow(text: doubleTap.displayString, icon: "×2", color: .cyan)
        }
    }

    @ViewBuilder
    private func labelRow(text: String, icon: String?, color: Color) -> some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Text(icon)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(color)
                    .frame(width: 24, alignment: .leading)
            }
            
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .monospaced)) // Monospaced for better shortcut readability
                .foregroundColor(.primary)
        }
    }
}
