import SwiftUI

/// Standalone "Controller Connection Guides" browser, opened from
/// **Help → Controller Connection Guides** in the menu bar.
///
/// It reuses `ControllerPairingHintView` verbatim: starting on `.active` shows
/// the controller chooser grid; picking a controller swaps in that device's
/// step-by-step pairing guide; the card's "Choose different" button returns to
/// the grid. So the same pairing content that appears in the Buttons-tab empty
/// state is reachable on demand from the Help menu — even while a controller is
/// already connected (when that empty state would otherwise be hidden).
struct ConnectionGuidesView: View {
    /// `.active` resolves to no single device, so its `pairingGuide` is nil and
    /// `ControllerPairingHintView` renders the chooser grid — the right landing
    /// state for a guides index.
    @State private var layout: ControllerPreviewLayout = .active

    var body: some View {
        // Fixed width, height follows the content. Paired with the scene's
        // `.windowResizability(.contentSize)`, the window sizes itself to the
        // current view and re-sizes automatically as `layout` changes — the
        // chooser router is compact, and each controller's guide grows the
        // window to fit its card (notably the tall Siri Remote), so nothing is
        // ever clipped and there's no need to resize or scroll.
        ControllerPairingHintView(previewLayout: layout) { selected in
            layout = selected
        }
        .padding(20)
        .frame(width: 600)
        // Match the main window's liquid-glass treatment so the guides window
        // doesn't read as a plain system sheet. A fixed dark tint (the main
        // window's is user-configurable) keeps the card text legible here.
        .background(
            ZStack {
                GlassVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(white: 0.2).opacity(0.82)
            }
            .ignoresSafeArea()
        )
    }
}
