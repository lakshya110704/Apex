import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date, order: .reverse) private var workouts: [WorkoutSession]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<DailyPlan> { _ in true }, sort: \DailyPlan.date, order: .reverse)
    private var plans: [DailyPlan]
    @Query(sort: \MorningCheckIn.date, order: .reverse) private var checkIns: [MorningCheckIn]

    var healthKit: HealthKitService
    var claude: ClaudeService
    var gamification: GamificationService
    var calendar: CalendarService
    var github: GitHubService
    var focusTimer: FocusTimerService

    @State private var isGeneratingPlan = false
    @State private var planError: String?
    @State private var showAchievement = false
    @State private var toastAchievement: Achievement?
    @State private var xpFloatOffset: CGFloat = 0
    @State private var xpFloatOpacity: Double = 0

    private var profile: UserProfile? { profiles.first }
    private var todayPlan: DailyPlan? { plans.first(where: { $0.date.isToday }) }
    private var todayCheckIn: MorningCheckIn? { checkIns.first(where: { $0.date.isToday }) }
    private var todayWorkouts: [WorkoutSession] { workouts.filter { $0.date.isToday } }
    private var todayMeals: [MealEntry] { meals.filter { $0.date.isToday } }
    private var totalCaloriesToday: Int { todayMeals.reduce(0) { $0 + $1.estimatedCalories } }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ApexColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Header
                        headerSection
                            .padding(.horizontal)

                        if let notice = healthKit.healthNotice {
                            Text(notice)
                                .font(.caption)
                                .foregroundStyle(ApexColor.warning)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(ApexColor.warning.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                        }

                        // Today's Plan (top of the scroll — it's your day at a glance)
                        dailyPlanSection
                            .padding(.horizontal)

                        // Activity Rings
                        ApexSectionCard(title: "Activity", systemImage: "circle.circle.fill", accentColor: ApexColor.danger) {
                            ActivityRingsView(
                                moveProgress: healthKit.moveProgress,
                                exerciseProgress: healthKit.exerciseProgress,
                                standProgress: healthKit.standProgress,
                                moveCalories: healthKit.todayActiveCalories,
                                exerciseMinutes: healthKit.todayExerciseMinutes,
                                standHours: healthKit.todayStandHours
                            )
                        }
                        .padding(.horizontal)

                        // Recovery Stats
                        recoveryStatsSection
                            .padding(.horizontal)

                        // Focus Timer
                        FocusTimerCard(focusTimer: focusTimer)
                            .padding(.horizontal)

                        // Calendar
                        if !calendar.todayEvents.isEmpty {
                            calendarSection
                                .padding(.horizontal)
                        }

                        // Today's Workouts
                        if !todayWorkouts.isEmpty {
                            todayWorkoutsSection
                                .padding(.horizontal)
                        }

                        // Today's Nutrition
                        if !todayMeals.isEmpty {
                            nutritionSummarySection
                                .padding(.horizontal)
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 8)
                }

                // Achievement Toast
                if showAchievement, let achievement = toastAchievement {
                    VStack {
                        AchievementToast(achievement: achievement, isShowing: $showAchievement)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .zIndex(10)
                }

                // XP Float
                if xpFloatOpacity > 0 {
                    VStack {
                        Spacer()
                        Text("+\(gamification.xpAnimationAmount) XP")
                            .font(.title2.bold())
                            .foregroundStyle(ApexColor.warning)
                            .offset(y: xpFloatOffset)
                            .opacity(xpFloatOpacity)
                        Spacer()
                    }
                    .zIndex(9)
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .task {
                await healthKit.requestAuthorization()
                await calendar.requestAuthorization()
                if let username = profile?.githubUsername, !username.isEmpty {
                    await github.fetchActivity(username: username)
                }
                checkAchievementToast()
            }
            .onChange(of: gamification.xpAnimationAmount) { _, _ in
                animateXP()
            }
            .onChange(of: gamification.pendingAchievements.count) { _, count in
                if count > 0 { checkAchievementToast() }
            }
            .refreshable {
                await healthKit.fetchAllTodayData()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView(claude: claude, gamification: gamification)) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(ApexColor.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.title3)
                    .foregroundStyle(ApexColor.textSecondary)
                Text(profile?.name.isEmpty == false ? profile!.name : "Athlete")
                    .font(.largeTitle.bold())
                    .foregroundStyle(ApexColor.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Lvl \(profile?.level ?? 1)")
                    .font(.headline.bold())
                    .foregroundStyle(ApexColor.accent)
                Text("\(profile?.xpPoints ?? 0) XP")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            }
        }
    }

    private var recoveryStatsSection: some View {
        ApexSectionCard(title: "Recovery", systemImage: "waveform.path.ecg", accentColor: ApexColor.accentCyan) {
            HStack(spacing: 12) {
                StatPill(
                    label: "Sleep",
                    value: String(format: "%.1fh", healthKit.sleepHoursLast),
                    color: sleepColor
                )
                StatPill(
                    label: "RHR",
                    value: "\(Int(healthKit.restingHeartRate)) bpm",
                    color: ApexColor.success
                )
                StatPill(
                    label: "HRV",
                    value: "\(Int(healthKit.hrv)) ms",
                    color: hrvColor
                )
                StatPill(
                    label: "Steps",
                    value: "\(healthKit.todaySteps.formatted())",
                    color: ApexColor.accentCyan
                )
            }
        }
    }

    private var dailyPlanSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Today's Plan", systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ApexColor.accent)
                Spacer()
                let aiReady = claude.isLocalAIAvailable || !claude.apiKey.isEmpty
                Button {
                    Task { await generatePlan() }
                } label: {
                    Label(todayPlan == nil ? "Generate" : "Refresh", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(aiReady ? ApexColor.accent : ApexColor.textSecondary)
                }
                .disabled(isGeneratingPlan || !aiReady)
            }
            .padding(16)

            if let error = planError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(ApexColor.warning)
                    .padding([.horizontal, .bottom], 16)
            } else if isGeneratingPlan {
                HStack(spacing: 12) {
                    ProgressView().tint(ApexColor.accent)
                    Text("Building your day...")
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.textSecondary)
                }
                .padding([.horizontal, .bottom], 16)
            } else if let plan = todayPlan {
                let blocks = parsePlanBlocks(from: plan.planText)
                if blocks.isEmpty {
                    Text(plan.planText)
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding([.horizontal, .bottom], 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                            planBlockRow(block, isLast: index == blocks.count - 1)
                        }
                    }
                    .padding(.bottom, 8)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 32))
                        .foregroundStyle(ApexColor.accent.opacity(0.4))
                    let aiReady = claude.isLocalAIAvailable || claude.apiKey.isNotEmpty
                    Text(aiReady
                         ? "Generate a personalized plan for today."
                         : "Add your Google AI key in Settings, or connect Ollama to enable AI planning.")
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.textSecondary)
                        .multilineTextAlignment(.center)
                    if aiReady {
                        Button { Task { await generatePlan() } } label: {
                            Text("Generate Plan")
                                .font(.subheadline.bold())
                                .foregroundStyle(ApexColor.background)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(ApexColor.accent)
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func planBlockRow(_ block: PlanBlock, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Timeline column
            VStack(spacing: 0) {
                Circle()
                    .fill(block.accentColor)
                    .frame(width: 7, height: 7)
                    .padding(.top, 7)
                if !isLast {
                    Rectangle()
                        .fill(ApexColor.cardBg2)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 16)
            .padding(.leading, 16)

            // Time
            Text(block.time)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ApexColor.textSecondary)
                .frame(width: 42, alignment: .leading)
                .padding(.top, 4)
                .padding(.leading, 8)

            // Icon + Activity
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: block.iconName)
                    .font(.caption)
                    .foregroundStyle(block.accentColor)
                    .frame(width: 14)
                    .padding(.top, 5)
                Text(block.activity)
                    .font(.subheadline)
                    .foregroundStyle(ApexColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.bottom, isLast ? 8 : 0)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 36)
    }

    private struct PlanBlock: Identifiable {
        let id = UUID()
        let time: String
        let category: String
        let activity: String

        var iconName: String {
            switch category {
            case "morning":   return "sunrise.fill"
            case "workout":   return "dumbbell.fill"
            case "nutrition": return "fork.knife"
            case "focus":     return "brain.head.profile"
            case "evening":   return "moon.stars.fill"
            default:          return "circle.fill"
            }
        }

        var accentColor: Color {
            switch category {
            case "morning":   return .orange
            case "workout":   return ApexColor.accent
            case "nutrition": return ApexColor.success
            case "focus":     return ApexColor.accentCyan
            case "evening":   return .purple
            default:          return ApexColor.textSecondary
            }
        }
    }

    private func parsePlanBlocks(from text: String) -> [PlanBlock] {
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strategy 1: pipe format — "HH:MM | category | activity" (Ollama output)
        let pipeBlocks = parsePipeFormat(stripped)
        if !pipeBlocks.isEmpty { return pipeBlocks }

        // Strategy 2: JSON array — direct or with extraction (Gemini output)
        for candidate in jsonCandidates(from: stripped) {
            if let data = candidate.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let blocks = makePlanBlocks(from: array)
                if !blocks.isEmpty { return blocks }
            }
        }
        return []
    }

    // Parse "HH:MM | category | activity" lines
    private func parsePipeFormat(_ text: String) -> [PlanBlock] {
        text.components(separatedBy: "\n")
            .compactMap { line -> PlanBlock? in
                let parts = line.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 3,
                      parts[0].contains(":"),
                      !parts[2].isEmpty else { return nil }
                return PlanBlock(
                    time: cleanPlanTime(parts[0]),
                    category: cleanPlanCategory(parts[1]),
                    activity: parts[2]
                )
            }
    }

    private func jsonCandidates(from text: String) -> [String] {
        var candidates: [String] = []
        candidates.append(text)
        if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]") {
            candidates.append(String(text[start...end]))
        }
        if text.hasPrefix("{"),
           let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for value in obj.values {
                if let arr = value as? [[String: Any]],
                   let rewrapped = try? JSONSerialization.data(withJSONObject: arr),
                   let str = String(data: rewrapped, encoding: .utf8) {
                    candidates.append(str)
                }
            }
        }
        return candidates
    }

    private func makePlanBlocks(from array: [[String: Any]]) -> [PlanBlock] {
        array.compactMap { dict in
            guard let rawTime = dict["time"] as? String,
                  let activity = dict["activity"] as? String,
                  activity.isNotEmpty else { return nil }
            let time = cleanPlanTime(rawTime)
            let category = cleanPlanCategory(dict["category"] as? String ?? "")
            return PlanBlock(time: time, category: category, activity: activity)
        }
    }

    // "08:00-09:00" or "8:00 AM" → "08:00"
    private func cleanPlanTime(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespaces)
        if let dash = t.firstIndex(of: "-") { t = String(t[..<dash]).trimmingCharacters(in: .whitespaces) }
        if let space = t.firstIndex(of: " ") { t = String(t[..<space]) }
        // Pad single-digit hour: "7:30" → "07:30"
        let parts = t.split(separator: ":")
        if parts.count == 2, let h = Int(parts[0]), h < 10 { return "0\(h):\(parts[1])" }
        return t
    }

    // "morning|workout" or "morning/nutrition" → "morning"
    private func cleanPlanCategory(_ raw: String) -> String {
        let valid = ["morning", "workout", "nutrition", "focus", "evening"]
        let first = raw.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "|/,; "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { valid.contains($0) })
        return first ?? "morning"
    }

    private var todayWorkoutsSection: some View {
        ApexSectionCard(title: "Today's Workouts", systemImage: "dumbbell.fill", accentColor: ApexColor.accent) {
            ForEach(todayWorkouts) { workout in
                HStack {
                    Image(systemName: workout.type.systemImage)
                        .foregroundStyle(Color.workoutTypeColor(workout.type))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.type.rawValue)
                            .font(.subheadline.bold())
                            .foregroundStyle(ApexColor.textPrimary)
                        Text("\(workout.durationMinutes)m · \(workout.caloriesBurned) kcal")
                            .font(.caption)
                            .foregroundStyle(ApexColor.textSecondary)
                    }
                    Spacer()
                    XPBadge(amount: workout.xpEarned)
                }
            }
        }
    }

    private var calendarSection: some View {
        ApexSectionCard(title: "Calendar", systemImage: "calendar", accentColor: .orange) {
            VStack(spacing: 10) {
                ForEach(calendar.todayEvents.prefix(5)) { event in
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(Color.orange.opacity(0.8))
                            .frame(width: 3)
                            .clipShape(Capsule())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(ApexColor.textPrimary)
                                .lineLimit(1)
                            Text(event.timeRange)
                                .font(.caption)
                                .foregroundStyle(ApexColor.textSecondary)
                        }
                        Spacer()
                        if event.durationMinutes > 0 && !event.isAllDay {
                            Text("\(event.durationMinutes)m")
                                .font(.caption.bold())
                                .foregroundStyle(ApexColor.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var nutritionSummarySection: some View {
        ApexSectionCard(title: "Nutrition", systemImage: "fork.knife", accentColor: ApexColor.success) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(totalCaloriesToday) kcal")
                        .font(.title2.bold())
                        .foregroundStyle(ApexColor.success)
                    Text("\(todayMeals.count) meal\(todayMeals.count == 1 ? "" : "s") logged")
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                }
                Spacer()
                macroSummary
            }
        }
    }

    private var macroSummary: some View {
        let totalProtein = todayMeals.reduce(0.0) { $0 + $1.proteinGrams }
        let totalCarbs   = todayMeals.reduce(0.0) { $0 + $1.carbsGrams }
        let totalFat     = todayMeals.reduce(0.0) { $0 + $1.fatGrams }
        return HStack(spacing: 8) {
            macroChip(label: "P", value: Int(totalProtein), color: ApexColor.accent)
            macroChip(label: "C", value: Int(totalCarbs),   color: ApexColor.accentCyan)
            macroChip(label: "F", value: Int(totalFat),     color: ApexColor.warning)
        }
    }

    private func macroChip(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)g")
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(ApexColor.textSecondary)
        }
    }

    // MARK: - Colors

    private var sleepColor: Color {
        switch healthKit.sleepHoursLast {
        case 7...: return ApexColor.success
        case 6..<7: return ApexColor.warning
        default:   return ApexColor.danger
        }
    }

    private var hrvColor: Color {
        healthKit.hrv > 50 ? ApexColor.success : healthKit.hrv > 30 ? ApexColor.warning : ApexColor.danger
    }

    // MARK: - Actions

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning,"
        case 12..<17: return "Good afternoon,"
        case 17..<22: return "Good evening,"
        default:      return "Hey,"
        }
    }

    private func generatePlan() async {
        planError = nil
        isGeneratingPlan = true
        defer { isGeneratingPlan = false }
        do {
            let ctx = ApexContext(
                userName: profile?.name ?? "Athlete",
                sleepHours: healthKit.sleepHoursLast,
                restingHR: healthKit.restingHeartRate,
                hrv: healthKit.hrv,
                todayActiveCalories: healthKit.todayActiveCalories,
                exerciseMinutes: healthKit.todayExerciseMinutes,
                steps: healthKit.todaySteps,
                vo2Max: healthKit.vo2Max,
                weight: healthKit.weight,
                respiratoryRate: healthKit.respiratoryRate,
                mindfulMinutes: healthKit.mindfulMinutes,
                weeklyAvgSleep: healthKit.weeklyAvgSleep,
                weeklyAvgHRV: healthKit.weeklyAvgHRV,
                weeklyAvgActiveCalories: healthKit.weeklyAvgActiveCalories,
                weeklyWorkoutCount: healthKit.weeklyWorkoutCount,
                energyLevel: todayCheckIn?.energyLevel ?? 3,
                recoveryRating: todayCheckIn?.recoveryRating ?? "Moderate",
                sleepScore: todayCheckIn?.sleepScore ?? 0,
                focusProjects: todayCheckIn?.focusProjectNames ?? [],
                customNote: todayCheckIn?.customFocusNote ?? "",
                recentWorkoutTypes: Array(workouts.prefix(7).map { $0.type.rawValue }),
                todayMealCalories: totalCaloriesToday,
                todayMeals: todayMeals.count,
                calendarEvents: calendar.todayEvents.map { $0.summary },
                githubCommitsToday: github.todayCommits,
                githubActiveRepos: github.activeRepos
            )
            let planText = try await claude.generateDailyPlan(context: ctx)
            // Delete stale plans for today, then insert fresh
            for old in plans.filter({ $0.date.isToday }) { context.delete(old) }
            context.insert(DailyPlan(date: Date(), planText: planText))
        } catch {
            planError = error.localizedDescription
        }
    }

    private func checkAchievementToast() {
        guard let achievement = gamification.popNextAchievement() else { return }
        toastAchievement = achievement
        withAnimation(.spring()) { showAchievement = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { showAchievement = false }
        }
    }

    private func animateXP() {
        xpFloatOffset = 0
        xpFloatOpacity = 1
        withAnimation(.easeOut(duration: 1.2)) {
            xpFloatOffset = -80
            xpFloatOpacity = 0
        }
    }
}
