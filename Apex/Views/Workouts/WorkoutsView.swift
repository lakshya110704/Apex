import SwiftUI
import HealthKit
import SwiftData

struct WorkoutsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date, order: .reverse) private var workouts: [WorkoutSession]
    @Query private var scheduleEntries: [WorkoutScheduleEntry]

    var gamification: GamificationService
    var healthKit: HealthKitService
    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    @State private var workoutTypeToAdd: WorkoutType?
    @State private var isImporting = false
    @State private var importedSession: WorkoutSession?
    @State private var showingScheduleEditor = false
    @State private var selectedDay: DayItem?
    @State private var showingAllHistory = false

    private var importedUUIDs: Set<String> {
        Set(workouts.compactMap(\.healthKitUUID))
    }

    private var unimportedWatchWorkouts: [HKWorkout] {
        healthKit.recentWorkouts.filter { !importedUUIDs.contains($0.uuid.uuidString) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // From Watch
                        if !unimportedWatchWorkouts.isEmpty {
                            watchImportSection
                                .padding(.horizontal)
                        }

                        // The week at a glance
                        weekCard
                            .padding(.horizontal)

                        // Quick Add
                        quickAddSection
                            .padding(.horizontal)

                        // What to train next
                        if workouts.contains(where: { $0.type == .gym }) {
                            muscleFocusSection
                        }

                        // Recent
                        if workouts.isEmpty {
                            EmptyStateView(
                                icon: "dumbbell",
                                title: "No Workouts Yet",
                                subtitle: "Log your first workout to start earning XP"
                            )
                            .padding(.top, 20)
                        } else {
                            recentSection
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Workouts")
            .sheet(item: $workoutTypeToAdd) { type in
                if type == .tennis {
                    TennisLogView(gamification: gamification, prefillSession: importedSession)
                } else {
                    GymWorkoutView(gamification: gamification, prefillSession: importedSession)
                }
            }
            .onChange(of: workoutTypeToAdd) { _, newVal in
                if newVal == nil { importedSession = nil }
            }
            .task { await healthKit.fetchAllTodayData() }
            .sheet(isPresented: $showingScheduleEditor) {
                WorkoutScheduleEditorView()
            }
            .sheet(item: $selectedDay) { item in
                dayDetailSheet(item.id)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingAllHistory) {
                allHistorySheet
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Watch Import

    private var watchImportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("From Apple Watch", systemImage: "applewatch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ApexColor.accentCyan)
                Spacer()
                Text("\(unimportedWatchWorkouts.count) new")
                    .font(.caption.bold())
                    .foregroundStyle(ApexColor.textSecondary)
            }

            ForEach(unimportedWatchWorkouts.prefix(5), id: \.uuid) { hkWorkout in
                watchWorkoutRow(hkWorkout)
            }
        }
    }

    private func watchWorkoutRow(_ hkWorkout: HKWorkout) -> some View {
        let type = HealthKitService.workoutType(from: hkWorkout.workoutActivityType)
        let calories = Int(hkWorkout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0)
        let duration = Int(hkWorkout.duration / 60)
        let color = Color.workoutTypeColor(type)

        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: type.systemImage).font(.headline).foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(type.rawValue)
                    .font(.subheadline.bold())
                    .foregroundStyle(ApexColor.textPrimary)
                Text("\(duration)m · \(calories) kcal · \(hkWorkout.startDate.dayAndMonth)")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            }

            Spacer()

            Button {
                Task { await importWorkout(hkWorkout) }
            } label: {
                if isImporting {
                    ProgressView().tint(ApexColor.accentCyan).scaleEffect(0.8)
                } else {
                    Text("Import")
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.onAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ApexColor.accentCyan)
                        .clipShape(Capsule())
                }
            }
            .disabled(isImporting)
        }
        .padding(14)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func importWorkout(_ hkWorkout: HKWorkout) async {
        isImporting = true
        let session = await healthKit.buildWorkoutSession(from: hkWorkout)
        context.insert(session)
        if let profile { gamification.processWorkout(session, profile: profile, context: context) }
        importedSession = session  // pass directly — don't rely on @Query update timing
        let type = HealthKitService.workoutType(from: hkWorkout.workoutActivityType)
        workoutTypeToAdd = type
        isImporting = false
    }

    // MARK: - Quick Add

    private var quickAddSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log Workout")
                .apexLabel()
            HStack(spacing: 12) {
                quickAddButton(type: .tennis, color: ApexColor.tennis)
                quickAddButton(type: .gym,    color: ApexColor.accent)
            }
        }
    }

    private func quickAddButton(type: WorkoutType, color: Color) -> some View {
        Button { workoutTypeToAdd = type } label: {
            HStack(spacing: 10) {
                Image(systemName: type.systemImage)
                    .font(.title3)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(ApexColor.textPrimary)
                    Text("+\(type == .tennis ? XPValues.logTennisSession : XPValues.logGymWorkout) XP")
                        .font(.caption)
                        .foregroundStyle(color)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(color)
            }
            .padding(14)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Muscle Recovery

    private var muscleStatuses: [MuscleGroupTracker.Status] {
        MuscleGroupTracker.statuses(from: workouts)
    }

    private var muscleFocusSection: some View {
        let statuses = muscleStatuses
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Train next").apexLabel()
                Spacer()
                NavigationLink(destination: MuscleHeatmapView()) {
                    Label("Muscle map", systemImage: "figure.arms.open")
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.accent)
                }
            }
            .padding(.horizontal)

            if let focus = MuscleGroupTracker.suggestion(from: statuses) {
                focusHero(focus)
                    .padding(.horizontal)
            } else {
                Label("Every muscle group was trained recently.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ApexColor.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(ApexColor.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(statuses) { status in
                        muscleChip(status)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
    }

    private func focusHero(_ status: MuscleGroupTracker.Status) -> some View {
        let color = status.recoveryLevel.color
        return HStack(spacing: 14) {
            Image(systemName: status.muscleGroup.systemImage)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 52, height: 52)
                .background(color.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(status.muscleGroup.rawValue)
                    .apexDisplay(34)
                    .foregroundStyle(ApexColor.textPrimary)
                Text(status.daysSinceTrained.map { "\($0) days since your last session" } ?? "Not trained yet")
                    .font(.subheadline)
                    .foregroundStyle(color)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
    }

    private func muscleChip(_ status: MuscleGroupTracker.Status) -> some View {
        let color = status.recoveryLevel.color
        return VStack(alignment: .leading, spacing: 6) {
            Image(systemName: status.muscleGroup.systemImage)
                .font(.subheadline)
                .foregroundStyle(color)
            Text(status.muscleGroup.rawValue)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ApexColor.textPrimary)
            Text(status.gapDescription)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 118, alignment: .leading)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Weekly Schedule

    // Mon=2, Tue=3, Wed=4, Thu=5, Fri=6, Sat=7, Sun=1
    private let weekdayOrder: [(Int, String)] = [
        (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")
    ]

    private func startOfWeek() -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    private func date(for dayOfWeek: Int) -> Date {
        let monday = startOfWeek()
        let cal = Calendar.current
        // dayOfWeek: 1=Sun, 2=Mon...7=Sat. Monday is weekday 2.
        let offset = (dayOfWeek == 1) ? 6 : (dayOfWeek - 2)
        return cal.date(byAdding: .day, value: offset, to: monday) ?? monday
    }

    private func workoutsOn(_ day: Date) -> [WorkoutSession] {
        let cal = Calendar.current
        return workouts.filter { cal.isDate($0.date, inSameDayAs: day) }
    }

    private struct DayItem: Identifiable { let id: Int }

    private func planned(on dayNum: Int) -> [WorkoutScheduleEntry] {
        scheduleEntries.filter { $0.dayOfWeek == dayNum && $0.isEnabled }
    }

    private var weekProgress: (done: Int, total: Int) {
        var plannedSessions: [(day: Int, type: WorkoutType)] = []
        var doneByDay: [Int: Set<WorkoutType>] = [:]
        for (dayNum, _) in weekdayOrder {
            doneByDay[dayNum] = Set(workoutsOn(date(for: dayNum)).map(\.type))
            plannedSessions += planned(on: dayNum).map { (dayNum, $0.workoutType) }
        }
        return WeekPlan.progress(planned: plannedSessions, doneByDay: doneByDay)
    }

    private var weekSummary: String {
        let progress = weekProgress
        if progress.total > 0 { return "\(progress.done) of \(progress.total) planned sessions done" }
        let count = weekdayOrder.reduce(0) { $0 + workoutsOn(date(for: $1.0)).count }
        return count == 0 ? "No sessions yet. Tap Edit plan to set your week." : "\(count) workout\(count == 1 ? "" : "s") this week"
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This week").apexLabel()
                Spacer()
                Button {
                    showingScheduleEditor = true
                } label: {
                    Label("Edit plan", systemImage: "pencil.circle")
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.accent)
                }
                .buttonStyle(PressableStyle())
            }

            HStack(spacing: 4) {
                ForEach(weekdayOrder, id: \.0) { dayNum, dayName in
                    dayChip(dayNum: dayNum, dayName: dayName)
                }
            }

            Text(weekSummary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ApexColor.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func dayChip(dayNum: Int, dayName: String) -> some View {
        let dayDate = date(for: dayNum)
        let isToday = Calendar.current.isDateInToday(dayDate)
        let isPast = dayDate < Date() && !isToday
        let plan = planned(on: dayNum)
        let actual = workoutsOn(dayDate)

        return Button { selectedDay = DayItem(id: dayNum) } label: {
            VStack(spacing: 6) {
                Text(String(dayName.prefix(1)))
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(isToday ? ApexColor.accent : ApexColor.textSecondary)
                Text("\(Calendar.current.component(.day, from: dayDate))")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(ApexColor.textPrimary)
                dayMark(plan: plan, actual: actual, isPast: isPast)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isToday ? ApexColor.accent.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(dayName) \(Calendar.current.component(.day, from: dayDate))")
    }

    @ViewBuilder
    private func dayMark(plan: [WorkoutScheduleEntry], actual: [WorkoutSession], isPast: Bool) -> some View {
        if let first = actual.first {
            let color = Color.workoutTypeColor(first.type)
            Image(systemName: first.type.systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.18))
                .clipShape(Circle())
        } else if let first = plan.first, isPast {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ApexColor.danger)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(ApexColor.danger.opacity(0.6), lineWidth: 1.5))
                .accessibilityLabel("Missed \(first.workoutType.rawValue)")
        } else if let first = plan.first {
            Image(systemName: first.workoutType.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ApexColor.textSecondary)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).foregroundStyle(ApexColor.textSecondary.opacity(0.6)))
        } else {
            Circle()
                .fill(ApexColor.textSecondary.opacity(0.25))
                .frame(width: 6, height: 6)
                .frame(width: 30, height: 30)
        }
    }

    private func dayDetailSheet(_ dayNum: Int) -> some View {
        let dayDate = date(for: dayNum)
        let plan = planned(on: dayNum)
        let actual = workoutsOn(dayDate)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if plan.isEmpty && actual.isEmpty {
                        Text("Rest day. Nothing planned or logged.")
                            .font(.subheadline)
                            .foregroundStyle(ApexColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }
                    if !plan.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Planned").apexLabel()
                            HStack(spacing: 6) {
                                ForEach(plan, id: \.workoutTypeRaw) { typePill(type: $0.workoutType, filled: false) }
                            }
                        }
                    }
                    if !actual.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Done").apexLabel()
                            ForEach(actual) { workoutRow($0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(ApexColor.background)
            .navigationTitle(dayDate.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func statusIcon(planned: [WorkoutScheduleEntry], actual: [WorkoutSession], isPast: Bool) -> some View {
        let plannedTypes = Set(planned.map { $0.workoutType })
        let actualTypes = Set(actual.map { $0.type })

        if planned.isEmpty && actual.isEmpty {
            Image(systemName: "minus").font(.caption).foregroundStyle(ApexColor.textSecondary.opacity(0.3))
        } else if actual.isEmpty && !planned.isEmpty && isPast {
            Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(ApexColor.danger)
        } else if !actual.isEmpty && plannedTypes.isSubset(of: actualTypes) {
            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(ApexColor.success)
        } else if !actual.isEmpty {
            Image(systemName: "checkmark.circle").font(.caption).foregroundStyle(ApexColor.warning)
        } else {
            Image(systemName: "circle.dotted").font(.caption).foregroundStyle(ApexColor.textSecondary.opacity(0.4))
        }
    }

    private func typePill(type: WorkoutType, filled: Bool) -> some View {
        let color = Color.workoutTypeColor(type)
        return HStack(spacing: 3) {
            Image(systemName: type.systemImage).font(.system(size: 8))
            Text(type.rawValue).font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(filled ? color.opacity(0.2) : color.opacity(0.08))
        .foregroundStyle(color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(filled ? 0.4 : 0.2), lineWidth: 0.5))
    }

    // MARK: - History

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent").apexLabel()
                Spacer()
                if workouts.count > 4 {
                    Button("See all \(workouts.count)") { showingAllHistory = true }
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.accent)
                        .buttonStyle(PressableStyle())
                }
            }

            ForEach(workouts.prefix(4)) { workout in
                workoutRow(workout)
            }
        }
    }

    private var allHistorySheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(workouts) { workoutRow($0) }
                }
                .padding()
            }
            .background(ApexColor.background)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func workoutRow(_ workout: WorkoutSession) -> some View {
        let color = Color.workoutTypeColor(workout.type)
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: workout.type.systemImage)
                    .font(.headline)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(workout.type.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(ApexColor.textPrimary)
                    if workout.importedFromHealthKit {
                        Label("Watch", systemImage: "applewatch")
                            .font(.caption2)
                            .foregroundStyle(ApexColor.textSecondary)
                    }
                }
                Text("\(workout.durationFormatted) · \(workout.date.dayAndMonth)")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)

                // Tennis score if available
                if let tennis = workout.tennisDetails, (tennis.setsWon + tennis.setsLost) > 0 {
                    Text(tennis.scoreFormatted)
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.tennis)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if workout.caloriesBurned > 0 {
                    Text("\(workout.caloriesBurned) kcal")
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.danger)
                }
                XPBadge(amount: workout.xpEarned)
            }
        }
        .padding(14)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            Button(role: .destructive) {
                context.delete(workout)
            } label: {
                Label("Delete Workout", systemImage: "trash")
            }
        }
    }

}

// MARK: - WorkoutType: Identifiable for sheet

extension WorkoutType: Identifiable {
    public var id: String { rawValue }
}
