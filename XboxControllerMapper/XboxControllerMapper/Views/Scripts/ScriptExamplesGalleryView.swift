import SwiftUI

struct ScriptExamplesGalleryView: View {
    var onSelect: (ScriptExample) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Example Scripts")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ScriptExamplesData.all) { example in
                        ExampleCard(example: example)
                            .onTapGesture {
                                onSelect(example)
                                dismiss()
                            }
                    }
                }
                .padding()
            }
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - Example Card

private struct ExampleCard: View {
    let example: ScriptExample
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: example.icon)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14))
                    .frame(width: 20)

                Text(example.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }

            Text(example.description)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                ForEach(example.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassCardBackground(isHovered: isHovered))
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}
