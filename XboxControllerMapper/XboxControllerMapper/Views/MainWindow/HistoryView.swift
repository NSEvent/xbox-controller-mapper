import SwiftUI

/// History tab — lists profile snapshots and lets the user restore one.
///
/// Snapshots are written automatically before destructive operations
/// (delete profile, import profile). Restoring captures the current state
/// as its own snapshot first, so restore is undoable.
struct HistoryView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var snapshots: [ProfileSnapshot] = []
    @State private var pendingRestore: ProfileSnapshot?
    @State private var lastRestoreError: String?

    var body: some View {
        Group {
            if snapshots.isEmpty {
                emptyState
            } else {
                snapshotList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { reload() }
        .alert(
            "Restore this snapshot?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            presenting: pendingRestore
        ) { snapshot in
            Button("Restore", role: .destructive) { perform(snapshot) }
            Button("Cancel", role: .cancel) {}
        } message: { snapshot in
            Text("\(snapshot.reason)\n\nYour current configuration will be saved as its own snapshot first, so you can undo this restore.")
        }
        .alert(
            "Restore failed",
            isPresented: Binding(
                get: { lastRestoreError != nil },
                set: { if !$0 { lastRestoreError = nil } }
            ),
            presenting: lastRestoreError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("No history yet")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
            Text("Snapshots are captured automatically before destructive\nactions like deleting or importing profiles.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var snapshotList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent snapshots are kept automatically. Restoring will overwrite your current configuration — but the current state is captured as a snapshot first, so the restore itself is undoable.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.bottom, 8)

                ForEach(snapshots) { snapshot in
                    HistoryRow(snapshot: snapshot) {
                        pendingRestore = snapshot
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func reload() {
        snapshots = profileManager.availableSnapshots()
    }

    private func perform(_ snapshot: ProfileSnapshot) {
        if profileManager.restoreSnapshot(snapshot) {
            reload()
        } else {
            lastRestoreError = "Could not restore snapshot from \(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened)). The snapshot file may be missing or corrupted."
        }
    }
}

private struct HistoryRow: View {
    let snapshot: ProfileSnapshot
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.reason)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
                Text(snapshot.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Button("Restore", action: onRestore)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
