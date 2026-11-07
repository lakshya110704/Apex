import SwiftUI
import SwiftData

struct EveningCheckInView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query(sort: \FocusSession.startTime, order: .reverse) private var focusSessions: [FocusSession]

    var claude: ClaudeService
    var healthKit: HealthKitService

    @State private var step = 0
    @State private var moodRating = 3
    @State private var accomplishments = ""
    @State private var isGenerating = false
    @State private var aiSummary = ""
    @State private var tomorrowPriority = ""

    private var profile: UserProfile? { profiles.first }
    private var firstName: String {
        let first = profile?.name.components(separatedBy: " ").first ?? ""
        return first.isEmpty ? "there" : first
    }

    private var todayFocusMinutes: Int {
        focusSessions.filter { $0.date.isToday }.reduce(0) { $0 + $1.durationMinutes }
    }

    var body: some View {
        ZStack {
            ApexColor.background.ignoresSafeArea()

            TabView(selection: $step) {
                moodStep.tag(0)
                accomplishmentsStep.tag(1)
                summaryStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)
        }
    }

    // MARK: - Step 0: Mood

    private var moodStep: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("Evening Wrap-up")
                    .font(.caption.bold())
                    .foregroundStyle(ApexColor.accent)
                    .tracking(2)
                Text("How was today,\n\(firstName)?")
                    .font(.largeTitle.bold())
                    .foregroundStyle(ApexColor.textPrimary)
                    .multilineTextAlignment(.center)

                if todayFocusMinutes > 0 {
                    Text("You logged \(todayFocusMinutes)m of focus time today.")
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.accentCyan)
                }
            }

            // Mood selector
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { rating in
                    Button { moodRating = rating } label: {
                        VStack(spacing: 6) {
                            Text(moodEmoji(rating))
                                .font(.system(size: moodRating == rating ? 44 : 32))
                            Text(moodLabel(rating))
                                .font(.caption2.bold())
                                .foregroundStyle(moodRating == rating ? ApexColor.textPrimary : ApexColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(moodRating == rating ? ApexColor.accent.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                            moodRating == rating ? ApexColor.accent : Color.clear, lineWidth: 1.5
                        ))
                    }
                    .animation(.spring(response: 0.3), value: moodRating)
                }
            }
            .padding(.horizontal)

            Spacer()

            nextButton("Next") { step = 1 }
                .padding(.horizontal)
                .padding(.bottom, 40)
        }
    }

    // MARK: - Step 1: Accomplishments

    private var accomplishmentsStep: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("What did you get done?")
                    .font(.title2.bold())
                    .foregroundStyle(ApexColor.textPrimary)
                Text("Brain-dump everything — work, workouts, learning, anything.")
                    .font(.subheadline)
                    .foregroundStyle(ApexColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            TextEditor(text: $accomplishments)
                .frame(minHeight: 180)
                .padding(14)
                .background(ApexColor.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(ApexColor.textPrimary)
                .font(.body)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if accomplishments.isEmpty {
                        Text("e.g. Finished the new feature, went to gym, read 30 pages...")
                            .font(.body)
                            .foregroundStyle(ApexColor.textSecondary.opacity(0.5))
                            .padding(18)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal)

            Spacer()

            nextButton(accomplishments.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "Get AI Summary") {
                Task { await generateSummary() }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Step 2: Summary

    private var summaryStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                if isGenerating {
                    VStack(spacing: 16) {
                        ProgressView().tint(ApexColor.accent).scaleEffect(1.4)
                        Text("Apex Coach is reviewing your day...")
                            .font(.subheadline)
                            .foregroundStyle(ApexColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else {
                    VStack(spacing: 8) {
                        Text("Day Complete 🎯")
                            .font(.title2.bold())
                            .foregroundStyle(ApexColor.textPrimary)
                    }

                    if !aiSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Today's Wins", systemImage: "checkmark.seal.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(ApexColor.success)
                            Text(aiSummary)
                                .font(.subheadline)
                                .foregroundStyle(ApexColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .apexCard()
                        .padding(.horizontal)
                    }

                    if !tomorrowPriority.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Tomorrow's #1 Priority", systemImage: "sunrise.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(ApexColor.accent)
                            Text(tomorrowPriority)
                                .font(.subheadline)
                                .foregroundStyle(ApexColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .apexCard()
                        .padding(.horizontal)
                    }

                    // Recovery preview
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Tonight", systemImage: "moon.stars.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.purple)
                        Text("Your HRV is \(Int(healthKit.hrv))ms. Aim for \(Int(healthKit.hrv) > 50 ? "7.5–8.5h" : "8–9h") of sleep to recover well.")
                            .font(.subheadline)
                            .foregroundStyle(ApexColor.textPrimary)
                    }
                    .apexCard()
                    .padding(.horizontal)

                    Button { saveAndDismiss() } label: {
                        Text("See you tomorrow 👋")
                            .font(.headline)
                            .foregroundStyle(ApexColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(ApexColor.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Helpers

    private func nextButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .foregroundStyle(ApexColor.onAccent)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(ApexColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func moodEmoji(_ rating: Int) -> String {
        ["😴", "😐", "🙂", "😊", "🔥"][rating - 1]
    }

    private func moodLabel(_ rating: Int) -> String {
        ["Rough", "Meh", "Good", "Great", "Epic"][rating - 1]
    }

    private func generateSummary() async {
        step = 2
        guard !claude.apiKey.isEmpty, !accomplishments.trimmingCharacters(in: .whitespaces).isEmpty else {
            aiSummary = ""
            tomorrowPriority = "Rest, recover, and show up strong tomorrow."
            return
        }

        isGenerating = true
        let prompt = """
        The user completed their day with mood \(moodRating)/5. They accomplished:
        \(accomplishments)

        Their health data: Sleep \(String(format: "%.1f", healthKit.sleepHoursLast))h, HRV \(Int(healthKit.hrv))ms, active calories \(Int(healthKit.todayActiveCalories)).

        Respond ONLY with valid JSON:
        {"summary":"<2-3 sentences celebrating their wins and framing the day positively>","priority":"<one specific, actionable thing to prioritize tomorrow based on what they shared>"}
        """

        let context = ApexContext(
            userName: profile?.name ?? "Athlete",
            sleepHours: healthKit.sleepHoursLast,
            hrv: healthKit.hrv,
            todayActiveCalories: healthKit.todayActiveCalories
        )
        do {
            let msgs = [ChatMessage(role: .user, content: prompt)]
            let response = try await claude.chat(messages: msgs, context: context)
            let cleaned = response
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = cleaned.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                aiSummary = json["summary"] as? String ?? ""
                tomorrowPriority = json["priority"] as? String ?? ""
            }
        } catch {
            aiSummary = "You put in the work today. Every rep, every hour of focus, every good decision compounds."
            tomorrowPriority = "Show up tomorrow with the same energy."
        }
        isGenerating = false
    }

    private func saveAndDismiss() {
        let checkIn = EveningCheckIn(date: Date())
        checkIn.moodRating = moodRating
        checkIn.accomplishments = accomplishments
        checkIn.aiSummary = aiSummary
        checkIn.tomorrowPriority = tomorrowPriority
        checkIn.isComplete = true
        context.insert(checkIn)
        dismiss()
    }
}
