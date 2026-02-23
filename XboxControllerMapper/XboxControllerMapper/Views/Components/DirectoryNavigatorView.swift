import SwiftUI

/// Two-column Miller columns-style directory browser overlay
struct DirectoryNavigatorView: View {
    @ObservedObject var manager: DirectoryNavigatorManager

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb bar
            breadcrumbBar

            // Two-column layout
            HStack(spacing: 0) {
                // Left column: current directory
                directoryColumn(
                    entries: manager.currentEntries,
                    selectedIndex: manager.selectedIndex,
                    isPreview: false
                )

                Divider()
                    .background(Color.white.opacity(0.15))

                // Right column: preview of selected subdirectory
                directoryColumn(
                    entries: manager.previewEntries,
                    selectedIndex: nil,
                    isPreview: true
                )
            }
            .frame(height: 360)

            // Hint bar
            hintBar
        }
        .frame(width: 560)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Breadcrumb Bar

    private var breadcrumbBar: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 13))
            Text(manager.displayPath)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
    }

    // MARK: - Directory Column

    private func directoryColumn(entries: [DirectoryEntry], selectedIndex: Int?, isPreview: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        directoryRow(entry: entry, isSelected: selectedIndex == index, isPreview: isPreview)
                            .id(entry.id)
                    }
                }
            }
            .onChange(of: selectedIndex) { newIndex in
                if let newIndex, newIndex < entries.count {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(entries[newIndex].id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func directoryRow(entry: DirectoryEntry, isSelected: Bool, isPreview: Bool) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: entry.icon)
                .resizable()
                .frame(width: 18, height: 18)

            Text(entry.name)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundColor(isPreview ? .white.opacity(0.55) : .white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isPreview ? .white.opacity(0.25) : .white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.7))
                    .padding(.horizontal, 4)
                : nil
        )
    }

    // MARK: - Hint Bar

    private var hintBar: some View {
        HStack(spacing: 16) {
            hintItem(icon: "arrow.up.arrow.down", text: "Navigate")
            hintItem(icon: "arrow.right", text: "Enter")
            hintItem(icon: "arrow.left", text: "Back")
            hintItem(symbol: "a.circle", text: "cd here")
            hintItem(symbol: "y.circle", text: "Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
    }

    private func hintItem(icon: String? = nil, symbol: String? = nil, text: String) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}
