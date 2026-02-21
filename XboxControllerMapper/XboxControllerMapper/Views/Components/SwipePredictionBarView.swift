import SwiftUI

/// Horizontal bar of word prediction buttons shown after a swipe gesture completes.
struct SwipePredictionBarView: View {
    let predictions: [SwipeTypingPrediction]
    let selectedIndex: Int
    var onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(predictions.enumerated()), id: \.offset) { index, prediction in
                let isSelected = index == selectedIndex

                Button {
                    onSelect(index)
                } label: {
                    Text(prediction.word)
                        .font(.system(size: 15, weight: isSelected ? .bold : .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            GlassKeyBackground(
                                isHovered: false,
                                isPressed: isSelected,
                                specialColor: .cyan,
                                cornerRadius: 8,
                                isNavHighlighted: isSelected
                            )
                        )
                        .foregroundColor(isSelected ? .white : .primary)
                        .cornerRadius(8)
                        .scaleEffect(isSelected ? 1.08 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
