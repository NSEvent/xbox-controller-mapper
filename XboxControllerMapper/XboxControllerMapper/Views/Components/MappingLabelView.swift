import SwiftUI
import AppKit

/// Tooltip position relative to the hover target
enum TooltipPosition {
    case right      // Vertically centered, to the right
    case topRight   // Above and to the right
}

/// Custom NSView that shows a tooltip window on hover
class TooltipNSView: NSView {
    var tooltipText: String = ""
    var position: TooltipPosition = .right
    private var tooltipWindow: NSWindow?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        showTooltip()
    }

    override func mouseExited(with event: NSEvent) {
        hideTooltip()
    }

    override func removeFromSuperview() {
        hideTooltip()
        super.removeFromSuperview()
    }

    private func showTooltip() {
        guard !tooltipText.isEmpty, tooltipWindow == nil else { return }

        let label = NSTextField(labelWithString: tooltipText)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.sizeToFit()

        let padding: CGFloat = 6
        let windowSize = NSSize(
            width: label.frame.width + padding * 2,
            height: label.frame.height + padding * 2
        )

        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.ignoresMouseEvents = true

        let container = NSView(frame: NSRect(origin: .zero, size: windowSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 4
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        label.frame.origin = NSPoint(x: padding, y: padding)
        container.addSubview(label)
        window.contentView = container

        // Position relative to the hover target
        if let screenFrame = self.window?.convertToScreen(self.convert(self.bounds, to: nil)) {
            let x = screenFrame.maxX + 4
            let y: CGFloat
            switch position {
            case .topRight:
                y = screenFrame.maxY + 2
            case .right:
                y = screenFrame.midY - windowSize.height / 2
            }
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFrontRegardless()
        tooltipWindow = window
    }

    private func hideTooltip() {
        tooltipWindow?.orderOut(nil)
        tooltipWindow = nil
    }
}

/// SwiftUI wrapper for the custom tooltip view
struct TooltipView: NSViewRepresentable {
    let tooltip: String
    var position: TooltipPosition = .right

    func makeNSView(context: Context) -> TooltipNSView {
        let view = TooltipNSView()
        view.tooltipText = tooltip
        view.position = position
        return view
    }

    func updateNSView(_ nsView: TooltipNSView, context: Context) {
        nsView.tooltipText = tooltip
        nsView.position = position
    }
}

extension View {
    @ViewBuilder
    func tooltipIfPresent(_ text: String?, position: TooltipPosition = .right) -> some View {
        if let text = text, !text.isEmpty {
            self.overlay(TooltipView(tooltip: text, position: position))
        } else {
            self
        }
    }
}

/// A view that displays a key mapping with colored icons for long hold and double tap
struct MappingLabelView: View {
    let mapping: KeyMapping
    var horizontal: Bool = false
    var font: Font = .system(size: 16, weight: .bold, design: .rounded)
    var foregroundColor: Color = .primary
    
    @EnvironmentObject var profileManager: ProfileManager

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
        if let systemCommand = mapping.systemCommand {
            labelRow(text: systemCommand.displayName, icon: "SYS", color: .green, tooltip: nil)

        } else if let macroId = mapping.macroId,
           let profile = profileManager.activeProfile,
           let macro = profile.macros.first(where: { $0.id == macroId }) {

            // Check hint first, then fall back to macro name
            let displayText = (mapping.hint?.isEmpty == false) ? mapping.hint! : macro.name
            labelRow(text: displayText, icon: "▶", color: .purple, tooltip: (mapping.hint?.isEmpty == false) ? macro.name : nil)

        } else if !mapping.isEmpty {
            // Show purple ▼ badge for hold-type mappings
            let holdIcon: String? = mapping.isHoldModifier ? "▼" : nil
            let holdColor: Color = mapping.isHoldModifier ? .purple : .primary
            if let hint = mapping.hint, !hint.isEmpty {
                labelRow(text: hint, icon: holdIcon, color: holdColor, tooltip: mapping.displayString)
            } else {
                labelRow(text: mapping.displayString, icon: holdIcon, color: holdColor, tooltip: nil)
            }
        } else if (mapping.longHoldMapping?.isEmpty ?? true) && (mapping.doubleTapMapping?.isEmpty ?? true) {
            Text("Unmapped")
                .font(font)
                .foregroundColor(.secondary)
                .italic()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }

        if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
            if let hint = longHold.hint, !hint.isEmpty {
                labelRow(text: hint, icon: "⏱", color: .orange, tooltip: longHold.displayString)
            } else {
                labelRow(text: longHold.displayString, icon: "⏱", color: .orange, tooltip: nil)
            }
        }

        if let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty {
            if let hint = doubleTap.hint, !hint.isEmpty {
                labelRow(text: hint, icon: "2×", color: .cyan, tooltip: doubleTap.displayString)
            } else {
                labelRow(text: doubleTap.displayString, icon: "2×", color: .cyan, tooltip: nil)
            }
        }
    }

    @ViewBuilder
    private func labelRow(text: String, icon: String?, color: Color, tooltip: String?) -> some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Text(icon)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(color)
                    .cornerRadius(3)
            }

            Text(text)
                .font(font)
                .foregroundColor(foregroundColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
        .tooltipIfPresent(tooltip)
    }
}
