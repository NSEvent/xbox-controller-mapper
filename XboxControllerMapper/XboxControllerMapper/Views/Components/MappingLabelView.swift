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
                    .frame(width: 24)
            }
            
            Text(text)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
