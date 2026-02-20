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
        .frame(width: 620, height: 480)
        .onAppear {
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

    // MARK: - Recommendation Row

    private func recommendationRow(_ rec: BindingRecommendation) -> some View {
        let isSelected = selectedIds.contains(rec.id)

        return HStack(spacing: 10) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .onTapGesture { toggleSelection(rec.id) }

            // Type icon
            typeIcon(for: rec.type)

            // Recommendation content
            VStack(alignment: .leading, spacing: 6) {
                // Title line
                titleView(for: rec)

                // Before → After with button icons
                beforeAfterView(for: rec)
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
        .onTapGesture { toggleSelection(rec.id) }
    }

    @ViewBuilder
    private func titleView(for rec: BindingRecommendation) -> some View {
        switch rec.type {
        case .swap(let b1, let b2):
            Text("Swap \(buttonName(b1)) and \(buttonName(b2)) — most-used action is on a harder button")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)

        case .promoteToChord(let fromButton, let fromType, let toChordButtons, _, _):
            let typeLabel = fromType == .longHold ? "long hold" : "double tap"
            let chordLabel = chordButtonNames(toChordButtons)
            Text("Promote \(buttonName(fromButton)) \(typeLabel) to \(chordLabel) chord — faster to execute")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)

        case .demoteToLongHold(let button, _, _):
            Text("Move \(buttonName(button)) to long hold — rarely used, frees the single-press slot")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func beforeAfterView(for rec: BindingRecommendation) -> some View {
        switch rec.type {
        case .swap(let b1, let b2):
            HStack(spacing: 6) {
                // Before
                buttonIcon(b1)
                Text(rec.actionDescription1)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("/")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
                buttonIcon(b2)
                Text(rec.actionDescription2)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)

                // After (swapped)
                buttonIcon(b1)
                Text(rec.actionDescription2)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("/")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
                buttonIcon(b2)
                Text(rec.actionDescription1)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

        case .promoteToChord(let fromButton, let fromType, let toChordButtons, _, _):
            HStack(spacing: 6) {
                buttonIcon(fromButton)
                let typeLabel = fromType == .longHold ? "hold" : "2x"
                Text("\(typeLabel): \(rec.actionDescription1)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)

                chordButtonIcons(toChordButtons)
                Text(rec.actionDescription1)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

        case .demoteToLongHold(let button, _, _):
            HStack(spacing: 6) {
                buttonIcon(button)
                Text("press: \(rec.actionDescription1)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)

                buttonIcon(button)
                Text("long hold: \(rec.actionDescription1)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Button Display Helpers

    private func buttonName(_ button: ControllerButton) -> String {
        button.displayName(forDualSense: isDualSense)
    }

    private func chordButtonNames(_ buttons: Set<ControllerButton>) -> String {
        buttons.sorted { $0.category.chordDisplayOrder < $1.category.chordDisplayOrder }
            .map { $0.shortLabel(forDualSense: isDualSense) }
            .joined(separator: "+")
    }

    private func buttonIcon(_ button: ControllerButton) -> some View {
        ButtonIconView(button: button, isDualSense: isDualSense)
            .scaleEffect(0.7)
            .frame(width: 22, height: 22)
    }

    @ViewBuilder
    private func chordButtonIcons(_ buttons: Set<ControllerButton>) -> some View {
        let sorted = buttons.sorted { $0.category.chordDisplayOrder < $1.category.chordDisplayOrder }
        HStack(spacing: 2) {
            ForEach(sorted, id: \.self) { button in
                buttonIcon(button)
            }
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
