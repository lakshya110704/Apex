import SwiftUI
import SwiftData

struct AchievementsView: View {
    @Query private var achievements: [Achievement]

    private var unlocked: [Achievement] { achievements.filter(\.isUnlocked) }
    private var locked: [Achievement]   { achievements.filter { !$0.isUnlocked } }

    var body: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Summary
                        HStack {
                            StatPill(
                                label: "Unlocked",
                                value: "\(unlocked.count)/\(achievements.count)",
                                color: ApexColor.warning
                            )
                            StatPill(
                                label: "XP Earned",
                                value: "\(unlocked.reduce(0) { $0 + $1.xpReward })",
                                color: ApexColor.success
                            )
                        }
                        .padding(.horizontal)

                        // Unlocked
                        if !unlocked.isEmpty {
                            achievementSection(title: "Unlocked", items: unlocked, isUnlocked: true)
                                .padding(.horizontal)
                        }

                        // Locked
                        achievementSection(title: "Locked", items: locked, isUnlocked: false)
                            .padding(.horizontal)

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Achievements")
        }
    }

    private func achievementSection(title: String, items: [Achievement], isUnlocked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .apexLabel()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(items) { achievement in
                    achievementCard(achievement, isUnlocked: isUnlocked)
                }
            }
        }
    }

    private func achievementCard(_ achievement: Achievement, isUnlocked: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? ApexColor.warning.opacity(0.2) : ApexColor.cardBg2)
                    .frame(width: 56, height: 56)
                Image(systemName: achievement.iconName)
                    .font(.title2)
                    .foregroundStyle(isUnlocked ? ApexColor.warning : ApexColor.textSecondary)
            }

            Text(achievement.name)
                .font(.caption.bold())
                .foregroundStyle(isUnlocked ? ApexColor.textPrimary : ApexColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(isUnlocked ? "+\(achievement.xpReward) XP" : achievement.achievementDescription)
                .font(.caption2)
                .foregroundStyle(isUnlocked ? ApexColor.warning : ApexColor.textSecondary.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if isUnlocked, let date = achievement.dateUnlocked {
                Text(date.dayAndMonth)
                    .font(.caption2)
                    .foregroundStyle(ApexColor.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(isUnlocked ? ApexColor.warning.opacity(0.05) : ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isUnlocked ? ApexColor.warning.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .opacity(isUnlocked ? 1.0 : 0.5)
    }
}
