import SwiftUI
import SwiftData

struct TennisLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    var gamification: GamificationService
    var prefillSession: WorkoutSession? = nil  // imported from Watch

    // Session fields
    @State private var date = Date()
    @State private var durationMinutes = 60
    @State private var averageHeartRate = 0
    @State private var caloriesBurned = 0

    // Tennis fields
    @State private var court = ""
    @State private var opponent = ""
    @State private var setsWon = 0
    @State private var setsLost = 0
    @State private var gamesWon = 0
    @State private var gamesLost = 0
    @State private var selectedDrills: Set<String> = []
    @State private var notes = ""

    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // Header XP info
                        HStack {
                            Image(systemName: "figure.tennis")
                                .font(.title2)
                                .foregroundStyle(ApexColor.tennis)
                            Text("Tennis Session")
                                .font(.headline)
                                .foregroundStyle(ApexColor.textPrimary)
                            Spacer()
                            XPBadge(amount: XPValues.logTennisSession)
                        }
                        .padding()
                        .background(ApexColor.tennis.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)

                        // Session Details
                        ApexSectionCard(title: "Session Details", systemImage: "clock.fill", accentColor: ApexColor.accentCyan) {
                            DatePicker("Date & Time", selection: $date)
                                .foregroundStyle(ApexColor.textPrimary)

                            Divider().background(ApexColor.cardBg2)

                            Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 15...360, step: 5)
                                .foregroundStyle(ApexColor.textPrimary)

                            Divider().background(ApexColor.cardBg2)

                            HStack {
                                Text("Avg HR")
                                    .foregroundStyle(ApexColor.textSecondary)
                                Spacer()
                                TextField("bpm", value: $averageHeartRate, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(ApexColor.textPrimary)
                                    .frame(width: 80)
                                Text("bpm")
                                    .foregroundStyle(ApexColor.textSecondary)
                            }
                        }
                        .padding(.horizontal)

                        // Location & Opponent
                        ApexSectionCard(title: "Match Info", systemImage: "sportscourt.fill", accentColor: ApexColor.tennis) {
                            TextField("Court / Location", text: $court)
                                .foregroundStyle(ApexColor.textPrimary)
                                .autocorrectionDisabled()
                            Divider().background(ApexColor.cardBg2)
                            TextField("Opponent (optional)", text: $opponent)
                                .foregroundStyle(ApexColor.textPrimary)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal)

                        // Score
                        ApexSectionCard(title: "Score", systemImage: "trophy.fill", accentColor: ApexColor.warning) {
                            HStack(spacing: 20) {
                                scoreColumn(label: "Sets Won", value: $setsWon)
                                Text("–")
                                    .font(.title2.bold())
                                    .foregroundStyle(ApexColor.textSecondary)
                                scoreColumn(label: "Sets Lost", value: $setsLost)
                            }

                            Divider().background(ApexColor.cardBg2)

                            HStack(spacing: 20) {
                                scoreColumn(label: "Games Won", value: $gamesWon)
                                Text("–")
                                    .font(.title2.bold())
                                    .foregroundStyle(ApexColor.textSecondary)
                                scoreColumn(label: "Games Lost", value: $gamesLost)
                            }
                        }
                        .padding(.horizontal)

                        // Drills
                        ApexSectionCard(title: "Drills Practiced", systemImage: "figure.tennis", accentColor: ApexColor.accent) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                                ForEach(TennisDrillDatabase.all, id: \.self) { drill in
                                    drillChip(drill)
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Notes
                        ApexSectionCard(title: "Notes", systemImage: "note.text", accentColor: ApexColor.textSecondary) {
                            TextField("How was the session?", text: $notes, axis: .vertical)
                                .foregroundStyle(ApexColor.textPrimary)
                                .lineLimit(3...6)
                        }
                        .padding(.horizontal)

                        Spacer(minLength: 24)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Log Tennis")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let s = prefillSession {
                    date = s.date
                    durationMinutes = s.durationMinutes
                    averageHeartRate = s.averageHeartRate
                    caloriesBurned = s.caloriesBurned
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
                        .foregroundStyle(ApexColor.tennis)
                        .disabled(isSaving)
                }
            }
        }
    }

    // MARK: - Subviews

    private func scoreColumn(label: String, value: Binding<Int>) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(ApexColor.textSecondary)
            HStack(spacing: 16) {
                Button { if value.wrappedValue > 0 { value.wrappedValue -= 1 } } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ApexColor.textSecondary)
                }
                Text("\(value.wrappedValue)")
                    .font(.title.bold())
                    .foregroundStyle(ApexColor.textPrimary)
                    .frame(minWidth: 32)
                Button { value.wrappedValue += 1 } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ApexColor.tennis)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func drillChip(_ drill: String) -> some View {
        let isSelected = selectedDrills.contains(drill)
        return Button {
            if isSelected { selectedDrills.remove(drill) }
            else { selectedDrills.insert(drill) }
        } label: {
            Text(drill)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? ApexColor.background : ApexColor.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(isSelected ? ApexColor.tennis : ApexColor.cardBg2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Save

    private func save() {
        isSaving = true

        // Re-use the already-imported session if this came from Watch import
        let session: WorkoutSession
        if let existing = prefillSession {
            session = existing
            session.date = date
            session.durationMinutes = durationMinutes
            session.averageHeartRate = averageHeartRate
            session.caloriesBurned = caloriesBurned
            session.notes = notes
        } else {
            session = WorkoutSession(
                date: date,
                type: .tennis,
                durationMinutes: durationMinutes,
                averageHeartRate: averageHeartRate,
                caloriesBurned: caloriesBurned,
                notes: notes
            )
            context.insert(session)
        }

        session.tennisDetails = TennisDetails(
            court: court,
            opponent: opponent,
            setsWon: setsWon,
            setsLost: setsLost,
            gamesWon: gamesWon,
            gamesLost: gamesLost,
            drillsPracticed: Array(selectedDrills)
        )

        if let profile, session.xpEarned == 0 {
            gamification.processWorkout(session, profile: profile, context: context)
        }
        dismiss()
    }
}
