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

                        // Quick Add
                        quickAddSection
                            .padding(.horizontal)

                        // Muscle Recovery
                        if workouts.contains(where: { $0.type == .gym }) {
                            muscleRecoverySection
                                .padding(.horizontal)
                        }

                        // Weekly Schedule
                        weeklyScheduleSection
                            .padding(.horizontal)

                        // History
                        if workouts.isEmpty {
                            EmptyStateView(
                                icon: "dumbbell",
                                title: "No Workouts Yet",
                                subtitle: "Log your first workout to start earning XP"
                            )
                            .padding(.top, 40)
                        } else {
                            workoutHistorySection
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

    private var muscleRecoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Muscle Recovery")
                .apexLabel()

            if let suggestion = MuscleGroupTracker.suggestion(from: muscleStatuses) {
                suggestionBanner(suggestion)
            }

            VStack(spacing: 0) {
                ForEach(muscleStatuses) { status in
                    muscleStatusRow(status)
                    if status.id != muscleStatuses.last?.id {
                        Divider().background(ApexColor.cardBg2).padding(.leading, 60)
                    }
                }
            }
            .background(ApexColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func suggestionBanner(_ status: MuscleGroupTracker.Status) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.muscleGroup.systemImage)
                .foregroundStyle(status.recoveryLevel.color)
            Text("Haven't trained \(status.muscleGroup.rawValue) in \(status.daysSinceTrained.map { "\($0) days" } ?? "a while") — consider it today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ApexColor.textPrimary)
            Spacer()
        }
        .padding(12)
        .background(status.recoveryLevel.color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(status.recoveryLevel.color.opacity(0.3), lineWidth: 1))
    }

    private func muscleStatusRow(_ status: MuscleGroupTracker.Status) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(status.recoveryLevel.color.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: status.muscleGroup.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(status.recoveryLevel.color)
            }

            Text(status.muscleGroup.rawValue)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ApexColor.textPrimary)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(status.gapDescription)
                    .font(.caption.bold())
                    .foregroundStyle(status.recoveryLevel.color)
                Text(status.recoveryLevel.label)
                    .font(.caption2)
                    .foregroundStyle(ApexColor.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    private var weeklyScheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This Week")
                    .apexLabel()
                Spacer()
                Button {
                    showingScheduleEditor = true
                } label: {
                    Label("Edit Plan", systemImage: "pencil.circle")
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.accent)
                }
            }

            VStack(spacing: 0) {
                ForEach(weekdayOrder, id: \.0) { dayNum, dayName in
                    weekDayRow(dayNum: dayNum, dayName: dayName)
                }
            }
            .background(ApexColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func weekDayRow(dayNum: Int, dayName: String) -> some View {
        let dayDate = date(for: dayNum)
        let cal = Calendar.current
        let isToday = cal.isDateInToday(dayDate)
        let isPast = dayDate < Date() && !isToday
        let planned = scheduleEntries.filter { $0.dayOfWeek == dayNum && $0.isEnabled }
        let actual = workoutsOn(dayDate)

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Day label
                VStack(spacing: 1) {
                    Text(dayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isToday ? ApexColor.accent : ApexColor.textSecondary)
                    Text("\(cal.component(.day, from: dayDate))")
                        .font(.caption.bold())
                        .foregroundStyle(isToday ? ApexColor.accent : ApexColor.textPrimary)
                }
                .frame(width: 34)

                // Status icon
                statusIcon(planned: planned, actual: actual, isPast: isPast)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    if planned.isEmpty && actual.isEmpty {
                        Text("Rest day")
                            .font(.caption)
                            .foregroundStyle(ApexColor.textSecondary.opacity(0.5))
                    } else {
                        if !planned.isEmpty {
                            HStack(spacing: 4) {
                                Text("Plan:")
                                    .font(.caption2)
                                    .foregroundStyle(ApexColor.textSecondary)
                                ForEach(planned, id: \.dayOfWeek) { entry in
                                    typePill(type: entry.workoutType, filled: false)
                                }
                            }
                        }
                        if !actual.isEmpty {
                            HStack(spacing: 4) {
                                Text("Done:")
                                    .font(.caption2)
                                    .foregroundStyle(ApexColor.textSecondary)
                                ForEach(actual) { session in
                                    typePill(type: session.type, filled: true)
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isToday ? ApexColor.accent.opacity(0.07) : Color.clear)

            if dayNum != weekdayOrder.last?.0 {
                Divider().background(ApexColor.cardBg2).padding(.leading, 60)
            }
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

    private var workoutHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .apexLabel()

            ForEach(workouts) { workout in
                workoutRow(workout)
            }
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
