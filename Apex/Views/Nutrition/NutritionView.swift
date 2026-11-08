import SwiftUI
import SwiftData

struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    var claude: ClaudeService
    var gamification: GamificationService

    @State private var showingCamera = false
    @State private var showingTextInput = false
    @State private var selectedDate = Date()

    private var mealsOnDate: [MealEntry] {
        meals.filter { $0.date.isSameDay(as: selectedDate) }
    }
    private var totalCalories: Int { mealsOnDate.reduce(0) { $0 + $1.estimatedCalories } }
    private var totalProtein: Double { mealsOnDate.reduce(0.0) { $0 + $1.proteinGrams } }
    private var totalCarbs: Double  { mealsOnDate.reduce(0.0) { $0 + $1.carbsGrams } }
    private var totalFat: Double    { mealsOnDate.reduce(0.0) { $0 + $1.fatGrams } }

    var body: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        dayStrip
                            .padding(.horizontal)

                        summaryHero
                            .padding(.horizontal)

                        logButtons
                            .padding(.horizontal)

                        if mealsOnDate.isEmpty {
                            EmptyStateView(
                                icon: "fork.knife",
                                title: "No Meals Logged",
                                subtitle: "Take a photo of your meal to get instant calorie estimates"
                            )
                        } else {
                            mealsListSection
                                .padding(.horizontal)
                        }

                        Text("Calories and macros are AI estimates, not medical or dietary advice.")
                            .font(.caption2)
                            .foregroundStyle(ApexColor.textSecondary)
                            .padding(.horizontal)

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Nutrition")
            .sheet(isPresented: $showingCamera) {
                MealCameraView(claude: claude) { entry in
                    context.insert(entry)
                    if let profile {
                        gamification.processMeal(entry, profile: profile, context: context)
                    }
                }
            }
            .sheet(isPresented: $showingTextInput) {
                MealTextInputView(claude: claude) { entry in
                    context.insert(entry)
                    if let profile {
                        gamification.processMeal(entry, profile: profile, context: context)
                    }
                }
            }
        }
    }

    // MARK: - Day strip

    private var lastSevenDays: [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date().startOfDay) }
    }

    private func calories(on day: Date) -> Int {
        meals.filter { $0.date.isSameDay(as: day) }.reduce(0) { $0 + $1.estimatedCalories }
    }

    private var dayStrip: some View {
        let days = lastSevenDays
        let peak = max(days.map { calories(on: $0) }.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last 7 days").apexLabel()
                Spacer()
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let kcal = calories(on: day)
                    let isSelected = day.isSameDay(as: selectedDate)
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedDate = day } } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                Capsule().fill(ApexColor.cardBg2).frame(width: 8, height: 44)
                                Capsule()
                                    .fill(isSelected ? ApexColor.accent : ApexColor.textSecondary.opacity(0.6))
                                    .frame(width: 8, height: kcal == 0 ? 0 : max(6, 44 * CGFloat(kcal) / CGFloat(peak)))
                            }
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(isSelected ? ApexColor.accent : ApexColor.textSecondary)
                            Text("\(Calendar.current.component(.day, from: day))")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(ApexColor.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isSelected ? ApexColor.accent.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(day.mediumDate), \(kcal) kilocalories")
                }
            }
        }
        .padding(14)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Summary hero

    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(totalCalories)")
                    .apexDisplay(64)
                    .foregroundStyle(totalCalories > 0 ? ApexColor.textPrimary : ApexColor.textSecondary)
                Text("kcal")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ApexColor.textSecondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(mealsOnDate.count) meal\(mealsOnDate.count == 1 ? "" : "s")")
                        .font(.subheadline.bold())
                        .foregroundStyle(ApexColor.textPrimary)
                    Text(selectedDate.isToday ? "Today" : selectedDate.dayAndMonth)
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                }
            }

            if let shares = MacroSplit.shares(protein: totalProtein, carbs: totalCarbs, fat: totalFat) {
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        Capsule().fill(ApexColor.accent).frame(width: max(geo.size.width * shares.protein - 3, 4))
                        Capsule().fill(ApexColor.success).frame(width: max(geo.size.width * shares.carbs - 3, 4))
                        Capsule().fill(ApexColor.warning).frame(width: max(geo.size.width * shares.fat - 3, 4))
                    }
                }
                .frame(height: 10)

                HStack(spacing: 0) {
                    macroLegend("Protein", grams: totalProtein, color: ApexColor.accent)
                    macroLegend("Carbs", grams: totalCarbs, color: ApexColor.success)
                    macroLegend("Fat", grams: totalFat, color: ApexColor.warning)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func macroLegend(_ label: String, grams: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(grams))g").font(.subheadline.bold()).foregroundStyle(ApexColor.textPrimary)
                Text(label).font(.caption2).foregroundStyle(ApexColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var logButtons: some View {
        HStack(spacing: 10) {
            Button { showingCamera = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "camera.fill").font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Snap a meal").font(.subheadline.bold())
                        Text("+\(XPValues.logMeal) XP").font(.caption.bold()).opacity(0.75)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(ApexColor.onAccent)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(ApexColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle())

            Button { showingTextInput = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "text.cursor").font(.title3).foregroundStyle(ApexColor.accent)
                    Text("Type it out").font(.subheadline.bold())
                    Spacer(minLength: 0)
                }
                .foregroundStyle(ApexColor.textPrimary)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(ApexColor.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: - Meals List

    private var mealsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meals")
                .apexLabel()

            ForEach(mealsOnDate) { meal in
                mealRow(meal)
            }
        }
    }

    private func mealRow(_ meal: MealEntry) -> some View {

        HStack(spacing: 12) {
            // Thumbnail
            if let data = meal.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ApexColor.success.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: meal.mealType.systemImage)
                        .font(.title2)
                        .foregroundStyle(ApexColor.success)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(meal.mealType.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.success)
                    Text("·")
                        .foregroundStyle(ApexColor.textSecondary)
                    Text(meal.date.shortTime)
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                }
                Text(meal.mealDescription.isEmpty ? "Meal" : meal.mealDescription)
                    .font(.subheadline.bold())
                    .foregroundStyle(ApexColor.textPrimary)
                    .lineLimit(1)
                Text(meal.macrosSummary)
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(meal.estimatedCalories)")
                    .font(.headline.bold())
                    .foregroundStyle(ApexColor.success)
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(ApexColor.textSecondary)
            }
        }
        .padding(12)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            Button(role: .destructive) {
                context.delete(meal)
            } label: {
                Label("Delete Meal", systemImage: "trash")
            }
        }
    }
}

// MARK: - Text Input View

struct MealTextInputView: View {
    @Environment(\.dismiss) private var dismiss

    var claude: ClaudeService
    var onSave: (MealEntry) -> Void

    @State private var mealText = ""
    @State private var mealType: MealType = .lunch
    @State private var isAnalyzing = false
    @State private var analysis: MealAnalysis?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Meal type selector
                        HStack(spacing: 0) {
                            ForEach(MealType.allCases, id: \.self) { type in
                                Button { mealType = type } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: type.systemImage).font(.title3)
                                        Text(type.rawValue).font(.caption.bold())
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(mealType == type ? ApexColor.background : ApexColor.textSecondary)
                                    .background(mealType == type ? ApexColor.success : Color.clear)
                                }
                            }
                        }
                        .background(ApexColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)

                        // Text input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What did you eat?")
                                .font(.subheadline.bold())
                                .foregroundStyle(ApexColor.textSecondary)
                                .padding(.horizontal)

                            TextEditor(text: $mealText)
                                .frame(minHeight: 120)
                                .padding(12)
                                .background(ApexColor.cardBg)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(ApexColor.textPrimary)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .overlay(alignment: .topLeading) {
                                    if mealText.isEmpty {
                                        Text("e.g. 2 scrambled eggs, whole wheat toast, orange juice...")
                                            .font(.body)
                                            .foregroundStyle(ApexColor.textSecondary.opacity(0.5))
                                            .padding(16)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .padding(.horizontal)

                            Button {
                                Task { await analyze() }
                            } label: {
                                HStack {
                                    if isAnalyzing {
                                        ProgressView().tint(ApexColor.background)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text(isAnalyzing ? "Analyzing..." : "Analyze")
                                        .font(.headline)
                                }
                                .foregroundStyle(ApexColor.onAccent)
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .background(mealText.trimmingCharacters(in: .whitespaces).isEmpty ? ApexColor.success.opacity(0.4) : ApexColor.success)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(mealText.trimmingCharacters(in: .whitespaces).isEmpty || isAnalyzing)
                            .padding(.horizontal)
                        }

                        // Results
                        if let error = errorMessage {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ApexColor.warning)
                                Text(error).font(.subheadline).foregroundStyle(ApexColor.textPrimary)
                            }
                            .apexCard()
                            .padding(.horizontal)
                        } else if let result = analysis {
                            analysisCard(result)
                                .padding(.horizontal)
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(ApexColor.textSecondary)
                }
                if analysis != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.font(.headline).foregroundStyle(ApexColor.success)
                    }
                }
            }
        }
    }

    private func analysisCard(_ result: MealAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Analysis", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ApexColor.success)
                Spacer()
                Text("Confidence: \(result.confidence)")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            }

            Text(result.description)
                .font(.subheadline)
                .foregroundStyle(ApexColor.textPrimary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(result.estimatedCalories)")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(ApexColor.success)
                    Text("estimated calories")
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                }
                Spacer()
                XPBadge(amount: XPValues.logMeal)
            }

            HStack(spacing: 12) {
                macroChip(label: "Protein", value: result.proteinGrams, color: ApexColor.accent)
                macroChip(label: "Carbs",   value: result.carbsGrams,   color: ApexColor.accentCyan)
                macroChip(label: "Fat",     value: result.fatGrams,     color: ApexColor.warning)
            }

            if !result.feedback.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.accent)
                        .padding(.top, 1)
                    Text(result.feedback)
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(ApexColor.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .apexCard()
    }

    private func macroChip(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(Int(value))g").font(.headline.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(ApexColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func analyze() async {
        guard claude.isConfigured else {
            errorMessage = "Set up an AI provider in Settings to analyze meals."
            return
        }
        isAnalyzing = true
        errorMessage = nil
        do {
            analysis = try await claude.analyzeMealText(mealText)
        } catch {
            errorMessage = error.localizedDescription
        }
        isAnalyzing = false
    }

    private func save() {
        guard let result = analysis else { return }
        let entry = MealEntry(
            date: Date(),
            mealType: mealType,
            photoData: nil,
            mealDescription: result.description,
            estimatedCalories: result.estimatedCalories,
            proteinGrams: result.proteinGrams,
            carbsGrams: result.carbsGrams,
            fatGrams: result.fatGrams,
            claudeAnalysis: result.description
        )
        onSave(entry)
        dismiss()
    }
}
