import SwiftUI

/// Sheet with card preview and "Copy to Clipboard" button
struct WrappedCardSheet: View {
    @EnvironmentObject var usageStatsService: UsageStatsService
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Your Controller Wrapped")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            WrappedCardView(
                stats: usageStatsService.stats,
                isDualSense: controllerService.threadSafeIsDualSense
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)

            HStack(spacing: 16) {
                Button {
                    copyCardToClipboard()
                } label: {
                    Label(
                        copied ? "Copied!" : "Copy to Clipboard",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(copied ? .green : .blue)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 700)
        .background(Color.black.opacity(0.92))
    }

    @MainActor
    private func copyCardToClipboard() {
        let card = WrappedCardView(
            stats: usageStatsService.stats,
            isDualSense: controllerService.threadSafeIsDualSense
        )

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0

        guard let image = renderer.nsImage else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
