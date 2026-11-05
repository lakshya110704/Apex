import SwiftUI
import SwiftData

struct MorningCheckInView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query private var projects: [Project]

    var healthKit: HealthKitService
    var claude: ClaudeService

    @State private var step = 0
    @State private var energyLevel = 0       // 0 = not selected
    @State private var selectedProjects: Set<PersistentIdentifier> = []
    @State private var customNote = ""
    @State private var motivation = ""
    @State private var isGenerating = false
    @State private var showAddProject = false
    @State private var newProjectName = ""
    @State private var newProjectCategory = ProjectCategory.startup

    private var profile: UserProfile? { profiles.first }
    private let totalSteps = 5

    private var sleepScore: Int {
        MorningCheckIn.sleepScore(hours: healthKit.sleepHoursLast, hrv: healthKit.hrv)
    }
    private var recoveryRating: String {
        MorningCheckIn.recoveryRating(score: sleepScore)
    }
    private var activeProjects: [Project] { projects.filter(\.isActive) }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [ApexColor.deepPurple, ApexColor.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                progressDots
                    .padding(.top, 20)

                // Step content
                TabView(selection: $step) {
                    greetingStep.tag(0)
                    sleepStep.tag(1)
                    energyStep.tag(2)
                    projectsStep.tag(3)
                    motivationStep.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.4), value: step)

                // Continue button
                continueButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAddProject) {
            addProjectSheet
        }
        .onAppear {
            Task { await healthKit.fetchAllTodayData() }
        }
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? ApexColor.accent : ApexColor.cardBg2)
                    .frame(width: i == step ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: step)
            }
        }
    }

    // MARK: - Step 0: Greeting

    private var greetingStep: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Text(timeEmoji)
                    .font(.system(size: 72))

                VStack(spacing: 8) {
                    Text(greetingLine)
                        .font(.title2)
                        .foregroundStyle(ApexColor.textSecondary)
                    Text(profile?.name.isEmpty == false ? profile!.name : "Athlete")
                        .font(.system(size: 48, weight: .black))
                        .foregroundStyle(ApexColor.textPrimary)
                }

                Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.subheadline)
                    .foregroundStyle(ApexColor.textSecondary)
            }

            VStack(spacing: 12) {
                statRow(icon: "moon.zzz.fill", color: ApexColor.accent,
                        label: "Sleep", value: sleepFormatted)
                statRow(icon: "heart.fill", color: ApexColor.danger,
                        label: "Resting HR", value: "\(Int(healthKit.restingHeartRate)) bpm")
                statRow(icon: "waveform.path.ecg", color: ApexColor.accentCyan,
                        label: "HRV", value: "\(Int(healthKit.hrv)) ms")
            }
            .padding(20)
            .background(ApexColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Step 1: Sleep Score

    private var sleepStep: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Text("Last Night's Sleep")
                    .font(.title3.bold())
                    .foregroundStyle(ApexColor.textSecondary)
                Text("Recovery Score")
                    .font(.headline)
                    .foregroundStyle(ApexColor.textPrimary)
            }

            // Score ring
            ZStack {
                RingView(progress: Double(sleepScore) / 100, color: scoreColor, lineWidth: 18, size: 180)
                VStack(spacing: 4) {
                    Text("\(sleepScore)")
                        .font(.system(size: 64, weight: .black))
                        .foregroundStyle(scoreColor)
                    Text(recoveryRating.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.textSecondary)
                        .tracking(2)
                }
            }

            // Sleep breakdown
            HStack(spacing: 20) {
                sleepStat(label: "Duration", value: sleepFormatted, color: ApexColor.accent)
                sleepStat(label: "HRV", value: "\(Int(healthKit.hrv))ms", color: ApexColor.accentCyan)
                sleepStat(label: "RHR", value: "\(Int(healthKit.restingHeartRate))bpm", color: ApexColor.danger)
            }
            .padding(16)
            .background(ApexColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(sleepInsight)
                .font(.subheadline)
                .foregroundStyle(ApexColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Step 2: Energy

    private var energyStep: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Text("How are you feeling?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(ApexColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Be honest — your plan adjusts to this")
                    .font(.subheadline)
                    .foregroundStyle(ApexColor.textSecondary)
            }

            VStack(spacing: 12) {
                ForEach(energyOptions, id: \.level) { option in
                    energyButton(option)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func energyButton(_ option: (level: Int, emoji: String, label: String, sublabel: String)) -> some View {
        let isSelected = energyLevel == option.level
        return Button { energyLevel = option.level } label: {
            HStack(spacing: 16) {
                Text(option.emoji)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.subheadline.bold())
                        .foregroundStyle(ApexColor.textPrimary)
                    Text(option.sublabel)
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ApexColor.accent)
                }
            }
            .padding(16)
            .background(isSelected ? ApexColor.accent.opacity(0.15) : ApexColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? ApexColor.accent : Color.clear, lineWidth: 1.5))
        }
    }

    private var energyOptions: [(level: Int, emoji: String, label: String, sublabel: String)] {[
        (5, "🔥", "On fire",    "Full send today"),
        (4, "😊", "Good",       "Feeling solid"),
        (3, "🙂", "Okay",       "Average start"),
        (2, "😐", "Low",        "Bit sluggish"),
        (1, "😴", "Exhausted",  "Need an easy day"),
    ]}

    // MARK: - Step 3: Projects

    private var projectsStep: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("What are you building?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(ApexColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Pick what you're focusing on today")
                    .font(.subheadline)
                    .foregroundStyle(ApexColor.textSecondary)
            }

            ScrollView {
                VStack(spacing: 10) {
                    if activeProjects.isEmpty {
                        Text("No projects yet — add one below")
                            .font(.subheadline)
                            .foregroundStyle(ApexColor.textSecondary)
                            .padding()
                    } else {
                        ForEach(activeProjects) { project in
                            projectChip(project)
                        }
                    }

                    Button {
                        showAddProject = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Project")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(ApexColor.accent)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(ApexColor.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(ApexColor.accent.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            .frame(maxHeight: 340)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func projectChip(_ project: Project) -> some View {
        let isSelected = selectedProjects.contains(project.persistentModelID)
        let color = projectColor(project.category)
        return Button {
            if isSelected { selectedProjects.remove(project.persistentModelID) }
            else { selectedProjects.insert(project.persistentModelID) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(color.opacity(0.2)).frame(width: 40, height: 40)
                    Image(systemName: project.category.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(ApexColor.textPrimary)
                    Text(project.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? color : ApexColor.textSecondary)
            }
            .padding(14)
            .background(isSelected ? color.opacity(0.1) : ApexColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? color : Color.clear, lineWidth: 1.5))
        }
    }

    // MARK: - Step 4: Motivation

    private var motivationStep: some View {
        VStack(spacing: 28) {
            Spacer()

            if isGenerating {
                VStack(spacing: 20) {
                    ProgressView().tint(ApexColor.accent).scaleEffect(1.5)
                    Text("Apex Coach is reading your data...")
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.textSecondary)
                }
            } else {
                VStack(spacing: 20) {
                    Text("⚡️")
                        .font(.system(size: 56))

                    Text(motivation.isEmpty ? "You're ready for today." : motivation)
                        .font(.title3.bold())
                        .foregroundStyle(ApexColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if !selectedProjects.isEmpty {
                        let focusNames = activeProjects
                            .filter { selectedProjects.contains($0.persistentModelID) }
                            .map(\.name)
                        VStack(spacing: 8) {
                            Text("Today's focus")
                                .font(.caption.bold())
                                .foregroundStyle(ApexColor.textSecondary)
                                .tracking(1)
                            ForEach(focusNames, id: \.self) { name in
                                Label(name, systemImage: "arrow.right.circle.fill")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(ApexColor.accent)
                            }
                        }
                        .padding(16)
                        .background(ApexColor.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .task { await generateMotivation() }
    }

    // MARK: - Add Project Sheet

    private var addProjectSheet: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()
                VStack(spacing: 20) {
                    TextField("Project name", text: $newProjectName)
                        .font(.headline)
                        .foregroundStyle(ApexColor.textPrimary)
                        .padding()
                        .background(ApexColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(ProjectCategory.allCases, id: \.self) { cat in
                            Button { newProjectCategory = cat } label: {
                                HStack {
                                    Image(systemName: cat.systemImage)
                                    Text(cat.rawValue)
                                        .font(.caption.bold())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .foregroundStyle(newProjectCategory == cat ? ApexColor.background : ApexColor.textPrimary)
                                .background(newProjectCategory == cat ? ApexColor.accent : ApexColor.cardBg)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddProject = false }
                        .foregroundStyle(ApexColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard newProjectName.isNotEmpty else { return }
                        let p = Project(name: newProjectName, category: newProjectCategory)
                        context.insert(p)
                        selectedProjects.insert(p.persistentModelID)
                        newProjectName = ""
                        showAddProject = false
                    }
                    .font(.headline)
                    .foregroundStyle(ApexColor.accent)
                    .disabled(newProjectName.isEmpty)
                }
            }
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button { advance() } label: {
            HStack {
                Text(buttonLabel)
                    .font(.headline)
                if step < totalSteps - 1 {
                    Image(systemName: "arrow.right")
                        .font(.headline)
                }
            }
            .foregroundStyle(ApexColor.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(canAdvance ? ApexColor.accent : ApexColor.cardBg2)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .animation(.easeInOut(duration: 0.2), value: canAdvance)
        }
        .disabled(!canAdvance)
    }

    private var buttonLabel: String {
        switch step {
        case 0: return "Let's go"
        case 1: return "Got it"
        case 2: return "Set my energy"
        case 3: return "Lock in focus"
        case 4: return "Enter Apex →"
        default: return "Continue"
        }
    }

    private var canAdvance: Bool {
        if step == 2 { return energyLevel > 0 }
        if step == 4 { return !isGenerating }
        return true
    }

    private func advance() {
        if step < totalSteps - 1 {
            withAnimation { step += 1 }
        } else {
            saveCheckIn()
            dismiss()
        }
    }

    // MARK: - Helpers

    private var timeEmoji: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "🌅"
        case 12..<17: return "☀️"
        default: return "🌙"
        }
    }

    private var greetingLine: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning,"
        case 12..<17: return "Good afternoon,"
        default: return "Good evening,"
        }
    }

    private var sleepFormatted: String {
        let h = Int(healthKit.sleepHoursLast)
        let m = Int((healthKit.sleepHoursLast - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    private var scoreColor: Color {
        switch sleepScore {
        case 75...: return ApexColor.success
        case 50..<75: return ApexColor.warning
        default: return ApexColor.danger
        }
    }

    private var sleepInsight: String {
        switch recoveryRating {
        case "Peak":     return "Your body is fully charged. Push hard today — you earned it."
        case "High":     return "Solid recovery. Good intensity is on the table today."
        case "Moderate": return "Decent recovery. Keep workout intensity moderate."
        default:         return "Your body needs care today. Keep it light and focus on your projects."
        }
    }

    private func sleepStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(ApexColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func statRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            Text(label).font(.subheadline).foregroundStyle(ApexColor.textSecondary)
            Spacer()
            Text(value).font(.subheadline.bold()).foregroundStyle(ApexColor.textPrimary)
        }
    }

    private func projectColor(_ category: ProjectCategory) -> Color {
        switch category {
        case .startup:  return ApexColor.accent
        case .study:    return ApexColor.accentCyan
        case .fitness:  return ApexColor.tennis
        case .personal: return ApexColor.warning
        case .work:     return ApexColor.success
        case .creative: return ApexColor.danger
        }
    }

    // MARK: - AI Motivation

    private func generateMotivation() async {
        guard motivation.isEmpty else { return }
        guard !claude.apiKey.isEmpty else {
            motivation = motivationFallback()
            return
        }
        isGenerating = true
        let focusNames = activeProjects
            .filter { selectedProjects.contains($0.persistentModelID) }
            .map(\.name)
        let energyLabel = energyOptions.first(where: { $0.level == energyLevel })?.label ?? "okay"
        let prompt = """
        Give \(profile?.name ?? "this athlete") a punchy 2-3 sentence morning motivation.
        Recovery: \(recoveryRating) (score \(sleepScore)/100). Sleep: \(sleepFormatted). HRV: \(Int(healthKit.hrv))ms.
        Energy: \(energyLabel). Today's focus: \(focusNames.joined(separator: ", ")).
        Be direct, personal, and fire them up. No fluff. Reference their actual data.
        """
        do {
            let ctx = ApexContext(
                userName: profile?.name ?? "Athlete",
                sleepHours: healthKit.sleepHoursLast,
                restingHR: healthKit.restingHeartRate,
                hrv: healthKit.hrv
            )
            let response = try await claude.chat(
                messages: [ChatMessage(role: .user, content: prompt)],
                context: ctx
            )
            motivation = response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            motivation = motivationFallback()
        }
        isGenerating = false
    }

    private func motivationFallback() -> String {
        switch recoveryRating {
        case "Peak":     return "HRV at \(Int(healthKit.hrv))ms — your body is locked and loaded. Don't waste this window."
        case "High":     return "Solid recovery. Your consistency is building into something real. Keep stacking days."
        case "Moderate": return "Not your peak, but showing up matters more than feeling ready. Get after it."
        default:         return "Even on low days, the work still counts. Small actions, big compounding."
        }
    }

    // MARK: - Save

    private func saveCheckIn() {
        let checkIn = MorningCheckIn()
        checkIn.energyLevel = energyLevel
        checkIn.sleepScore = sleepScore
        checkIn.recoveryRating = recoveryRating
        checkIn.aiMotivation = motivation
        checkIn.isComplete = true
        context.insert(checkIn)

        // Mark selected projects as focused today
        activeProjects
            .filter { selectedProjects.contains($0.persistentModelID) }
            .forEach {
                $0.lastFocusedAt = Date()
                $0.totalFocusDays += 1
            }
    }
}
