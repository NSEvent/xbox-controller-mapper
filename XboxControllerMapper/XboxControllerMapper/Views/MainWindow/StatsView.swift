import SwiftUI

/// Stats dashboard tab showing usage statistics and controller personality
struct StatsView: View {
    @EnvironmentObject var usageStatsService: UsageStatsService
    @EnvironmentObject var controllerService: ControllerService
    @State private var showingWrappedSheet = false

    private var stats: UsageStats { usageStatsService.stats }
    private var isDualSense: Bool { controllerService.threadSafeIsPlayStation }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Identity — the hero element, what makes people scroll
                personalitySection

                // 2. Most personal insight — visual, scannable, "what do I actually use?"
                if !stats.topButtons.isEmpty {
                    topButtonsSection
                }

                // 3. Headline numbers — compact summary after the visual bar chart
                metricsGrid

                // 4. What you did — direct physical output
                inputActionsSection

                // 5. What you automated — things the controller triggered for you
                automationActionsSection

                // 6. Fun novelty metric — visual break before denser data
                if stats.joystickMousePixels > 0 || stats.touchpadMousePixels > 0 || stats.scrollPixels > 0 {
                    distanceSection
                }

                // 7. Most technical breakdown — granular, for power users
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
            metricCard(title: "Total Presses", value: formatNumber(stats.totalPresses), icon: "hand.tap")
            metricCard(title: "Sessions", value: "\(stats.totalSessions)", icon: "play.circle")
            metricCard(title: "Streak", value: "\(stats.currentStreakDays)d", icon: "flame")
            metricCard(title: "Best Streak", value: "\(stats.longestStreakDays)d", icon: "trophy")
        }
    }

    // MARK: - Input Actions (physical output)

    private var inputActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INPUT \u{2192} OUTPUT")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                outputCard(title: "Key Presses", value: formatNumber(stats.keyPresses), icon: "keyboard", color: .blue)
                outputCard(title: "Mouse Clicks", value: formatNumber(stats.mouseClicks), icon: "computermouse", color: .green)
                outputCard(title: "Macros Run", value: formatNumber(stats.macrosExecuted), icon: "repeat", color: .purple)
                outputCard(title: "Steps Automated", value: formatNumber(stats.macroStepsAutomated), icon: "bolt", color: .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Automation Actions (things triggered for you)

    private var automationActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AUTOMATION")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                outputCard(title: "Apps Launched", value: formatNumber(stats.appsLaunched), icon: "app.badge", color: .pink)
                outputCard(title: "Links Opened", value: formatNumber(stats.linksOpened), icon: "link", color: .teal)
                outputCard(title: "Snippets Pasted", value: formatNumber(stats.textSnippetsRun), icon: "text.quote", color: .yellow)
                outputCard(title: "Terminals Popped", value: formatNumber(stats.terminalCommandsRun), icon: "terminal", color: .gray)
                outputCard(title: "Webhooks Run", value: formatNumber(stats.webhooksFired), icon: "network", color: .cyan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func outputCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08))
        )
    }

    // MARK: - Distance Section

    private var distanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DISTANCE TRAVELED")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                if stats.joystickMousePixels > 0 {
                    distanceCard(
                        title: "Joystick Mouse",
                        pixels: stats.joystickMousePixels,
                        icon: "l.joystick",
                        color: .orange
                    )
                }
                if stats.touchpadMousePixels > 0 {
                    distanceCard(
                        title: "Touchpad Mouse",
                        pixels: stats.touchpadMousePixels,
                        icon: "hand.point.up",
                        color: .mint
                    )
                }
                if stats.scrollPixels > 0 {
                    distanceCard(
                        title: "Scroll Distance",
                        pixels: stats.scrollPixels,
                        icon: "arrow.up.and.down",
                        color: .indigo
                    )
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

    private func distanceCard(title: String, pixels: Double, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)

            Text(UsageStats.formatDistance(pixels))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08))
        )
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
                    ButtonIconView(button: item.button, isDualSense: isDualSense)

                    Text(item.button.displayName(forDualSense: isDualSense))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 90, alignment: .leading)

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
                .frame(height: 28)
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
            Text("INPUT TYPES")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            let totalActions = stats.actionTypeCounts.values.reduce(0, +)
            let sorted = stats.actionTypeCounts.sorted { $0.value > $1.value }

            ForEach(sorted, id: \.key) { key, count in
                HStack {
                    Text(actionTypeDisplayName(key))
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

    private func actionTypeDisplayName(_ rawValue: String) -> String {
        switch rawValue {
        case "Press": return "Single Press"
        case "Double Tap": return "Double Tap"
        case "Long Press": return "Long Hold"
        case "Chord": return "Chord"
        case "Webhook \u{2713}": return "Webhook Success"
        case "Webhook \u{2717}": return "Webhook Failure"
        default: return rawValue
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}
