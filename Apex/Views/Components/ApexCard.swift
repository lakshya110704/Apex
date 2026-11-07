import SwiftUI

// MARK: - Reusable card containers

struct ApexSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(ApexColor.accent)
                Text(title).apexLabel()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .apexCard()
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(ApexColor.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ApexColor.cardBg2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - XP Badge

struct XPBadge: View {
    let amount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
            Text("+\(amount) XP")
                .font(.caption.bold())
        }
        .foregroundStyle(ApexColor.warning)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ApexColor.warning.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Circular Progress Ring

struct RingView: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: progress)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Achievement Toast

struct AchievementToast: View {
    let achievement: Achievement
    @Binding var isShowing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.iconName)
                .font(.title2)
                .foregroundStyle(ApexColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Achievement Unlocked!")
                    .font(.caption.bold())
                    .foregroundStyle(ApexColor.warning)
                Text(achievement.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(ApexColor.textPrimary)
                Text("+\(achievement.xpReward) XP")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            }
            Spacer()
            Button { isShowing = false } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            }
        }
        .padding()
        .background(ApexColor.cardBg2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ApexColor.warning.opacity(0.4), lineWidth: 1))
        .shadow(color: ApexColor.warning.opacity(0.2), radius: 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(ApexColor.textSecondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(ApexColor.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(ApexColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}
