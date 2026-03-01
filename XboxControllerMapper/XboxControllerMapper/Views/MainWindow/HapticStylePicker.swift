import SwiftUI

/// Reusable picker for selecting an optional haptic feedback style on a mapping.
struct HapticStylePicker: View {
    @Binding var hapticStyle: HapticStyle?

    var body: some View {
        HStack {
            Text("Haptic:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("", selection: $hapticStyle) {
                Text("None").tag(HapticStyle?.none)
                ForEach(HapticStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(HapticStyle?.some(style))
                }
            }
            .labelsHidden()
            .frame(width: 140)
        }
    }
}
