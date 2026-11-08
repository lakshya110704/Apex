import SwiftUI
import SwiftData

struct ApexProgressView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var workouts: [WorkoutSession]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query private var achievements: [Achievement]

    private var profile: UserProfile? { profiles.first }
    private var unlockedCount: Int { achievements.filter(\.isUnlocked).count }

    var body: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        levelCard
                            .padding(.horizontal)

                        consistencyCard
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            streakTile(title: "Workout streak", icon: "flame.fill", value: profile?.workoutStreak ?? 0, color: ApexColor.danger)
                            streakTile(title: "Meal streak", icon: "leaf.fill", value: profile?.mealStreak ?? 0, color: ApexColor.success)
                            NavigationLink(destination: MuscleHeatmapView()) {
                                ApexTile(title: "Muscles", systemImage: "figure.arms.open") {
                                    Text("See which muscles you have worked")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ApexColor.textPrimary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .buttonStyle(PressableStyle())
                            NavigationLink(destination: AchievementsView()) {
                                ApexTile(title: "Achievements", systemImage: "trophy.fill") {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(unlockedCount)/\(achievements.count)")
                                            .apexDisplay(36)
                                            .foregroundStyle(ApexColor.textPrimary)
                                        Text("unlocked")
                                            .font(.caption)
                                            .foregroundStyle(ApexColor.textSecondary)
                                    }
                                }
                            }
                            .buttonStyle(PressableStyle())
                        }
                        .padding(.horizontal)

                        statsSection
                            .padding(.horizontal)

                        workoutBreakdownSection
                            .padding(.horizontal)

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Progress")
        }
    }

    // MARK: - Level Card

    private var levelCard: some View {
        let level = profile?.level ?? 1
        let xp = profile?.xpPoints ?? 0
        let progress = profile?.levelProgress ?? 0
        let toNext = profile?.xpForNextLevel ?? 0

        return VStack(spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LEVEL")
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.textSecondary)
                        .tracking(2)
                    Text("\(level)")
                        .apexDisplay(64)
                        .foregroundStyle(ApexColor.accent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(xp.formatted()) XP")
                        .font(.title2.bold())
                        .foregroundStyle(ApexColor.textPrimary)
                    if toNext > 0 {
                        Text("\(toNext) XP to Level \(level + 1)")
                            .font(.caption)
                            .foregroundStyle(ApexColor.textSecondary)
                    } else {
                        Text("MAX LEVEL")
                            .font(.caption.bold())
                            .foregroundStyle(ApexColor.warning)
                    }
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ApexColor.cardBg2)
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            colors: [ApexColor.accent, ApexColor.accentCyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * progress, height: 12)
                        .animation(.easeInOut(duration: 1.0), value: progress)
                }
            }
            .frame(height: 12)
        }
        .apexCard()
    }

    // MARK: - Consistency

    private var consistencyCard: some View {
        let days = ActiveDays.lastDays(14, dates: workouts.map(\.date) + meals.map(\.date))
        let activeCount = days.filter(\.active).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last 14 days").apexLabel()
                Spacer()
                Text("\(activeCount) active")
                    .font(.caption.bold())
                    .foregroundStyle(ApexColor.textSecondary)
            }
            HStack(spacing: 5) {
                ForEach(days, id: \.day) { item in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(item.active ? ApexColor.accent : ApexColor.cardBg2)
                        .frame(height: 30)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(item.day.isToday ? ApexColor.textPrimary.opacity(0.6) : Color.clear, lineWidth: 1.5)
                        )
                        .accessibilityLabel("\(item.day.mediumDate), \(item.active ? "active" : "nothing logged")")
                }
            }
            Text("A day counts when you log a workout or a meal.")
                .font(.caption2)
                .foregroundStyle(ApexColor.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func streakTile(title: String, icon: String, value: Int, color: Color) -> some View {
        ApexTile(title: title, systemImage: icon) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .apexDisplay(44)
                    .foregroundStyle(value > 0 ? color : ApexColor.textSecondary)
                Text(value == 1 ? "day" : "days")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            }
        }
    }

    // MARK: - All-Time Stats

    private var statsSection: some View {
        ApexSectionCard(title: "All-Time Stats", systemImage: "chart.bar.fill", accentColor: ApexColor.accentCyan) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statItem(label: "Workouts",  value: "\(workouts.count)",         color: ApexColor.accent)
                statItem(label: "Tennis",    value: "\(tennisCount)",            color: ApexColor.tennis)
                statItem(label: "Gym",       value: "\(gymCount)",               color: ApexColor.accent)
                statItem(label: "Meals",     value: "\(meals.count)",            color: ApexColor.success)
                statItem(label: "Calories",  value: "\(totalCaloriesAll)k",      color: ApexColor.danger)
                statItem(label: "Hrs Logged",value: "\(totalHoursLogged)",       color: ApexColor.accentCyan)
            }
        }
    }

    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(ApexColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(ApexColor.cardBg2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Workout Breakdown

    private var workoutBreakdownSection: some View {
        ApexSectionCard(title: "Workout Types", systemImage: "chart.pie.fill", accentColor: ApexColor.accent) {
            VStack(spacing: 10) {
                typeBar(type: .tennis, count: tennisCount, total: workouts.count, color: ApexColor.tennis)
                typeBar(type: .gym,    count: gymCount,    total: workouts.count, color: ApexColor.accent)
                typeBar(type: .run,    count: runCount,    total: workouts.count, color: ApexColor.accentCyan)
            }
        }
    }

    private func typeBar(type: WorkoutType, count: Int, total: Int, color: Color) -> some View {
        let fraction = total > 0 ? Double(count) / Double(total) : 0
        return HStack(spacing: 10) {
            Image(systemName: type.systemImage)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(type.rawValue)
                .font(.caption.bold())
                .foregroundStyle(ApexColor.textSecondary)
                .frame(width: 52, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(ApexColor.cardBg2).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4).fill(color).frame(width: geo.size.width * fraction, height: 8)
                }
            }
            .frame(height: 8)
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(ApexColor.textPrimary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    // MARK: - Computed

    private var tennisCount: Int { workouts.filter { $0.type == .tennis }.count }
    private var gymCount: Int    { workouts.filter { $0.type == .gym }.count }
    private var runCount: Int    { workouts.filter { $0.type == .run }.count }
    private var totalCaloriesAll: Int { workouts.reduce(0) { $0 + $1.caloriesBurned } / 1000 }
    private var totalHoursLogged: Int { workouts.reduce(0) { $0 + $1.durationMinutes } / 60 }
}
