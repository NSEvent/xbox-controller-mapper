import SwiftUI

/// Self-contained 400x560 shareable card with gradient background
struct WrappedCardView: View {
    let stats: UsageStats
    let isDualSense: Bool

    private var personality: ControllerPersonality { stats.personality }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 40)

            // Personality
            Text(personality.emoji)
                .font(.system(size: 56))

            Text(personality.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 8)

            Text(personality.tagline)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .padding(.top, 4)

            Spacer()
                .frame(height: 32)

            // Stats Grid
            HStack(spacing: 24) {
                statPill(value: formatNumber(stats.totalPresses), label: "Presses")
                statPill(value: "\(stats.totalSessions)", label: "Sessions")
                statPill(value: "\(stats.longestStreakDays)d", label: "Best Streak")
            }

            Spacer()
                .frame(height: 24)

            // Top 3 Buttons
            if stats.topButtons.count >= 3 {
                VStack(spacing: 8) {
                    Text("TOP BUTTONS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(1.5)

                    ForEach(Array(stats.topButtons.prefix(3).enumerated()), id: \.offset) { index, item in
                        HStack {
                            Text("\(index + 1).")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 24)

                            Text(item.button.displayName(forDualSense: isDualSense))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)

                            Spacer()

                            Text(formatNumber(item.count))
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 32)
                    }
                }
            }

            Spacer()

            // Branding
            Text("ControllerKeys")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 24)
        }
        .frame(width: 400, height: 560)
        .background(
            LinearGradient(
                colors: personality.gradientColors + [Color.black.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.15))
        )
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
