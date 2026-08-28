import SwiftUI
import AppKit

/// One-time, dismissible nudge asking a happy licensed user to leave a review.
/// Presented from `ContentView` when `ReviewRequestManager` says it's due.
struct ReviewRequestSheet: View {
    var onLeaveReview: () -> Void
    var onNotNow: () -> Void
    var onDontAskAgain: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(spacing: 6) {
                Text("Enjoying ControllerKeys?")
                    .font(.title2.bold())
                Text("A short review on Gumroad helps other controller people find it — and genuinely helps an indie app grow.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                Button {
                    onLeaveReview()
                } label: {
                    Text("Leave a Review")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Not Now") {
                    onNotNow()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Don't Ask Again") {
                    onDontAskAgain()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
