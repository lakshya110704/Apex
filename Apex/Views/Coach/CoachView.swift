import SwiftUI
import SwiftData

struct CoachView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date, order: .reverse) private var workouts: [WorkoutSession]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(filter: #Predicate<DailyPlan> { _ in true }, sort: \DailyPlan.date, order: .reverse)
    private var plans: [DailyPlan]
    @Query private var profiles: [UserProfile]
    @Query(sort: \MorningCheckIn.date, order: .reverse) private var checkIns: [MorningCheckIn]
    @Query private var scheduleEntries: [WorkoutScheduleEntry]

    private var profile: UserProfile? { profiles.first }
    private var todayCheckIn: MorningCheckIn? { checkIns.first(where: { $0.date.isToday }) }

    var claude: ClaudeService
    var healthKit: HealthKitService
    var calendar: CalendarService
    var github: GitHubService

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isTyping = false
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var inputFocused: Bool

    private var todayPlan: DailyPlan? { plans.first(where: { $0.date.isToday }) }

    // MARK: - Coach Stance

    private enum CoachStance {
        case noData, fullSend, measured, recovery, rest

        var label: String {
            switch self {
            case .noData:    return "No Data"
            case .fullSend:  return "Full Send"
            case .measured:  return "Measured"
            case .recovery:  return "Recovery"
            case .rest:      return "Rest Day"
            }
        }
        var icon: String {
            switch self {
            case .noData:    return "questionmark.circle.fill"
            case .fullSend:  return "flame.fill"
            case .measured:  return "bolt.fill"
            case .recovery:  return "leaf.fill"
            case .rest:      return "moon.fill"
            }
        }
        var color: Color {
            switch self {
            case .noData:    return ApexColor.textSecondary
            case .fullSend:  return ApexColor.accent
            case .measured:  return ApexColor.accentCyan
            case .recovery:  return ApexColor.warning
            case .rest:      return ApexColor.textSecondary
            }
        }
        var description: String {
            switch self {
            case .noData:    return "Needs sleep or HRV data. Allow Health access and sync your Watch."
            case .fullSend:  return "HRV & sleep are strong. No excuses today."
            case .measured:  return "Train smart. Not your best day, not your worst."
            case .recovery:  return "Light work only. Body needs to rebuild."
            case .rest:      return "Metrics say rest. Honor it."
            }
        }
    }

    private var coachStance: CoachStance {
        let hrv = healthKit.hrv
        let avgHRV = healthKit.weeklyAvgHRV
        let sleepScore = todayCheckIn?.sleepScore ?? Int(healthKit.sleepHoursLast / 8.0 * 100)
        let energy = todayCheckIn?.energyLevel ?? 3

        // No sleep or HRV reading at all: don't present a default as a measurement.
        if hrv == 0 && sleepScore == 0 { return .noData }

        let hrvGood = avgHRV > 0 ? hrv >= avgHRV * 0.9 : true
        let sleepGood = sleepScore >= 65
        let energyGood = energy >= 3

        let goodCount = [hrvGood, sleepGood, energyGood].filter { $0 }.count

        switch goodCount {
        case 3:       return .fullSend
        case 2:       return .measured
        case 1:       return .recovery
        default:      return .rest
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Coach stance banner
                    stanceBanner

                    // Chat messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if messages.isEmpty {
                                    welcomePrompts
                                }
                                ForEach(messages) { message in
                                    messageBubble(message)
                                        .id(message.id)
                                }
                                if isTyping {
                                    typingIndicator
                                        .id("typing")
                                }
                            }
                            .padding()
                        }
                        .scrollDismissesKeyboard(.immediately)
                        .onAppear { scrollProxy = proxy }
                        .onChange(of: messages.count) { _, _ in
                            withAnimation { scrollProxy?.scrollTo(messages.last?.id, anchor: .bottom) }
                        }
                        .onChange(of: isTyping) { _, typing in
                            if typing { withAnimation { scrollProxy?.scrollTo("typing", anchor: .bottom) } }
                        }
                    }

                    Text("AI coaching based on your logged data. Not medical advice.")
                        .font(.caption2)
                        .foregroundStyle(ApexColor.textSecondary)
                        .padding(.bottom, 4)

                    // Input bar
                    inputBar
                }
            }
            .navigationTitle("Apex Coach")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { inputFocused = false }
                        .foregroundStyle(ApexColor.accent)
                }
            }
        }
    }

    // MARK: - Stance Banner

    private var stanceBanner: some View {
        let stance = coachStance
        return HStack(spacing: 10) {
            Image(systemName: stance.icon)
                .font(.caption.bold())
                .foregroundStyle(stance.color)

            VStack(alignment: .leading, spacing: 1) {
                Text(stance.label.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(stance.color)
                Text(stance.description)
                    .font(.caption2)
                    .foregroundStyle(ApexColor.textSecondary)
            }

            Spacer()

            // Today's key stats
            if let cal = todayCalorieInfo {
                statChip(value: cal, label: "kcal left", color: ApexColor.danger)
            }
            if let pro = todayProteinInfo {
                statChip(value: pro, label: "g protein", color: ApexColor.accentCyan)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(stance.color.opacity(0.08))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(stance.color.opacity(0.15)), alignment: .bottom)
    }

    private var todayCalorieInfo: String? {
        let profile = profiles.first
        let target = calorieTarget(for: profile)
        guard target > 0 else { return nil }
        let eaten = todayMeals.reduce(0) { $0 + $1.estimatedCalories }
        return "\(target - eaten)"
    }

    private var todayProteinInfo: String? {
        guard let profile, profile.name.isNotEmpty else { return nil }
        let target = proteinTarget(for: profile)
        guard target > 0 else { return nil }
        let eaten = Int(todayMeals.reduce(0.0) { $0 + $1.proteinGrams })
        return "\(target - eaten)"
    }

    private var todayMeals: [MealEntry] { meals.filter { $0.date.isToday } }

    private func calorieTarget(for profile: UserProfile?) -> Int {
        guard profile != nil else { return 0 }
        let w = healthKit.weight > 0 ? healthKit.weight : 0
        guard w > 0 else { return 0 }
        return Int(w * 33)
    }

    private func proteinTarget(for profile: UserProfile?) -> Int {
        let w = healthKit.weight > 0 ? healthKit.weight : 0
        guard w > 0 else { return 0 }
        return Int(w * 1.8)  // 1.8g per kg — athlete standard
    }

    private func statChip(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(ApexColor.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Welcome Prompts

    private var welcomePrompts: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 16)
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 40))
                    .foregroundStyle(ApexColor.accent)
                Text("Apex Coach")
                    .font(.title2.bold())
                    .foregroundStyle(ApexColor.textPrimary)
                Text("Answers based on the data you have logged.")
                    .font(.subheadline)
                    .foregroundStyle(ApexColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Text("Try asking")
                    .font(.caption.bold())
                    .foregroundStyle(ApexColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(quickPrompts, id: \.self) { prompt in
                    Button { sendMessage(prompt) } label: {
                        HStack {
                            Text(prompt)
                                .font(.subheadline)
                                .foregroundStyle(ApexColor.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.circle")
                                .foregroundStyle(ApexColor.accent)
                        }
                        .padding(12)
                        .background(ApexColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private var quickPrompts: [String] {
        [
            "Can I have ice cream tonight?",
            "Should I skip today's workout?",
            "Am I overtraining this week?",
            "What should I eat right now?",
            "Is my recovery good enough to push hard today?",
        ]
    }

    // MARK: - Message Bubble

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(ApexColor.accent)
                    .frame(width: 28, height: 28)
                    .background(ApexColor.accent.opacity(0.15))
                    .clipShape(Circle())
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.subheadline)
                    .foregroundStyle(ApexColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? ApexColor.accent : ApexColor.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(message.timestamp.shortTime)
                    .font(.caption2)
                    .foregroundStyle(ApexColor.textSecondary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
                    .frame(width: 28, height: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.caption)
                .foregroundStyle(ApexColor.accent)
                .frame(width: 28, height: 28)
                .background(ApexColor.accent.opacity(0.15))
                .clipShape(Circle())

            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(ApexColor.textSecondary)
                        .frame(width: 6, height: 6)
                        .animation(
                            .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2),
                            value: isTyping
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(ApexColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
    }

    // MARK: - Input Bar

    private var canSend: Bool {
        claude.apiKey.isNotEmpty || claude.isLocalAIAvailable
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask your coach...", text: $inputText, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(ApexColor.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(ApexColor.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...4)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit {
                    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard text.isNotEmpty, canSend else { return }
                    sendMessage(text)
                }

            Button {
                let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.isNotEmpty else { return }
                sendMessage(text)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty || !canSend
                                     ? ApexColor.textSecondary
                                     : ApexColor.accent)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isTyping || !canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(ApexColor.cardBg2)
        .overlay(
            VStack { Divider().background(ApexColor.cardBg2) ; Spacer() },
            alignment: .top
        )
    }

    // MARK: - Send

    private func sendMessage(_ text: String) {
        inputText = ""
        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        isTyping = true

        Task {
            do {
                let apexCtx = buildApexContext()
                let response = try await claude.chat(messages: messages, context: apexCtx)
                let assistantMsg = ChatMessage(role: .assistant, content: response)
                messages.append(assistantMsg)
                updatePlanIfNeeded(with: text, response: response)
            } catch {
                let errMsg = ChatMessage(role: .assistant, content: "Coach offline: \(error.localizedDescription)")
                messages.append(errMsg)
            }
            isTyping = false
        }
    }

    // MARK: - Context Builder

    private func buildApexContext() -> ApexContext {
        let cal = Calendar.current
        let mealsToday = meals.filter { $0.date.isToday }
        let workoutsToday = workouts.filter { cal.isDateInToday($0.date) }
        let profile = profiles.first

        // Nutrition
        let totalCalories = mealsToday.reduce(0) { $0 + $1.estimatedCalories }
        let totalProtein  = mealsToday.reduce(0.0) { $0 + $1.proteinGrams }
        let totalCarbs    = mealsToday.reduce(0.0) { $0 + $1.carbsGrams }
        let totalFat      = mealsToday.reduce(0.0) { $0 + $1.fatGrams }
        let cTarget = calorieTarget(for: profile)
        let pTarget = proteinTarget(for: profile)

        // Schedule vs actual
        let todayWeekday = cal.component(.weekday, from: Date())
        let plannedToday = scheduleEntries
            .filter { $0.dayOfWeek == todayWeekday && $0.isEnabled }
            .map { $0.workoutType.rawValue }
        let completedToday = workoutsToday.map { $0.type.rawValue }

        // Workouts logged in Apex this week
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let weeklyApexWorkouts = workouts.filter { $0.date >= weekStart }.count

        // Missed workouts this week
        var missedCount = 0
        for entry in scheduleEntries where entry.isEnabled {
            if let dayDate = dateInCurrentWeek(for: entry.dayOfWeek),
               dayDate < Date() && !cal.isDateInToday(dayDate) {
                let done = workouts.contains { cal.isDate($0.date, inSameDayAs: dayDate) && $0.type == entry.workoutType }
                if !done { missedCount += 1 }
            }
        }

        return ApexContext(
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
            todayMealCalories: totalCalories,
            todayMeals: mealsToday.count,
            calorieTarget: cTarget,
            proteinTarget: pTarget,
            proteinGrams: totalProtein,
            carbsGrams: totalCarbs,
            fatGrams: totalFat,
            scheduledWorkoutsToday: plannedToday,
            completedWorkoutsToday: completedToday,
            weeklyMissedWorkouts: missedCount,
            currentStreak: profile?.workoutStreak ?? 0,
            xpToday: workoutsToday.reduce(0) { $0 + $1.xpEarned },
            weeklyApexWorkouts: weeklyApexWorkouts,
            calendarEvents: calendar.todayEvents.map { $0.summary },
            githubCommitsToday: github.todayCommits,
            githubActiveRepos: github.activeRepos
        )
    }

    private func dateInCurrentWeek(for dayOfWeek: Int) -> Date? {
        var cal = Calendar.current
        cal.firstWeekday = 2
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return nil }
        let monday = weekInterval.start
        let offset = (dayOfWeek == 1) ? 6 : (dayOfWeek - 2)
        return cal.date(byAdding: .day, value: offset, to: monday)
    }

    private func updatePlanIfNeeded(with userText: String, response: String) {
        let planKeywords = ["plan", "schedule", "adjust", "change", "reschedule", "skip", "modify"]
        let isPlanRelated = planKeywords.contains { userText.localizedCaseInsensitiveContains($0) }
        guard isPlanRelated, let plan = todayPlan else { return }
        plan.userModifications += "\n---\nUser: \(userText)\nCoach: \(response)"
    }
}
