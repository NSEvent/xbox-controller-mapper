import SwiftUI

struct InputLogView: View {
    @EnvironmentObject var inputLogService: InputLogService
    @EnvironmentObject var controllerService: ControllerService

    private var isDualSense: Bool {
        controllerService.threadSafeIsDualSense
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(inputLogService.entries) { entry in
                    LogEntryView(entry: entry, isLast: entry.id == inputLogService.entries.last?.id, isDualSense: isDualSense)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(height: 70)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .bottom
        )
    }
}

private struct LogEntryView: View, Equatable {
    let entry: InputLogEntry
    let isLast: Bool
    let isDualSense: Bool

    static func == (lhs: LogEntryView, rhs: LogEntryView) -> Bool {
        lhs.isLast == rhs.isLast && lhs.entry == rhs.entry && lhs.isDualSense == rhs.isDualSense
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                // Top: Button(s) + Type
                HStack(spacing: 4) {
                    ForEach(entry.buttons, id: \.self) { button in
                        ButtonIconView(button: button, isDualSense: isDualSense)
                    }
                    
                    if entry.type != .singlePress {
                        Text(entry.type.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(badgeColor(for: entry.type).opacity(0.2)))
                            .foregroundColor(badgeColor(for: entry.type))
                            .overlay(
                                Capsule()
                                    .stroke(badgeColor(for: entry.type).opacity(0.5), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                )
                
                // Bottom: Action
                Text(entry.actionDescription)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                
            }
            .padding(.horizontal, 8)
            .drawingGroup() // Optimize rendering of the cell
            
            // Separator arrow
            if !isLast {
                Image(systemName: "chevron.left") // Newest is at left/start
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.3))
                    .padding(.horizontal, 2)
            }
        }
        // Use simple opacity transition - complex spring animations block input handling
        .transition(.opacity)
    }
    
    private func badgeColor(for type: InputEventType) -> Color {
        switch type {
        case .singlePress: return .secondary
        case .doubleTap: return .orange
        case .longPress: return .purple
        case .chord: return .blue
        }
    }
}
