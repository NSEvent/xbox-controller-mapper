import SwiftUI

// MARK: - Input Settings View

struct InputSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager

    private var latencyMode: InputLatencyMode {
        profileManager.activeProfile?.inputLatencyMode ?? .standard
    }

    var body: some View {
        Form {
            Section("Button Latency") {
                Picker("Mode", selection: Binding(
                    get: { latencyMode },
                    set: { updateLatencyMode($0) }
                )) {
                    ForEach(InputLatencyMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                ActiveLatencyModeCallout(mode: latencyMode)
            }

            Section("Mode Comparison") {
                LatencyComparisonTable()
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func updateLatencyMode(_ mode: InputLatencyMode) {
        guard let profile = profileManager.activeProfile else { return }
        profileManager.setInputLatencyMode(mode, for: profile)
    }
}

private struct ActiveLatencyModeCallout: View {
    let mode: InputLatencyMode

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: mode == .realtime ? "bolt.fill" : "timer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(mode == .realtime ? .orange : .blue)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .realtime ? "Realtime is enabled for this profile." : "Standard timing is enabled for this profile.")
                    .font(.callout.weight(.medium))

                Text(mode == .realtime ? realtimeSummary : standardSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var standardSummary: String {
        "ControllerKeys waits through the chord window before firing a single-button action, so advanced gestures have full priority. Default window: \(chordWindowDescription)."
    }

    private var realtimeSummary: String {
        "Simple key mappings fire on button press and release when you let go. Advanced mappings keep standard timing."
    }

    private var chordWindowDescription: String {
        "\(Int(Config.chordDetectionWindow * 1000)) ms"
    }
}

private struct LatencyComparisonTable: View {
    private let rows = [
        LatencyComparisonRowData(
            label: "Press timing",
            standard: "Waits through the chord window before a single-button action. Default: \(Int(Config.chordDetectionWindow * 1000)) ms.",
            realtime: "Fires eligible key mappings immediately on button press."
        ),
        LatencyComparisonRowData(
            label: "Eligible actions",
            standard: "All mapping types.",
            realtime: "Plain one-button key mappings only."
        ),
        LatencyComparisonRowData(
            label: "Key behavior",
            standard: "Normal tap handling after timing checks.",
            realtime: "Key-down on press, key-up when you let go."
        ),
        LatencyComparisonRowData(
            label: "Advanced mappings",
            standard: "Chords, double-taps, long-holds, repeat-while-held mappings, macros, scripts, and system actions.",
            realtime: "Advanced mappings automatically stay on standard timing."
        ),
        LatencyComparisonRowData(
            label: "Best for",
            standard: "Profiles that depend on chords or timing gestures.",
            realtime: "Anki answers, Space, arrow keys, and simple game controls."
        ),
        LatencyComparisonRowData(
            label: "Tradeoff",
            standard: "More gesture flexibility, slightly slower simple taps.",
            realtime: "Fastest simple keys, less wait-and-see behavior."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Spacer()
                    .frame(width: 106)

                LatencyComparisonHeader(
                    title: "Standard",
                    icon: "timer",
                    color: .blue
                )

                LatencyComparisonHeader(
                    title: "Realtime",
                    icon: "bolt.fill",
                    color: .orange
                )
            }
            .padding(.bottom, 6)

            ForEach(rows) { row in
                Divider()

                HStack(alignment: .top, spacing: 12) {
                    Text(row.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 106, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    LatencyComparisonCell(text: row.standard)
                    LatencyComparisonCell(text: row.realtime)
                }
                .padding(.vertical, 7)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LatencyComparisonHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)

            Text(title)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LatencyComparisonCell: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LatencyComparisonRowData: Identifiable {
    var id: String { label }
    let label: String
    let standard: String
    let realtime: String
}
