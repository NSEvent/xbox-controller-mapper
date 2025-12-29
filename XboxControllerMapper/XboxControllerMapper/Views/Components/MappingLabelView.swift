import SwiftUI

/// A view that displays a key mapping with colored icons for long hold and double tap
struct MappingLabelView: View {
    let mapping: KeyMapping
    var font: Font = .system(size: 11, weight: .bold)
    var foregroundColor: Color = .white
    var horizontal: Bool = false

    var body: some View {
        if horizontal {
            HStack(spacing: 8) {
                content
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !mapping.isEmpty {
            Text(mapping.displayString)
                .font(font)
                .foregroundColor(foregroundColor)
        }

        if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
            HStack(spacing: 2) {
                Text("⏱")
                    .foregroundColor(.orange)
                Text(longHold.displayString)
            }
            .font(font)
            .foregroundColor(foregroundColor)
        }

        if let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty {
            HStack(spacing: 2) {
                Text("×2")
                    .foregroundColor(.cyan)
                Text(doubleTap.displayString)
            }
            .font(font)
            .foregroundColor(foregroundColor)
        }
    }
}
