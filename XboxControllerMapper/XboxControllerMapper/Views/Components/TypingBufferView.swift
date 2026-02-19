import SwiftUI

/// Floating text buffer that shows typed characters above the on-screen keyboard
struct TypingBufferView: View {
    let text: String

    @State private var cursorVisible = true

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.head)

            // Blinking cursor — fixed width so it doesn't shift the text horizontally
            Rectangle()
                .fill(Color.white)
                .frame(width: 1.5, height: 18)
                .opacity(cursorVisible ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorVisible)
                .padding(.leading, 2)
                .onAppear { cursorVisible = false }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                Color.black.opacity(0.6)
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .fixedSize()
    }
}
