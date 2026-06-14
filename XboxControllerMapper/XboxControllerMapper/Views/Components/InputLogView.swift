import SwiftUI

struct InputLogView: View, ControllerTypeProviding {
    @EnvironmentObject var inputLogService: InputLogService
    @EnvironmentObject var controllerService: ControllerService

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 11, weight: .semibold))
                Text("Timeline")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.46))
            .frame(width: 76, alignment: .leading)

            if inputLogService.entries.isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    Text("Waiting for input")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 46)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(inputLogService.entries) { entry in
								LogEntryView(entry: entry, isLast: entry.id == inputLogService.entries.last?.id, isPlayStation: isPlayStation, isNintendo: isNintendo, isSteamController: isSteamController, isAppleTVRemote: isAppleTVRemote)
                        }
                    }
                    .frame(minHeight: 46)
                }
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .accessibilityLabel("Recent button presses")
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct LogEntryView: View, Equatable {
    let entry: InputLogEntry
    let isLast: Bool
	    let isPlayStation: Bool  // True for DualSense/DualShock - used for PS-style labels
	    let isNintendo: Bool
	    let isSteamController: Bool
	    let isAppleTVRemote: Bool

	    static func == (lhs: LogEntryView, rhs: LogEntryView) -> Bool {
			lhs.isLast == rhs.isLast && lhs.entry == rhs.entry && lhs.isPlayStation == rhs.isPlayStation && lhs.isNintendo == rhs.isNintendo && lhs.isSteamController == rhs.isSteamController && lhs.isAppleTVRemote == rhs.isAppleTVRemote
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                // Top: Button(s) + Type
                HStack(spacing: 4) {
                    ForEach(entry.buttons, id: \.self) { button in
							ButtonIconView(button: button, isDualSense: isPlayStation, isNintendo: isNintendo, isSteamController: isSteamController, isAppleTVRemote: isAppleTVRemote)
                    }

                    if entry.type != .singlePress {
                        Text(entry.type.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(badgeColor(for: entry.type).opacity(0.3)))
                            .foregroundColor(badgeColor(for: entry.type))
                            .overlay(
                                Capsule()
                                    .stroke(badgeColor(for: entry.type).opacity(0.4), lineWidth: 1)
                            )
                            .accessibilityLabel("Event type: \(entry.type.rawValue)")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)

                // Bottom: Action
                Text(entry.actionDescription)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

            }
            .padding(.horizontal, 8)

            // Separator arrow
            if !isLast {
                Image(systemName: "chevron.left") // Newest is at left/start
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.2))
                    .padding(.horizontal, 2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        // Use simple opacity transition - complex spring animations block input handling
        .transition(.opacity)
    }

    private var accessibilityDescription: String {
			let buttonNames = entry.buttons.map { $0.displayName(forDualSense: isPlayStation, forNintendo: isNintendo, forAppleTVRemote: isAppleTVRemote) }.joined(separator: " plus ")
        let typeDescription = entry.type == .singlePress ? "" : ", \(entry.type.rawValue)"
        return "\(buttonNames)\(typeDescription): \(entry.actionDescription)"
    }

    private func badgeColor(for type: InputEventType) -> Color {
        switch type {
        case .singlePress: return .secondary
        case .doubleTap: return .orange
        case .longPress: return .purple
        case .chord: return .blue
        case .sequence: return .cyan
        case .webhookSuccess: return .green
        case .webhookFailure: return .red
        case .gesture: return .teal
        }
    }
}
