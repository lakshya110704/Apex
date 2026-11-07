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

// MARK: - Gemini API Request/Response

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiSystemInstruction?
    let generationConfig: GeminiGenerationConfig?
}

private struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiGenerationConfig: Encodable {
    let maxOutputTokens: Int
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable {
    let text: String?
    let inlineData: GeminiInlineData?

    init(text: String) {
        self.text = text
        self.inlineData = nil
    }

    init(imageData: Data, mimeType: String = "image/jpeg") {
        self.text = nil
        self.inlineData = GeminiInlineData(
            mimeType: mimeType,
            data: imageData.base64EncodedString()
        )
    }

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}

private struct GeminiInlineData: Encodable {
    let mimeType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]?

    var text: String {
        candidates?.first?.content.parts.first?.text ?? ""
    }
}

private struct GeminiCandidate: Decodable {
    let content: GeminiResponseContent
}

private struct GeminiResponseContent: Decodable {
    let parts: [GeminiResponsePart]
}

private struct GeminiResponsePart: Decodable {
    let text: String?
}

// MARK: - Ollama Models

private struct OllamaRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let format: String?
    let options: OllamaOptions?
}

private struct OllamaMessage: Encodable {
    let role: String
    let content: String
}

private struct OllamaOptions: Encodable {
    let numPredict: Int
    enum CodingKeys: String, CodingKey { case numPredict = "num_predict" }
}

private struct OllamaResponse: Decodable {
    struct OllamaMsg: Decodable { let content: String }
    let message: OllamaMsg
}

// MARK: - Service

@Observable
final class ClaudeService {

    var isLoading = false
    var lastError: String?
    var isCheckingLocalAI = false

    private(set) var apiKey: String = ""
    private(set) var aiConsentGiven = false

    // Local AI (Ollama)
    private(set) var localAIHost: String = ""
    private(set) var localAIPort: Int = 11434
    private(set) var localAIModel: String = "llama3.2"
    private(set) var isLocalAIAvailable: Bool = false

    private let geminiModel = "gemini-2.5-flash"
    static let ollamaReasoningHeadroom = 1200
    private var baseURL: String {
        "https://generativelanguage.googleapis.com/v1beta/models/\(geminiModel):generateContent"
    }
    private var ollamaBaseURL: String {
        "http://\(localAIHost):\(localAIPort)"
    }

    init() {
        let ud = UserDefaults.standard
        self.apiKey       = KeychainStore.get(UserDefaultsKeys.claudeAPIKey) ?? ""
        // One-time move of a key saved by earlier builds from UserDefaults into the Keychain.
        if let legacy = ud.string(forKey: UserDefaultsKeys.claudeAPIKey), !legacy.isEmpty {
            if apiKey.isEmpty, KeychainStore.set(legacy, for: UserDefaultsKeys.claudeAPIKey) { apiKey = legacy }
            if KeychainStore.get(UserDefaultsKeys.claudeAPIKey) != nil { ud.removeObject(forKey: UserDefaultsKeys.claudeAPIKey) }
        }
        self.aiConsentGiven = ud.bool(forKey: UserDefaultsKeys.aiConsent)
        self.localAIHost  = ud.string(forKey: UserDefaultsKeys.localAIHost)   ?? ""
        self.localAIPort  = ud.integer(forKey: UserDefaultsKeys.localAIPort).nonZeroOr(11434)
        self.localAIModel = ud.string(forKey: UserDefaultsKeys.localAIModel)  ?? "llama3.2"
        // Re-check connectivity on every launch so UI is never stuck disabled
        Task { await checkLocalAIAvailability() }
    }

    func setAPIKey(_ key: String) {
        apiKey = key
        KeychainStore.set(key, for: UserDefaultsKeys.claudeAPIKey)
    }

    func setAIConsent(_ given: Bool) {
        aiConsentGiven = given
        UserDefaults.standard.set(given, forKey: UserDefaultsKeys.aiConsent)
    }

    func setLocalAI(host: String, port: Int, model: String) {
        let ud = UserDefaults.standard
        localAIHost  = host.trimmingCharacters(in: .whitespacesAndNewlines)
        localAIPort  = port
        localAIModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        ud.set(localAIHost,  forKey: UserDefaultsKeys.localAIHost)
        ud.set(port,         forKey: UserDefaultsKeys.localAIPort)
        ud.set(localAIModel, forKey: UserDefaultsKeys.localAIModel)
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

        let request = GeminiRequest(
            contents: [GeminiContent(parts: [
                GeminiPart(imageData: jpegData),
                GeminiPart(text: "Analyze this meal. Respond with JSON only.")
            ])],
            systemInstruction: GeminiSystemInstruction(parts: [GeminiPart(text: systemPrompt)]),
            generationConfig: GeminiGenerationConfig(maxOutputTokens: 300)
        )

        let responseText = try await sendRequest(request)
        return try parseMealAnalysis(from: responseText)
    }

    func analyzeMealText(_ description: String) async throws -> MealAnalysis {
        let systemPrompt = """
        You are a nutrition analyst. Respond ONLY with valid JSON in this exact format:
        {"description":"<what the meal is>","calories":<integer>,"protein":<number>,"carbs":<number>,"fat":<number>,"confidence":"<low|medium|high>","feedback":"<2 sentences: what's good about this meal nutritionally, and one specific thing to improve next time>"}
        Protein/carbs/fat are in grams. Be direct and honest — no food suggestions, just analysis of what they ate.
        """
        let userText = "Estimate macros for this meal: \(description)"

        if isLocalAIAvailable {
            let text = try await sendOllamaRequest(
                systemPrompt: systemPrompt,
                messages: [OllamaMessage(role: "user", content: userText)],
                maxTokens: 300, forceJSON: true
            )
            return try parseMealAnalysis(from: text)
        }

        let request = GeminiRequest(
            contents: [GeminiContent(parts: [GeminiPart(text: userText)])],
            systemInstruction: GeminiSystemInstruction(parts: [GeminiPart(text: systemPrompt)]),
            generationConfig: GeminiGenerationConfig(maxOutputTokens: 300)
        )
        let responseText = try await sendRequest(request)
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

        if isLocalAIAvailable {
            return try await sendOllamaRequest(
                systemPrompt: ollamaSystemPrompt,
                messages: [OllamaMessage(role: "user", content: contextText)],
                maxTokens: 800, forceJSON: false
            )
        }

        let request = GeminiRequest(
            contents: [GeminiContent(parts: [GeminiPart(text: contextText)])],
            systemInstruction: GeminiSystemInstruction(parts: [GeminiPart(text: geminiPrompt)]),
            generationConfig: GeminiGenerationConfig(maxOutputTokens: 1024)
        )
        return try await sendRequest(request)
    }

    // MARK: - Chat

    func chat(messages: [ChatMessage], context: ApexContext) async throws -> String {
        let systemPrompt = buildCoachSystemPrompt(context: context)
        let filtered = messages.filter { $0.role != .system }

        if isLocalAIAvailable {
            let ollamaMessages = filtered.map {
                OllamaMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content)
            }
            return try await sendOllamaRequest(
                systemPrompt: systemPrompt,
                messages: ollamaMessages,
                maxTokens: 400
            )
        }

        let contents = filtered.map { GeminiContent(parts: [GeminiPart(text: $0.content)]) }
        let request = GeminiRequest(
            contents: contents,
            systemInstruction: GeminiSystemInstruction(parts: [GeminiPart(text: systemPrompt)]),
            generationConfig: GeminiGenerationConfig(maxOutputTokens: 400)
        )
        return try await sendRequest(request)
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

    // MARK: - Ollama Core

    private func sendOllamaRequest(systemPrompt: String, messages: [OllamaMessage], maxTokens: Int, forceJSON: Bool = false) async throws -> String {
        guard let url = URL(string: "\(ollamaBaseURL)/api/chat") else { throw ClaudeError.networkError }

        var allMessages = [OllamaMessage(role: "system", content: systemPrompt)]
        allMessages += messages

        let body = OllamaRequest(
            model: localAIModel,
            messages: allMessages,
            stream: false,
            format: forceJSON ? "json" : nil,
            // Reasoning models (gpt-oss) spend tokens thinking before the visible reply; without headroom the reply comes back empty.
            options: OllamaOptions(numPredict: maxTokens + Self.ollamaReasoningHeadroom)
        )

        var req = URLRequest(url: url, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        isLoading = true
        defer { isLoading = false }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClaudeError.networkError
        }
        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return decoded.message.content
    }

    // MARK: - Gemini Core

    private func sendRequest(_ body: GeminiRequest) async throws -> String {
        guard apiKey.isNotEmpty else { throw ClaudeError.noAPIKey }
        guard aiConsentGiven else { throw ClaudeError.consentRequired }

        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: baseURL) else {
            throw ClaudeError.networkError
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch is URLError {
            throw ClaudeError.networkError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }
        guard httpResponse.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiError(httpResponse.statusCode, bodyStr)
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return geminiResponse.text
    }
}

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case noAPIKey
    case consentRequired
    case imageConversionFailed
    case parseError
    case networkError
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:              return "No API key. Add your Google AI key in Settings."
        case .imageConversionFailed: return "Failed to process image."
        case .parseError:            return "Could not parse the response."
        case .consentRequired:       return "Turn on AI data sharing in Settings first. Your health summary and meal photos are sent to Google Gemini."
        case .networkError:          return "No connection to the AI service. Check your internet and try again."
        case .apiError(429, _):      return "AI quota reached. Wait a bit and try again."
        case .apiError(let code, _): return "API error \(code). Check your key in Settings."
        }
    }
}
