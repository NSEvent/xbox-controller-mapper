import SwiftUI
import AppKit

// MARK: - Hoverable Row Modifier

/// A modifier for list rows that need background highlight + cursor change on hover
struct HoverableRowModifier: ViewModifier {
    let onTap: (() -> Void)?
    @State private var isHovered = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let base = content
            .contentShape(Rectangle())
            .background(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
            .cornerRadius(6)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

        if let onTap = onTap {
            base.onTapGesture { onTap() }
        } else {
            base
        }
    }
}

// MARK: - Hoverable Glass Row Modifier

/// A modifier for rows using GlassCardBackground styling
struct HoverableGlassRowModifier: ViewModifier {
    let isActive: Bool
    let onTap: (() -> Void)?
    @State private var isHovered = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let base = content
            .contentShape(Rectangle())
            .background(GlassCardBackground(isActive: isActive, isHovered: isHovered))
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

        if let onTap = onTap {
            base.onTapGesture { onTap() }
        } else {
            base
        }
    }
}

// MARK: - Hoverable Modifier (Cursor Only)

/// A simple modifier that only changes cursor on hover (for toolbar buttons)
struct HoverableModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Adds hover highlighting and pointing hand cursor to a row
    /// - Parameter onTap: Optional tap handler
    func hoverableRow(onTap: (() -> Void)? = nil) -> some View {
        modifier(HoverableRowModifier(onTap: onTap))
    }

    /// Adds GlassCardBackground styling with hover effects and pointing hand cursor
    /// - Parameters:
    ///   - isActive: Whether the row is in an active/selected state
    ///   - onTap: Optional tap handler
    func hoverableGlassRow(isActive: Bool = false, onTap: (() -> Void)? = nil) -> some View {
        modifier(HoverableGlassRowModifier(isActive: isActive, onTap: onTap))
    }

    /// Adds pointing hand cursor on hover (for buttons/interactive elements)
    func hoverable() -> some View {
        modifier(HoverableModifier())
    }
}
