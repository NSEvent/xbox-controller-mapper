import SwiftUI

/// Stats dashboard tab showing usage statistics and controller personality
struct StatsView: View {
    @EnvironmentObject var usageStatsService: UsageStatsService
    @EnvironmentObject var controllerService: ControllerService
    @State private var showingWrappedSheet = false

    private var stats: UsageStats { usageStatsService.stats }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Personality Card
                personalitySection

                // Key Metrics
                metricsGrid

                // Top Buttons
                if !stats.topButtons.isEmpty {
                    topButtonsSection
                }

                // Action Breakdown
                if !stats.actionTypeCounts.isEmpty {
                    actionBreakdownSection
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingWrappedSheet) {
            WrappedCardSheet()
        }
    }

    // MARK: - Personality Section

    private var personalitySection: some View {
        VStack(spacing: 16) {
            let personality = stats.personality

            Text(personality.emoji)
                .font(.system(size: 48))

            Text(personality.title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(personality.tagline)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button {
                showingWrappedSheet = true
            } label: {
                Label("Share Wrapped", systemImage: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(personality.gradientColors.first ?? .blue)
            .disabled(stats.totalPresses < 10)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            metricCard(title: "Total Presses", value: formatNumber(stats.totalPresses), icon: "hand.tap")
            metricCard(title: "Sessions", value: "\(stats.totalSessions)", icon: "play.circle")
            metricCard(title: "Streak", value: "\(stats.currentStreakDays)d", icon: "flame")
            metricCard(title: "Best Streak", value: "\(stats.longestStreakDays)d", icon: "trophy")
        }
    }

    private func metricCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Top Buttons

    private var topButtonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOP BUTTONS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            let top = Array(stats.topButtons.prefix(5))
            let maxCount = top.first?.count ?? 1

            ForEach(top, id: \.button) { item in
                HStack(spacing: 12) {
                    Text(item.button.displayName(forDualSense: controllerService.threadSafeIsDualSense))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 100, alignment: .leading)

                    GeometryReader { geo in
                        let fraction = CGFloat(item.count) / CGFloat(maxCount)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: stats.personality.gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * fraction)
                    }
                    .frame(height: 20)

                    Text(formatNumber(item.count))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
                .frame(height: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Action Breakdown

    private var actionBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTION TYPES")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            let totalActions = stats.actionTypeCounts.values.reduce(0, +)
            let sorted = stats.actionTypeCounts.sorted { $0.value > $1.value }

            ForEach(sorted, id: \.key) { key, count in
                HStack {
                    Text(key)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    Spacer()

                    if totalActions > 0 {
                        Text("\(Int(Double(count) / Double(totalActions) * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Text(formatNumber(count))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Helpers

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}
