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

                        // Date Picker
                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .padding(.horizontal)

                        // Daily Summary
                        dailySummaryCard
                            .padding(.horizontal)

                        // Log Meal Buttons
                        HStack(spacing: 10) {
                            Button { showingCamera = true } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                        .font(.subheadline.bold())
                                    Text("Snap a Meal")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    XPBadge(amount: XPValues.logMeal)
                                }
                                .foregroundStyle(ApexColor.background)
                                .padding(14)
                                .background(ApexColor.success)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .frame(maxWidth: .infinity)

                            Button { showingTextInput = true } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "text.cursor")
                                        .font(.subheadline.bold())
                                    Text("Type it out")
                                        .font(.subheadline.bold())
                                }
                                .foregroundStyle(ApexColor.textPrimary)
                                .padding(14)
                                .frame(maxWidth: .infinity)
                                .background(ApexColor.cardBg)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding(.horizontal)

                        // Meals List
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
            .preferredColorScheme(.dark)
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

    // MARK: - Summary Card

    private var dailySummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(totalCalories)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(totalCalories > 0 ? ApexColor.success : ApexColor.textSecondary)
                    Text("kcal today")
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(mealsOnDate.count) meal\(mealsOnDate.count == 1 ? "" : "s")")
                        .font(.subheadline.bold())
                        .foregroundStyle(ApexColor.textPrimary)
                    Text(selectedDate.isToday ? "Today" : selectedDate.dayAndMonth)
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                }
            }

            if !mealsOnDate.isEmpty {
                HStack(spacing: 0) {
                    macroBar(label: "Protein", grams: totalProtein, color: ApexColor.accent)
                    Divider().background(ApexColor.cardBg2).frame(height: 40)
                    macroBar(label: "Carbs",   grams: totalCarbs,   color: ApexColor.accentCyan)
                    Divider().background(ApexColor.cardBg2).frame(height: 40)
                    macroBar(label: "Fat",     grams: totalFat,     color: ApexColor.warning)
                }
            }
        }
        .apexCard()
    }

    private func macroBar(label: String, grams: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(grams))g")
                .font(.headline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(ApexColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Meals List

    private var mealsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meals")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ApexColor.textSecondary)

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
                                .foregroundStyle(ApexColor.background)
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
            .preferredColorScheme(.dark)
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
        guard !claude.apiKey.isEmpty else {
            errorMessage = "Add your Google AI key in Settings to analyze meals."
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
