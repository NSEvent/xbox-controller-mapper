import SwiftUI

struct RecommendationsSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss

    let analysisResult: BindingAnalysisResult

    @State private var selectedIds: Set<UUID> = []
    @State private var applied = false

    private var isDualSense: Bool { controllerService.threadSafeIsPlayStation }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 600, height: 480)
        .onAppear {
            // Pre-select all recommendations
            selectedIds = Set(analysisResult.recommendations.map(\.id))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Binding Optimization")
                    .font(.headline)

                Text("\(analysisResult.recommendations.count) recommendation\(analysisResult.recommendations.count == 1 ? "" : "s") based on \(analysisResult.totalActions) tracked actions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("\(Int(analysisResult.efficiencyScore * 100))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(efficiencyColor)

                Text("Efficiency")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if analysisResult.recommendations.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    Text("Your bindings are already well-optimized!")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(analysisResult.recommendations) { rec in
                            recommendationRow(rec)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func recommendationRow(_ rec: BindingRecommendation) -> some View {
        let isSelected = selectedIds.contains(rec.id)

        return HStack(spacing: 12) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .onTapGesture {
                    toggleSelection(rec.id)
                }

            // Type icon
            typeIcon(for: rec.type)

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text(rec.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(rec.beforeDescription)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    Text(rec.afterDescription)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Priority indicator
            Circle()
                .fill(priorityColor(rec.priority))
                .frame(width: 8, height: 8)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(rec.id)
        }
    }

    @ViewBuilder
    private func typeIcon(for type: RecommendationType) -> some View {
        switch type {
        case .swap:
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 14))
                .foregroundColor(.orange)
                .frame(width: 24)
        case .promoteToChord:
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 14))
                .foregroundColor(.green)
                .frame(width: 24)
        case .demoteToLongHold:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14))
                .foregroundColor(.blue)
                .frame(width: 24)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(selectedIds.count == analysisResult.recommendations.count ? "Deselect All" : "Select All") {
                if selectedIds.count == analysisResult.recommendations.count {
                    selectedIds.removeAll()
                } else {
                    selectedIds = Set(analysisResult.recommendations.map(\.id))
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.accentColor)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            if applied {
                Label("Applied!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.green)
            } else {
                Button("Apply Selected (\(selectedIds.count))") {
                    applySelected()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIds.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func toggleSelection(_ id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func applySelected() {
        let selected = analysisResult.recommendations.filter { selectedIds.contains($0.id) }
        profileManager.applyRecommendations(selected)
        applied = true

        // Auto-dismiss after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
        }
    }

    private var efficiencyColor: Color {
        let score = analysisResult.efficiencyScore
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .yellow }
        return .orange
    }

    private func priorityColor(_ priority: Double) -> Color {
        if priority >= 20 { return .red }
        if priority >= 10 { return .orange }
        return .yellow
    }
}
