import SwiftUI
import SwiftData

/// The coach's look back at one week: the numbers (worked out on device), the coach's words,
/// and up to two schedule changes you can accept for next week.
struct WeeklyReviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date, order: .reverse) private var workouts: [WorkoutSession]
    @Query private var scheduleEntries: [WorkoutScheduleEntry]
    @Query(sort: \MorningCheckIn.date, order: .reverse) private var checkIns: [MorningCheckIn]
    @Query(sort: \CoachMemory.createdAt, order: .reverse) private var memories: [CoachMemory]
    @Query(sort: \WeeklyReview.weekStart, order: .reverse) private var reviews: [WeeklyReview]
    @Query private var profiles: [UserProfile]

    var claude: ClaudeService
    var healthKit: HealthKitService

    @State private var isWriting = false
    @State private var error: String?

    private let weekStart = WeeklyReviewEngine.reviewWeekStart()

    private var review: WeeklyReview? {
        reviews.first { Calendar.current.isDate($0.weekStart, inSameDayAs: weekStart) }
    }

    /// The Watch's rolling 7-day averages only describe the reviewed week when it ends today.
    private var coversThisWeek: Bool {
        WeeklyReviewEngine.mondayCalendar().isDate(weekStart, equalTo: Date(), toGranularity: .weekOfYear)
    }

    private var stats: WeeklyReviewEngine.Stats {
        WeeklyReviewEngine.stats(
            weekStart: weekStart,
            sessions: workouts.map { WeeklyReviewEngine.Session($0) },
            schedule: scheduleEntries.filter(\.isEnabled).map { WeeklyReviewEngine.Slot($0) },
            checkIns: checkIns.filter(\.isComplete).map { WeeklyReviewEngine.CheckIn($0) },
            goals: memories.filter { $0.kind == .goal }.map(\.text)
        )
    }

    var body: some View {
        let stats = stats
        ZStack {
            ApexColor.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    numbers(stats)
                    coachCard(stats)
                    Spacer(minLength: 32)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Weekly Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        let end = WeeklyReviewEngine.mondayCalendar().date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return VStack(alignment: .leading, spacing: 4) {
            Text(coversThisWeek ? "This week" : "Last week").apexLabel()
            Text("\(CoachMemoryEngine.shortDate(weekStart)) – \(CoachMemoryEngine.shortDate(end))")
                .font(.title3.weight(.bold))
                .foregroundStyle(ApexColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Numbers

    private func numbers(_ s: WeeklyReviewEngine.Stats) -> some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                statTile("Plan kept", systemImage: "checkmark.circle.fill",
                         value: s.adherenceText ?? "–",
                         caption: s.planned > 0 ? "scheduled sessions done" : "nothing scheduled")
                statTile("Training", systemImage: "stopwatch.fill",
                         value: "\(s.minutes) min",
                         caption: change(s.minutes, from: s.previousMinutes, unit: "min"))
                statTile("Sessions", systemImage: "figure.mixed.cardio",
                         value: "\(s.sessions)",
                         caption: change(s.sessions, from: s.previousSessions, unit: ""))
                statTile("Recovery", systemImage: "bed.double.fill",
                         value: s.averageSleepScore.map { "\($0)" } ?? "–",
                         caption: s.checkIns > 0 ? "avg sleep score · \(s.checkIns) check-ins" : "no check-ins")
            }

            if !s.missed.isEmpty || s.tennisRecord.played > 0 || !s.staleDrills.isEmpty || !s.byType.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    if !s.byType.isEmpty {
                        detailRow("figure.run", ApexColor.accent,
                                  s.byType.map { "\($0.type.rawValue) \($0.sessions)×" }.joined(separator: " · "))
                    }
                    if !s.missed.isEmpty {
                        detailRow("xmark.circle.fill", ApexColor.warning, "Missed: " + s.missed.joined(separator: ", "))
                    }
                    if s.extra > 0 {
                        detailRow("plus.circle.fill", ApexColor.success, "\(s.extra) extra session\(s.extra == 1 ? "" : "s") not on the schedule")
                    }
                    if s.tennisRecord.played > 0 {
                        detailRow("figure.tennis", ApexColor.tennis, "Tennis matches \(s.tennisRecord.text)")
                    }
                    if !s.staleDrills.isEmpty {
                        detailRow("clock.badge.exclamationmark", ApexColor.textSecondary,
                                  "Not practiced in 3+ weeks: " + s.staleDrills.joined(separator: ", "))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .apexCard()
            }
        }
    }

    private func change(_ value: Int, from previous: Int, unit: String) -> String {
        let delta = value - previous
        let suffix = unit.isEmpty ? "" : " \(unit)"
        if delta == 0 { return "same as the week before" }
        return "\(delta > 0 ? "+" : "−")\(abs(delta))\(suffix) on the week before"
    }

    private func statTile(_ title: String, systemImage: String, value: String, caption: String) -> some View {
        ApexTile(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .apexDisplay(32)
                    .foregroundStyle(ApexColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func detailRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(ApexColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
    }

    // MARK: - Coach

    private func coachCard(_ s: WeeklyReviewEngine.Stats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Coach's review", systemImage: "brain.head.profile")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(ApexColor.accent)
                Spacer()
                if review != nil, claude.isConfigured, !isWriting {
                    Button("Rewrite") { Task { await write(s) } }
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.accent)
                }
            }

            if isWriting {
                HStack(spacing: 12) {
                    ProgressView().tint(ApexColor.accent)
                    Text("Looking back at your week...")
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.textSecondary)
                }
            } else if let review {
                Text(review.text)
                    .font(.body)
                    .foregroundStyle(ApexColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !review.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For next week").apexLabel()
                        ForEach(review.suggestions, id: \.self) { tag in
                            suggestionRow(tag, review: review)
                        }
                    }
                }
            } else if claude.isConfigured {
                Text("Your coach reads the numbers above and your goals, says what went well and what didn't, and suggests changes for next week.")
                    .font(.subheadline)
                    .foregroundStyle(ApexColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { Task { await write(s) } } label: {
                    Text("Write my review")
                        .font(.subheadline.bold())
                        .foregroundStyle(ApexColor.onAccent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(ApexColor.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            } else {
                Text("Choose an AI provider and add its key in Settings to get the coach's review. The numbers above work without one.")
                    .font(.subheadline)
                    .foregroundStyle(ApexColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(ApexColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func suggestionRow(_ tag: String, review: WeeklyReview) -> some View {
        if let change = WeeklyReviewEngine.change(from: tag) {
            let accepted = review.accepted.contains(tag)
            HStack(spacing: 12) {
                Image(systemName: change.type.systemImage)
                    .foregroundStyle(ApexColor.accent)
                    .frame(width: 24)
                Text(PlanUpdateEngine.describe(change))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ApexColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if accepted {
                    Label("Added", systemImage: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.success)
                } else {
                    Button("Accept") { accept(change, tag: tag, review: review) }
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(ApexColor.accent)
                        .clipShape(Capsule())
                        .buttonStyle(PressableStyle())
                        .accessibilityHint("Adds this to your weekly schedule in Workouts.")
                }
            }
            .padding(12)
            .background(ApexColor.cardBg2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .sensoryFeedback(.success, trigger: accepted)
        }
    }

    // MARK: - Actions

    private func write(_ s: WeeklyReviewEngine.Stats) async {
        guard !isWriting else { return }
        isWriting = true
        error = nil
        let health = coversThisWeek ? (sleepHours: healthKit.weeklyAvgSleep, hrv: healthKit.weeklyAvgHRV) : nil
        do {
            let raw = try await claude.weeklyReview(
                data: WeeklyReviewEngine.dataBlock(s, health: health),
                name: profiles.first?.name ?? "",
                nextWeek: WeeklyReviewEngine.suggestionStart()
            )
            let (text, suggestions) = WeeklyReviewEngine.parse(raw)
            guard text.isNotEmpty else { throw ClaudeError.parseError }
            for old in reviews where Calendar.current.isDate(old.weekStart, inSameDayAs: weekStart) {
                context.delete(old)
            }
            context.insert(WeeklyReview(weekStart: weekStart, text: text, suggestions: suggestions))
            try? context.save()
        } catch {
            self.error = error.localizedDescription
        }
        isWriting = false
    }

    private func accept(_ change: PlanUpdateEngine.ScheduleChange, tag: String, review: WeeklyReview) {
        WorkoutScheduleEntry.apply(WeeklyReviewEngine.startingNoEarlierThanToday(change), to: scheduleEntries, in: context)
        review.accepted.append(tag)
        try? context.save()
    }
}
