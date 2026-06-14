import SwiftUI

struct CanvasScrollEventViewReader: NSViewRepresentable {
    @Binding var view: NSView?

    func makeNSView(context: Context) -> NSView {
        CanvasScrollEventView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let binding = $view
        DispatchQueue.main.async {
            if binding.wrappedValue !== nsView {
                binding.wrappedValue = nsView
            }
        }
    }
}

private final class CanvasScrollEventView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
