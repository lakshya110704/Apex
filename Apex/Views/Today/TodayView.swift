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
    @Binding var selectedTab: Int

    @State private var isGeneratingPlan = false
    @State private var detail: Detail?
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
                    VStack(spacing: 20) {
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

                        // The day at a glance: what is next, then what you can do about it
                        planHero
                            .padding(.horizontal)

                        quickActions
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            activityTile
                            recoveryTile
                            nutritionTile
                            workoutsTile
                        }
                        .padding(.horizontal)

                        FocusTimerCard(focusTimer: focusTimer)
                            .padding(.horizontal)

                        if nextEvent != nil {
                            calendarTile
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
            .sheet(item: $detail) { item in
                detailSheet(item)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: detail)
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

    // MARK: - Plan hero

    private var planHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(ApexColor.accent)
                    Text("Today's plan").apexLabel()
                }
                Spacer()
                let aiReady = claude.isConfigured
                Button {
                    Task { await generatePlan() }
                } label: {
                    Label(todayPlan == nil ? "Generate" : "Refresh", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(aiReady ? ApexColor.accent : ApexColor.textSecondary)
                }
                .buttonStyle(PressableStyle())
                .disabled(isGeneratingPlan || !aiReady)
            }

            if let error = planError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(ApexColor.warning)
            } else if isGeneratingPlan {
                HStack(spacing: 12) {
                    ProgressView().tint(ApexColor.accent)
                    Text("Building your day...")
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.textSecondary)
                }
            } else if let plan = todayPlan {
                let blocks = parsePlanBlocks(from: plan.planText)
                if blocks.isEmpty {
                    Text(plan.planText)
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    planContent(blocks)
                }
            } else {
                emptyPlan
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func planContent(_ blocks: [PlanBlock]) -> some View {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let nextIndex = PlanTiming.nextIndex(times: blocks.map(\.time), now: nowMinutes) ?? 0
        let next = blocks[nextIndex]

        VStack(alignment: .leading, spacing: 6) {
            Text("NEXT UP")
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(next.accentColor)
            Text(next.time)
                .apexDisplay(52)
                .foregroundStyle(ApexColor.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: next.iconName).foregroundStyle(next.accentColor)
                Text(next.activity)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ApexColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        planChip(block, state: index < nextIndex ? .past : (index == nextIndex ? .next : .later))
                            .id(block.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .onAppear { proxy.scrollTo(next.id, anchor: .leading) }
        }
        .padding(.horizontal, -18)
        .contentMargins(.horizontal, 18, for: .scrollContent)
    }

    private enum ChipState { case past, next, later }

    private func planChip(_ block: PlanBlock, state: ChipState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(block.time)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(ApexColor.textSecondary)
                Spacer()
                Image(systemName: block.iconName)
                    .font(.caption)
                    .foregroundStyle(block.accentColor)
            }
            Text(block.activity)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ApexColor.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 148, height: 96, alignment: .topLeading)
        .background(state == .next ? block.accentColor.opacity(0.14) : ApexColor.cardBg2)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(state == .next ? block.accentColor.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
        .opacity(state == .past ? 0.5 : 1)
    }

    private var emptyPlan: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 32))
                .foregroundStyle(ApexColor.accent.opacity(0.4))
            let aiReady = claude.isConfigured
            Text(aiReady
                 ? "Generate a personalized plan for today."
                 : "Choose an AI provider and add its key in Settings to enable AI planning.")
                .font(.subheadline)
                .foregroundStyle(ApexColor.textSecondary)
                .multilineTextAlignment(.center)
            if aiReady {
                Button { Task { await generatePlan() } } label: {
                    Text("Generate plan")
                        .font(.subheadline.bold())
                        .foregroundStyle(ApexColor.onAccent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(ApexColor.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            quickAction("Log workout", systemImage: "dumbbell.fill", tab: 1)
            quickAction("Snap a meal", systemImage: "camera.fill", tab: 2)
            quickAction("Ask coach", systemImage: "brain.head.profile", tab: 4)
        }
    }

    private func quickAction(_ title: String, systemImage: String, tab: Int) -> some View {
        Button { selectedTab = tab } label: {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(ApexColor.accent)
                    .frame(height: 26)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ApexColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(ApexColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Tiles

    private func tile<Content: View>(_ item: Detail, title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        Button { detail = item } label: {
            ApexTile(title: title, systemImage: systemImage, content: content)
        }
        .buttonStyle(PressableStyle())
    }

    private var activityTile: some View {
        tile(.activity, title: "Activity", systemImage: "circle.circle.fill") {
            HStack(spacing: 14) {
                ZStack {
                    RingView(progress: healthKit.moveProgress, color: ApexColor.danger, lineWidth: 7, size: 66)
                    RingView(progress: healthKit.exerciseProgress, color: ApexColor.success, lineWidth: 7, size: 48)
                    RingView(progress: healthKit.standProgress, color: ApexColor.accent, lineWidth: 7, size: 30)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(healthKit.todayActiveCalories))")
                        .apexDisplay(30)
                        .foregroundStyle(ApexColor.textPrimary)
                    Text("kcal moved")
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                }
            }
        }
    }

    private var recoveryTile: some View {
        tile(.recovery, title: "Recovery", systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 2) {
                Text(healthKit.sleepHoursLast > 0 ? String(format: "%.1f", healthKit.sleepHoursLast) : "–")
                    .apexDisplay(36)
                    .foregroundStyle(healthKit.sleepHoursLast > 0 ? sleepColor : ApexColor.textSecondary)
                Text(healthKit.sleepHoursLast > 0 ? "hours of sleep" : "No sleep data")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
                Text(healthKit.hrv > 0 ? "HRV \(Int(healthKit.hrv)) ms" : "HRV no data")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(healthKit.hrv > 0 ? hrvColor : ApexColor.textSecondary)
                    .padding(.top, 4)
            }
        }
    }

    private var nutritionTile: some View {
        tile(.nutrition, title: "Nutrition", systemImage: "fork.knife") {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(totalCaloriesToday)")
                    .apexDisplay(36)
                    .foregroundStyle(ApexColor.textPrimary)
                Text("kcal today")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
                Text("\(todayMeals.count) meal\(todayMeals.count == 1 ? "" : "s") logged")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ApexColor.textSecondary)
                    .padding(.top, 4)
            }
        }
    }

    private var workoutsTile: some View {
        tile(.workouts, title: "Training", systemImage: "dumbbell.fill") {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(todayWorkouts.count)")
                    .apexDisplay(36)
                    .foregroundStyle(ApexColor.textPrimary)
                Text(todayWorkouts.isEmpty ? "No workout yet" : "workout\(todayWorkouts.count == 1 ? "" : "s") today")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
                Label("\(profile?.workoutStreak ?? 0) day streak", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle((profile?.workoutStreak ?? 0) > 0 ? ApexColor.danger : ApexColor.textSecondary)
                    .padding(.top, 4)
            }
        }
    }

    private var nextEvent: CalendarEvent? {
        calendar.todayEvents.first(where: { $0.endTime > Date() }) ?? calendar.todayEvents.first
    }

    private var calendarTile: some View {
        Button { detail = .calendar } label: {
            ApexTile(title: "Next event", systemImage: "calendar") {
                if let event = nextEvent {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(ApexColor.textPrimary)
                            .lineLimit(2)
                        Text(event.timeRange)
                            .font(.caption)
                            .foregroundStyle(ApexColor.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Detail sheets

    private enum Detail: String, Identifiable {
        case activity, recovery, nutrition, workouts, calendar
        var id: String { rawValue }
        var title: String {
            switch self {
            case .activity:  return "Activity"
            case .recovery:  return "Recovery"
            case .nutrition: return "Nutrition"
            case .workouts:  return "Training"
            case .calendar:  return "Calendar"
            }
        }
    }

    private func detailSheet(_ item: Detail) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    switch item {
                    case .activity:
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
                    case .recovery:
                        recoveryStatsSection
                    case .nutrition:
                        if todayMeals.isEmpty { emptyDetail("No meals logged today.") } else { nutritionSummarySection }
                    case .workouts:
                        if todayWorkouts.isEmpty { emptyDetail("No workouts logged today.") } else { todayWorkoutsSection }
                    case .calendar:
                        if calendar.todayEvents.isEmpty { emptyDetail("No events today.") } else { calendarSection }
                    }
                }
                .padding()
            }
            .background(ApexColor.background)
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func emptyDetail(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(ApexColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
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
                energyLevel: todayCheckIn?.energyLevel ?? 0,
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
