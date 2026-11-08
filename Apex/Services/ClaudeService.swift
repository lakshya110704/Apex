import Foundation
import UIKit

// MARK: - Context Model

struct ApexContext {
    var userName: String = ""
    // Health today
    var sleepHours: Double = 0
    var restingHR: Double = 0
    var hrv: Double = 0
    var todayActiveCalories: Double = 0
    var exerciseMinutes: Double = 0
    var steps: Int = 0
    var vo2Max: Double = 0
    var weight: Double = 0
    var respiratoryRate: Double = 0
    var mindfulMinutes: Double = 0
    // 7-day trends
    var weeklyAvgSleep: Double = 0
    var weeklyAvgHRV: Double = 0
    var weeklyAvgActiveCalories: Double = 0
    var weeklyWorkoutCount: Int = 0
    // Morning check-in
    var energyLevel: Int = 0   // 0 = no check-in today
    var recoveryRating: String = "Moderate"
    var sleepScore: Int = 0
    var focusProjects: [String] = []
    var customNote: String = ""
    // Activity
    var recentWorkoutTypes: [String] = []
    var todayMealCalories: Int = 0
    var todayMeals: Int = 0
    // Nutrition targets & macros
    var calorieTarget: Int = 0
    var proteinTarget: Int = 0       // grams/day based on weight
    var proteinGrams: Double = 0     // consumed today
    var carbsGrams: Double = 0
    var fatGrams: Double = 0
    // Schedule adherence
    var scheduledWorkoutsToday: [String] = []
    var completedWorkoutsToday: [String] = []
    var weeklyMissedWorkouts: Int = 0
    // Gamification
    var currentStreak: Int = 0
    var xpToday: Int = 0
    // Explicitly logged in Apex (not HealthKit auto-detection)
    var weeklyApexWorkouts: Int = 0
    // Calendar
    var calendarEvents: [String] = []
    // GitHub
    var githubCommitsToday: Int = 0
    var githubActiveRepos: [String] = []
    // User request
    var userRequest: String = ""
}

// MARK: - Response Models

struct MealAnalysis {
    let description: String
    let estimatedCalories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let confidence: String
    let feedback: String
}

// MARK: - Service

@Observable
final class ClaudeService {

    var isLoading = false
    var lastError: String?
    var isCheckingLocalAI = false

    private(set) var provider: AIProvider = .gemini

    // Local AI (Ollama)
    private(set) var localAIHost: String = ""
    private(set) var localAIPort: Int = 11434
    private(set) var isLocalAIAvailable: Bool = false

    /// Bumped whenever a key, model or consent value changes so SwiftUI re-reads them.
    private var revision = 0

    private var ollamaBaseURL: String {
        "http://\(localAIHost):\(localAIPort)"
    }

    init() {
        let ud = UserDefaults.standard
        // One-time move of a Gemini key saved by earlier builds from UserDefaults into the Keychain.
        let legacyAccount = AIProvider.gemini.keychainAccount
        if let legacy = ud.string(forKey: legacyAccount), !legacy.isEmpty {
            if KeychainStore.get(legacyAccount) == nil { KeychainStore.set(legacy, for: legacyAccount) }
            if KeychainStore.get(legacyAccount) != nil { ud.removeObject(forKey: legacyAccount) }
        }
        self.localAIHost = ud.string(forKey: UserDefaultsKeys.localAIHost) ?? ""
        self.localAIPort = ud.integer(forKey: UserDefaultsKeys.localAIPort).nonZeroOr(11434)
        // The saved choice wins. Otherwise keep what earlier builds did: Gemini, or the local server if that was the only thing set up.
        if let saved = ud.string(forKey: UserDefaultsKeys.aiProvider), let chosen = AIProvider(rawValue: saved) {
            self.provider = chosen
        } else if KeychainStore.get(legacyAccount) == nil, localAIHost.isNotEmpty {
            self.provider = .local
        }
        // Re-check connectivity on every launch so UI is never stuck disabled
        Task { await checkLocalAIAvailability() }
    }

    // MARK: Provider, keys, models, consent

    func setProvider(_ chosen: AIProvider) {
        provider = chosen
        UserDefaults.standard.set(chosen.rawValue, forKey: UserDefaultsKeys.aiProvider)
        revision += 1
    }

    /// Key for the selected provider.
    var apiKey: String { apiKey(for: provider) }

    func apiKey(for target: AIProvider) -> String {
        _ = revision
        return KeychainStore.get(target.keychainAccount) ?? ""
    }

    func setAPIKey(_ key: String) { setAPIKey(key, for: provider) }

    func setAPIKey(_ key: String, for target: AIProvider) {
        KeychainStore.set(key, for: target.keychainAccount)
        revision += 1
    }

    func model(for target: AIProvider) -> String {
        _ = revision
        let saved = UserDefaults.standard.string(forKey: target.modelDefaultsKey) ?? ""
        return saved.isEmpty ? target.defaultModel : saved
    }

    func setModel(_ name: String, for target: AIProvider) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: target.modelDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: target.modelDefaultsKey)
        }
        revision += 1
    }

    var localAIModel: String { model(for: .local) }

    /// Consent for the selected provider.
    var aiConsentGiven: Bool { consent(for: provider) }

    func consent(for target: AIProvider) -> Bool {
        _ = revision
        return UserDefaults.standard.bool(forKey: target.consentDefaultsKey)
    }

    func setAIConsent(_ given: Bool) { setConsent(given, for: provider) }

    func setConsent(_ given: Bool, for target: AIProvider) {
        UserDefaults.standard.set(given, forKey: target.consentDefaultsKey)
        revision += 1
    }

    /// True when the selected provider can be called right now.
    var isConfigured: Bool {
        provider.isCloud ? !apiKey.isEmpty : isLocalAIAvailable
    }

    func setLocalAI(host: String, port: Int, model: String) {
        let ud = UserDefaults.standard
        localAIHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        localAIPort = port
        ud.set(localAIHost, forKey: UserDefaultsKeys.localAIHost)
        ud.set(port,        forKey: UserDefaultsKeys.localAIPort)
        setModel(model, for: .local)
        Task { await checkLocalAIAvailability() }
    }

    func checkLocalAIAvailability() async {
        guard localAIHost.isNotEmpty else { isLocalAIAvailable = false; return }
        isCheckingLocalAI = true
        defer { isCheckingLocalAI = false }
        guard let url = URL(string: "\(ollamaBaseURL)/api/tags") else {
            isLocalAIAvailable = false; return
        }
        do {
            var req = URLRequest(url: url, timeoutInterval: 3)
            req.httpMethod = "GET"
            let (_, response) = try await URLSession.shared.data(for: req)
            isLocalAIAvailable = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            isLocalAIAvailable = false
        }
    }

    // MARK: - Meal Analysis

    func analyzeMeal(image: UIImage) async throws -> MealAnalysis {
        guard let jpegData = image.jpegData(compressionQuality: 0.7) else {
            throw ClaudeError.imageConversionFailed
        }

        let systemPrompt = """
        You are a nutrition analyst. Respond ONLY with valid JSON in this exact format:
        {"description":"<what the meal is>","calories":<integer>,"protein":<number>,"carbs":<number>,"fat":<number>,"confidence":"<low|medium|high>","feedback":"<2 sentences: what's good about this meal nutritionally, and one specific thing to improve next time>"}
        Protein/carbs/fat are in grams. Be direct and honest in feedback — no food suggestions, just analysis of what they ate.
        """

        let responseText = try await send(AIRequestSpec(
            system: systemPrompt,
            messages: [AIMessage(role: .user, text: "Analyze this meal. Respond with JSON only.")],
            maxTokens: 300, wantsJSON: true, imageJPEG: jpegData
        ))
        return try parseMealAnalysis(from: responseText)
    }

    func analyzeMealText(_ description: String) async throws -> MealAnalysis {
        let systemPrompt = """
        You are a nutrition analyst. Respond ONLY with valid JSON in this exact format:
        {"description":"<what the meal is>","calories":<integer>,"protein":<number>,"carbs":<number>,"fat":<number>,"confidence":"<low|medium|high>","feedback":"<2 sentences: what's good about this meal nutritionally, and one specific thing to improve next time>"}
        Protein/carbs/fat are in grams. Be direct and honest — no food suggestions, just analysis of what they ate.
        """
        let userText = "Estimate macros for this meal: \(description)"

        let responseText = try await send(AIRequestSpec(
            system: systemPrompt,
            messages: [AIMessage(role: .user, text: userText)],
            maxTokens: 300, wantsJSON: true
        ))
        return try parseMealAnalysis(from: responseText)
    }

    func parseMealAnalysis(from text: String) throws -> MealAnalysis {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ClaudeError.parseError }

        return MealAnalysis(
            description:       json["description"] as? String ?? "Unknown meal",
            estimatedCalories: Int(((json["calories"] as? NSNumber)?.doubleValue ?? 0).rounded()),
            proteinGrams:     (json["protein"]     as? NSNumber)?.doubleValue ?? 0,
            carbsGrams:       (json["carbs"]       as? NSNumber)?.doubleValue ?? 0,
            fatGrams:         (json["fat"]         as? NSNumber)?.doubleValue ?? 0,
            confidence:        json["confidence"]  as? String ?? "medium",
            feedback:          json["feedback"]    as? String ?? ""
        )
    }

    // MARK: - Generate Daily Plan

    func generateDailyPlan(context: ApexContext) async throws -> String {
        let geminiPrompt = """
        You are Apex Coach. Output ONLY a JSON array — no other text, no markdown, no backticks:
        [{"time":"HH:MM","category":"morning|workout|nutrition|focus|evening","activity":"one-line description"}]
        Max 10 items. Keep each activity concise (under 8 words). Base intensity on HRV, sleep score, and energy level. Factor in calendar events and scheduled meetings.
        """

        let contextText = buildContextMessage(context)
        let recentSports = context.recentWorkoutTypes.prefix(3).joined(separator: ", ")
        let workoutHint = recentSports.isEmpty ? "gym or sport session" : recentSports

        let ollamaSystemPrompt = """
        You are a daily schedule planner. Output a schedule as plain lines — NO JSON, NO brackets, NO quotes.
        Each line must follow this exact pattern:
        HH:MM | category | activity

        Rules:
        - HH:MM is a single time, never a range (e.g. 07:30, not 07:30-08:30)
        - category is one word only: morning, workout, nutrition, focus, or evening
        - activity is a short phrase, under 8 words
        - Output 6 to 8 lines, cover at least 4 different categories
        - Sort by time, earliest first
        - No extra text before or after the lines
        - IMPORTANT: For workout activities, only suggest sports or exercises the athlete actually does: \(workoutHint). Never invent activities they have not done.

        Example output:
        07:00 | morning | Wake up and cold shower
        08:00 | nutrition | High protein breakfast
        10:00 | focus | Deep work session
        13:00 | nutrition | Balanced lunch
        17:00 | workout | \(workoutHint.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "Gym session")
        22:00 | evening | Wind down and journaling
        """

        return try await send(AIRequestSpec(
            system: provider == .local ? ollamaSystemPrompt : geminiPrompt,
            messages: [AIMessage(role: .user, text: contextText)],
            maxTokens: provider == .local ? 800 : 1024
        ))
    }

    // MARK: - Chat

    func chat(messages: [ChatMessage], context: ApexContext) async throws -> String {
        let systemPrompt = buildCoachSystemPrompt(context: context)
        let filtered = messages.filter { $0.role != .system }

        let aiMessages = filtered.map { AIMessage(role: $0.role == .user ? .user : .assistant, text: $0.content) }
        return try await send(AIRequestSpec(system: systemPrompt, messages: aiMessages, maxTokens: 400))
    }

    private func buildCoachSystemPrompt(context: ApexContext) -> String {
        let caloriesRemaining = context.calorieTarget > 0 ? context.calorieTarget - context.todayMealCalories : -1
        let proteinRemaining = context.proteinTarget > 0 ? context.proteinTarget - Int(context.proteinGrams) : -1

        let scheduleStatus: String = {
            if context.scheduledWorkoutsToday.isEmpty { return "No workout scheduled today." }
            let done = context.completedWorkoutsToday
            let planned = context.scheduledWorkoutsToday
            let missed = planned.filter { p in !done.contains(where: { $0.lowercased().contains(p.lowercased()) }) }
            if missed.isEmpty { return "All scheduled workouts completed ✓ (\(planned.joined(separator: ", ")))" }
            return "Scheduled: \(planned.joined(separator: ", ")) | Completed: \(done.isEmpty ? "none yet" : done.joined(separator: ", ")) | Pending: \(missed.joined(separator: ", "))"
        }()

        return """
        You are Apex Coach — an elite, data-driven performance coach for \(context.userName). Your job is to optimize their performance, not validate their feelings.

        COACHING PHILOSOPHY:
        - Never just agree with a bad decision. Look at the data first, then respond.
        - Always cite specific numbers from their data in your response.
        - Be direct and honest — not harsh, but completely unambiguous.
        - If recovery metrics are good, push them. If recovery is poor, enforce rest. Trust the data over their mood.
        - Food decisions: check calories remaining and protein target before answering. A treat is fine if budget allows; call it out if it doesn't.
        - Workout skip requests: check HRV vs 7-day avg, sleep score, streak, and scheduled plan. Say no if data supports training.
        - If their HRV is at or above their 7-day average AND sleep score ≥ 65, they have no objective reason to skip a planned workout.
        - OVERTRAINING RULE: Never suggest overtraining if "Workouts logged in Apex this week" is 0 or 1. Low HRV or fatigue with zero logged workouts means under-recovery or illness, NOT overtraining. Call it what it actually is.
        - Always distinguish between HealthKit auto-detected activity and workouts the user actually logged. Only logged workouts count as training load.
        - Never start with "Great question!" or similar filler. Lead with the answer.
        - Under 160 words. No bullet lists unless comparing options.

        LIVE DATA SNAPSHOT:
        \(buildContextMessage(context))

        SCHEDULE TODAY: \(scheduleStatus)
        WEEKLY MISSED WORKOUTS: \(context.weeklyMissedWorkouts)
        CURRENT STREAK: \(context.currentStreak) days | XP TODAY: \(context.xpToday)

        NUTRITION BUDGET:
        \(context.calorieTarget > 0 ? "Target: \(context.calorieTarget) kcal | Eaten: \(context.todayMealCalories) kcal | Remaining: \(caloriesRemaining) kcal" : "No calorie target set")
        \(context.proteinTarget > 0 ? "Protein target: \(context.proteinTarget)g | Eaten: \(Int(context.proteinGrams))g | Remaining: \(proteinRemaining)g" : "")
        \(context.carbsGrams > 0 ? "Carbs: \(Int(context.carbsGrams))g | Fat: \(Int(context.fatGrams))g" : "")
        """
    }

    // MARK: - Context Builder

    func buildContextMessage(_ ctx: ApexContext) -> String {
        var lines: [String] = []

        lines.append("Athlete: \(ctx.userName)")

        lines.append("\n── HEALTH TODAY ──")
        lines.append("Sleep: \(String(format: "%.1f", ctx.sleepHours))h tonight (7-day avg: \(String(format: "%.1f", ctx.weeklyAvgSleep))h)")
        if ctx.hrv > 0 { lines.append("HRV: \(Int(ctx.hrv))ms tonight (7-day avg: \(Int(ctx.weeklyAvgHRV))ms)") }
        if ctx.restingHR > 0 { lines.append("RHR: \(Int(ctx.restingHR)) bpm") }
        if ctx.vo2Max > 0 { lines.append("VO2 Max: \(String(format: "%.1f", ctx.vo2Max)) mL/kg/min") }
        if ctx.weight > 0 { lines.append("Weight: \(String(format: "%.1f", ctx.weight)) kg") }
        if ctx.respiratoryRate > 0 { lines.append("Respiratory rate: \(String(format: "%.0f", ctx.respiratoryRate)) breaths/min") }
        lines.append("Active cal: \(Int(ctx.todayActiveCalories)) | Exercise: \(Int(ctx.exerciseMinutes))m | Steps: \(ctx.steps)")
        if ctx.mindfulMinutes > 0 { lines.append("Mindfulness: \(Int(ctx.mindfulMinutes)) min today") }

        lines.append("\n── RECOVERY ──")
        let sleepText = ctx.sleepScore > 0 ? "\(ctx.sleepScore)/100" : "not reported"
        let energyText = ctx.energyLevel > 0 ? "\(ctx.energyLevel)/5" : "not reported"
        lines.append("Sleep score: \(sleepText) | Recovery: \(ctx.recoveryRating) | Energy: \(energyText)")

        lines.append("\n── TRAINING ──")
        lines.append("Workouts logged in Apex this week: \(ctx.weeklyApexWorkouts)")
        lines.append("HealthKit detected workouts (Watch/auto): \(ctx.weeklyWorkoutCount)")
        lines.append("7-day avg active calories: \(Int(ctx.weeklyAvgActiveCalories))")
        if !ctx.recentWorkoutTypes.isEmpty {
            lines.append("Recent logged: \(ctx.recentWorkoutTypes.prefix(5).joined(separator: ", "))")
        }

        if !ctx.focusProjects.isEmpty {
            lines.append("\n── FOCUS PROJECTS ──")
            lines.append(ctx.focusProjects.joined(separator: ", "))
        }
        if !ctx.customNote.isEmpty { lines.append("Note: \(ctx.customNote)") }

        if ctx.todayMeals > 0 {
            lines.append("\n── NUTRITION ──")
            lines.append("\(ctx.todayMealCalories) kcal across \(ctx.todayMeals) meals today")
            if ctx.proteinGrams > 0 {
                lines.append("Macros: \(Int(ctx.proteinGrams))g protein | \(Int(ctx.carbsGrams))g carbs | \(Int(ctx.fatGrams))g fat")
            }
            if ctx.proteinTarget > 0 {
                lines.append("Daily target: \(ctx.calorieTarget) kcal / \(ctx.proteinTarget)g protein")
            }
        }

        if !ctx.calendarEvents.isEmpty {
            lines.append("\n── CALENDAR TODAY ──")
            ctx.calendarEvents.forEach { lines.append("  \($0)") }
        }

        if ctx.githubCommitsToday > 0 {
            lines.append("\n── GITHUB ──")
            lines.append("\(ctx.githubCommitsToday) commits today in: \(ctx.githubActiveRepos.joined(separator: ", "))")
        }

        if !ctx.userRequest.isEmpty {
            lines.append("\n── REQUEST ──")
            lines.append(ctx.userRequest)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Send

    private func send(_ spec: AIRequestSpec) async throws -> String {
        let key = apiKey
        if provider.isCloud {
            guard !key.isEmpty else { throw ClaudeError.noAPIKey(provider.displayName) }
            guard aiConsentGiven else { throw ClaudeError.consentRequired(provider.company) }
        } else {
            guard localAIHost.isNotEmpty else { throw ClaudeError.networkError }
        }

        isLoading = true
        defer { isLoading = false }

        let request = try provider.urlRequest(spec, apiKey: key, model: model(for: provider), localBaseURL: ollamaBaseURL)
        return try provider.parseReply(try await perform(request))
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is URLError {
            throw ClaudeError.networkError
        }
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.networkError }
        guard http.statusCode == 200 else {
            throw ClaudeError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// Tiny request with no personal data, so the user can check a key and model before relying on them.
    func testConnection(apiKey key: String, model name: String) async throws {
        let spec = AIRequestSpec(
            system: "Reply with the single word OK.",
            messages: [AIMessage(role: .user, text: "ping")],
            maxTokens: 8
        )
        let request = try provider.urlRequest(spec, apiKey: key, model: name.isEmpty ? provider.defaultModel : name, localBaseURL: ollamaBaseURL)
        _ = try provider.parseReply(try await perform(request))
    }

    /// Asks the provider which models this key can use, so a retired default never leaves the user stuck.
    func listModels(apiKey key: String) async throws -> [String] {
        guard let request = provider.modelsRequest(apiKey: key) else { return [] }
        let ids = provider.parseModels(try await perform(request))
        guard !ids.isEmpty else { throw ClaudeError.parseError }
        return ids
    }
}
