import SwiftUI

/// Confirmation sheet shown before any external profile (community / file /
/// URL / StreamDeck) gets installed when it carries shell commands or
/// scripts. The user must explicitly approve the listed code before the
/// profile is added to ProfileManager.
///
/// Replaces the old `validateShellCommand` blocklist, which was bypassable
/// by any motivated attacker (process substitution, eval, IFS=, etc.) and
/// gave a false sense of safety. Real protection is informed consent at the
/// import boundary.
struct ProfileImportSafetySheet: View {
    let profileName: String
    let report: ProfileImportSafetyReport
    let onApprove: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 540, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 26))
            VStack(alignment: .leading, spacing: 4) {
                Text("This profile runs code on your Mac")
                    .font(.headline)
                Text("\"\(profileName)\" contains \(summaryLine).")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private var summaryLine: String {
        var parts: [String] = []
        if !report.shellCommands.isEmpty {
            parts.append("\(report.shellCommands.count) shell command\(report.shellCommands.count == 1 ? "" : "s")")
        }
        if !report.scripts.isEmpty {
            parts.append("\(report.scripts.count) script\(report.scripts.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " and ")
    }

    // MARK: - Body content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !report.shellCommands.isEmpty {
                    section(title: "Shell commands") {
                        ForEach(report.shellCommands) { item in
                            shellCommandRow(item)
                        }
                    }
                }
                if !report.scripts.isEmpty {
                    section(title: "Scripts") {
                        ForEach(report.scripts) { item in
                            scriptRow(item)
                        }
                    }
                }
                Text("These run with your full user permissions when triggered. Only import if you trust the source.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func shellCommandRow(_ item: ProfileImportSafetyReport.DiscoveredShellCommand) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(item.context)
                    .font(.system(size: 11, weight: .medium))
                if item.inTerminal {
                    Text("Terminal")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.25))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                }
            }
            Text(item.command)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func scriptRow(_ item: ProfileImportSafetyReport.DiscoveredScript) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            Text(item.name)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text("\(item.lineCount) line\(item.lineCount == 1 ? "" : "s") of JavaScript")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Import Anyway") {
                onApprove()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
}
