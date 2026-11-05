import SwiftUI
import SwiftData

struct GymWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    var gamification: GamificationService
    var prefillSession: WorkoutSession? = nil

    @State private var date = Date()
    @State private var durationMinutes = 60
    @State private var averageHeartRate = 0
    @State private var notes = ""
    @State private var exercises: [GymExercise] = []
    @State private var showingExercisePicker = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Header
                        HStack {
                            Image(systemName: "dumbbell.fill")
                                .font(.title2)
                                .foregroundStyle(ApexColor.accent)
                            Text("Gym Workout")
                                .font(.headline)
                                .foregroundStyle(ApexColor.textPrimary)
                            Spacer()
                            XPBadge(amount: XPValues.logGymWorkout)
                        }
                        .padding()
                        .background(ApexColor.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)

                        // Session Details
                        ApexSectionCard(title: "Session Details", systemImage: "clock.fill", accentColor: ApexColor.accentCyan) {
                            DatePicker("Date & Time", selection: $date)
                                .colorScheme(.dark)
                            Divider().background(ApexColor.cardBg2)
                            Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 15...240, step: 5)
                                .foregroundStyle(ApexColor.textPrimary)
                        }
                        .padding(.horizontal)

                        // Exercises
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Exercises", systemImage: "list.bullet.clipboard.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ApexColor.accent)
                                Spacer()
                                Button {
                                    showingExercisePicker = true
                                } label: {
                                    Label("Add", systemImage: "plus.circle.fill")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(ApexColor.accent)
                                }
                            }

                            if exercises.isEmpty {
                                Text("Tap Add to pick exercises from the database")
                                    .font(.subheadline)
                                    .foregroundStyle(ApexColor.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 12)
                            } else {
                                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                                    exerciseRow(exercise: exercise, index: index)
                                }
                            }
                        }
                        .apexCard()
                        .padding(.horizontal)

                        // Notes
                        ApexSectionCard(title: "Notes", systemImage: "note.text", accentColor: ApexColor.textSecondary) {
                            TextField("Any notes about this session?", text: $notes, axis: .vertical)
                                .foregroundStyle(ApexColor.textPrimary)
                                .lineLimit(2...5)
                        }
                        .padding(.horizontal)

                        Spacer(minLength: 24)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .onAppear {
                if let s = prefillSession {
                    date = s.date
                    durationMinutes = s.durationMinutes
                    averageHeartRate = s.averageHeartRate
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ApexColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") { save() }
                        .font(.headline)
                        .foregroundStyle(ApexColor.accent)
                        .disabled(isSaving || exercises.isEmpty)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { info in
                    let ex = GymExercise(
                        name: info.name,
                        muscleGroup: info.muscleGroup,
                        sets: 3,
                        reps: 10,
                        weightKg: 0,
                        videoURL: info.videoURL,
                        order: exercises.count
                    )
                    exercises.append(ex)
                }
            }
        }
    }

    // MARK: - Exercise Row

    private func exerciseRow(exercise: GymExercise, index: Int) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(ApexColor.textPrimary)
                    Text(exercise.muscleGroup.rawValue)
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                }
                Spacer()

                // YouTube link
                if let url = URL(string: exercise.videoURL), exercise.videoURL.isNotEmpty {
                    Link(destination: url) {
                        Label("Watch", systemImage: "play.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(ApexColor.accent)
                    }
                }

                // Delete
                Button {
                    exercises.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(ApexColor.danger)
                }
            }

            HStack(spacing: 12) {
                exerciseField(label: "Sets", value: Binding(
                    get: { exercise.sets },
                    set: { exercises[index].sets = $0 }
                ), range: 1...20)

                exerciseField(label: "Reps", value: Binding(
                    get: { exercise.reps },
                    set: { exercises[index].reps = $0 }
                ), range: 1...50)

                weightField(exercise: exercise, index: index)
            }

            if index < exercises.count - 1 {
                Divider().background(ApexColor.cardBg2)
            }
        }
    }

    private func exerciseField(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(ApexColor.textSecondary)
            HStack(spacing: 8) {
                Button { if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 } } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(ApexColor.textSecondary)
                }
                Text("\(value.wrappedValue)")
                    .font(.subheadline.bold())
                    .foregroundStyle(ApexColor.textPrimary)
                    .frame(minWidth: 24)
                Button { if value.wrappedValue < range.upperBound { value.wrappedValue += 1 } } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(ApexColor.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(ApexColor.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func weightField(exercise: GymExercise, index: Int) -> some View {
        VStack(spacing: 4) {
            Text("Weight")
                .font(.caption2)
                .foregroundStyle(ApexColor.textSecondary)
            HStack(spacing: 4) {
                TextField("0", value: Binding(
                    get: { exercises[index].weightKg },
                    set: { exercises[index].weightKg = $0 }
                ), format: .number)
                .keyboardType(.decimalPad)
                .font(.subheadline.bold())
                .foregroundStyle(ApexColor.textPrimary)
                .multilineTextAlignment(.center)
                .frame(width: 52)
                Text("kg")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(ApexColor.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Save

    private func save() {
        isSaving = true
        let session: WorkoutSession
        if let existing = prefillSession {
            session = existing
            session.date = date
            session.durationMinutes = durationMinutes
            session.averageHeartRate = averageHeartRate
            session.notes = notes
        } else {
            session = WorkoutSession(
                date: date,
                type: .gym,
                durationMinutes: durationMinutes,
                averageHeartRate: averageHeartRate,
                notes: notes
            )
            context.insert(session)
        }
        session.gymExercises = exercises
        exercises.forEach { context.insert($0) }

        if let profile, session.xpEarned == 0 {
            gamification.processWorkout(session, profile: profile, context: context)
        }
        dismiss()
    }
}
