import SwiftUI

/// Self-contained 400x560 shareable card with gradient background
struct WrappedCardView: View {
    let stats: UsageStats
    let isDualSense: Bool

    private var personality: ControllerPersonality { stats.personality }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 36)

            // Personality
            Text(personality.emoji)
                .font(.system(size: 48))

            Text(personality.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 6)

            Text(personality.tagline)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .padding(.top, 2)

            Spacer()
                .frame(height: 24)

            // Stats Row 1: Presses split
            HStack(spacing: 16) {
                statPill(value: formatNumber(stats.keyPresses), label: "Keys")
                statPill(value: formatNumber(stats.mouseClicks), label: "Clicks")
                statPill(value: "\(stats.totalSessions)", label: "Sessions")
            }

            Spacer()
                .frame(height: 12)

            // Stats Row 2: Distance + streak
            HStack(spacing: 16) {
                if stats.totalMousePixels > 0 {
                    statPill(value: UsageStats.formatDistance(stats.totalMousePixels), label: "Mouse")
                }
                if stats.scrollPixels > 0 {
                    statPill(value: UsageStats.formatDistance(stats.scrollPixels), label: "Scrolled")
                }
                statPill(value: "\(stats.longestStreakDays)d", label: "Streak")
            }

            Spacer()
                .frame(height: 20)

            // Top 3 Buttons
            if stats.topButtons.count >= 3 {
                VStack(spacing: 8) {
                    Text("TOP BUTTONS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .tracking(1.5)

                    ForEach(Array(stats.topButtons.prefix(3).enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 10) {
                            Text("\(index + 1).")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 22)

                            ButtonIconView(button: item.button, isDualSense: isDualSense)

                            Text(item.button.displayName(forDualSense: isDualSense))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)

                            Spacer()

                            Text(formatNumber(item.count))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.2))
                        )
                        .padding(.horizontal, 20)
                    }
                }
            }

            Spacer()

            // Branding
            Text("ControllerKeys")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
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
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.25))
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
