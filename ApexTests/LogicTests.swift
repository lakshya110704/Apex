import XCTest
import SwiftData
import HealthKit
import SwiftUI
@testable import Apex

@MainActor
final class LogicTests: XCTestCase {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date())!
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: UserProfile.self, WorkoutSession.self, GymExercise.self, MealEntry.self, Achievement.self, MorningCheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func gymSession(daysAgo: Int, _ exercises: [(MuscleGroup, Int)]) -> WorkoutSession {
        let session = WorkoutSession(date: day(-daysAgo), type: .gym)
        session.gymExercises = exercises.map { GymExercise(name: "x", muscleGroup: $0.0, sets: $0.1) }
        return session
    }

    // MARK: Levels

    func testLevelBoundaries() {
        XCTAssertEqual(LevelThresholds.level(for: 0), 1)
        XCTAssertEqual(LevelThresholds.level(for: 499), 1)
        XCTAssertEqual(LevelThresholds.level(for: 500), 2)
        XCTAssertEqual(LevelThresholds.level(for: 60_000), 10)
        XCTAssertEqual(LevelThresholds.level(for: 1_000_000), 10)
    }

    func testLevelProgressAndNextXP() {
        XCTAssertEqual(LevelThresholds.progress(for: 250), 0.5, accuracy: 0.001)
        XCTAssertEqual(LevelThresholds.xpForNextLevel(currentXP: 250), 250)
        XCTAssertEqual(LevelThresholds.progress(for: 60_000), 1.0)
        XCTAssertEqual(LevelThresholds.xpForNextLevel(currentXP: 60_000), 0)
    }

    // MARK: Streaks

    func testWorkoutStreakFirstLogStartsAtOne() {
        let profile = UserProfile()
        GamificationService().updateWorkoutStreak(profile: profile)
        XCTAssertEqual(profile.workoutStreak, 1)
    }

    func testWorkoutStreakSameDayDoesNotIncrement() {
        let profile = UserProfile()
        let service = GamificationService()
        service.updateWorkoutStreak(profile: profile)
        service.updateWorkoutStreak(profile: profile)
        XCTAssertEqual(profile.workoutStreak, 1)
    }

    func testWorkoutStreakIncrementsAfterYesterdayAndResetsAfterGap() {
        let profile = UserProfile()
        profile.workoutStreak = 4
        profile.lastWorkoutDate = day(-1)
        GamificationService().updateWorkoutStreak(profile: profile)
        XCTAssertEqual(profile.workoutStreak, 5)

        profile.lastWorkoutDate = day(-3)
        GamificationService().updateWorkoutStreak(profile: profile)
        XCTAssertEqual(profile.workoutStreak, 1)
    }

    func testMealStreakIncrementsAndResets() {
        let profile = UserProfile()
        profile.mealStreak = 2
        profile.lastMealDate = day(-1)
        GamificationService().updateMealStreak(profile: profile)
        XCTAssertEqual(profile.mealStreak, 3)

        profile.lastMealDate = day(-5)
        GamificationService().updateMealStreak(profile: profile)
        XCTAssertEqual(profile.mealStreak, 1)
    }

    // MARK: XP

    func testProcessWorkoutAwardsXPByType() throws {
        let context = try makeContext()
        let profile = UserProfile()
        let service = GamificationService()

        let tennis = WorkoutSession(type: .tennis)
        service.processWorkout(tennis, profile: profile, context: context)
        XCTAssertEqual(tennis.xpEarned, XPValues.logTennisSession)

        let gym = WorkoutSession(type: .gym)
        service.processWorkout(gym, profile: profile, context: context)
        XCTAssertEqual(gym.xpEarned, XPValues.logGymWorkout)
        XCTAssertGreaterThanOrEqual(profile.xpPoints, XPValues.logTennisSession + XPValues.logGymWorkout)
    }

    func testFirstMealUnlocksAchievementOnce() throws {
        let context = try makeContext()
        let profile = UserProfile()
        let service = GamificationService()
        let meal = MealEntry()
        context.insert(meal)
        service.processMeal(meal, profile: profile, context: context)
        let unlocked = service.pendingAchievements.filter { $0.achievementID == AchievementID.firstMeal.rawValue }
        XCTAssertEqual(unlocked.count, 1)

        let second = MealEntry()
        context.insert(second)
        service.processMeal(second, profile: profile, context: context)
        let again = service.pendingAchievements.filter { $0.achievementID == AchievementID.firstMeal.rawValue }
        XCTAssertEqual(again.count, 1)
    }

    // MARK: Muscle tracker

    func testStatusesUseMostRecentDateAndSortMostNeglectedFirst() {
        let workouts = [
            gymSession(daysAgo: 6, [(.legs, 3)]),
            gymSession(daysAgo: 1, [(.chest, 3), (.legs, 3)]),
        ]
        let statuses = MuscleGroupTracker.statuses(from: workouts)
        XCTAssertEqual(statuses.count, MuscleGroupTracker.trackedGroups.count)
        XCTAssertEqual(statuses.first(where: { $0.muscleGroup == .legs })?.daysSinceTrained, 1)
        XCTAssertEqual(statuses.first(where: { $0.muscleGroup == .chest })?.recoveryLevel, .restingToday)
        // Never-trained groups sort ahead of recently trained ones.
        XCTAssertNil(statuses.first?.lastTrainedDate)
    }

    func testRecoveryBucketsAndSuggestion() {
        let neglected = MuscleGroupTracker.Status(muscleGroup: .back, lastTrainedDate: day(-6))
        XCTAssertEqual(neglected.recoveryLevel, .neglected)
        XCTAssertEqual(MuscleGroupTracker.Status(muscleGroup: .back, lastTrainedDate: day(-3)).recoveryLevel, .recovering)
        XCTAssertEqual(MuscleGroupTracker.Status(muscleGroup: .back, lastTrainedDate: nil).recoveryLevel, .stale)
        XCTAssertEqual(MuscleGroupTracker.Status(muscleGroup: .back, lastTrainedDate: nil).gapDescription, "Never trained")

        let fresh = MuscleGroupTracker.trackedGroups.map { MuscleGroupTracker.Status(muscleGroup: $0, lastTrainedDate: day(-2)) }
        XCTAssertNil(MuscleGroupTracker.suggestion(from: fresh))
        XCTAssertEqual(MuscleGroupTracker.suggestion(from: [neglected])?.muscleGroup, .back)
    }

    func testSetCountsRespectRangeAndIgnoreNonGym() {
        let workouts = [
            gymSession(daysAgo: 2, [(.chest, 4)]),
            gymSession(daysAgo: 20, [(.chest, 5)]),
            WorkoutSession(date: day(-1), type: .tennis),
        ]
        XCTAssertEqual(MuscleGroupTracker.setCounts(from: workouts, range: .week)[.chest], 4)
        XCTAssertEqual(MuscleGroupTracker.setCounts(from: workouts, range: .month)[.chest], 9)
        XCTAssertEqual(MuscleGroupTracker.setCounts(from: workouts, range: .allTime)[.chest], 9)
    }

    // MARK: Exercise database

    func testExerciseDatabase() {
        XCTAssertEqual(ExerciseDatabase.search("").count, ExerciseDatabase.all.count)
        XCTAssertTrue(ExerciseDatabase.search("squat").contains { $0.name == "Barbell Back Squat" })
        XCTAssertTrue(ExerciseDatabase.search("zzzz-no-match").isEmpty)
        for group in MuscleGroupTracker.trackedGroups {
            XCTAssertFalse(ExerciseDatabase.byMuscleGroup(group).isEmpty, "\(group) has no exercises")
        }
        XCTAssertTrue(ExerciseDatabase.all.allSatisfy { URL(string: $0.videoURL) != nil })
    }

    // MARK: Meal JSON parsing

    func testParseMealAnalysisHandlesFencedJSON() throws {
        let text = "```json\n{\"description\":\"Oats\",\"calories\":350,\"protein\":12.5,\"carbs\":60,\"fat\":6,\"confidence\":\"high\",\"feedback\":\"ok\"}\n```"
        let meal = try ClaudeService().parseMealAnalysis(from: text)
        XCTAssertEqual(meal.description, "Oats")
        XCTAssertEqual(meal.estimatedCalories, 350)
        XCTAssertEqual(meal.proteinGrams, 12.5, accuracy: 0.001)
    }

    func testParseMealAnalysisRejectsGarbage() {
        XCTAssertThrowsError(try ClaudeService().parseMealAnalysis(from: "sorry, I cannot help"))
    }

    func testParseMealAnalysisKeepsFractionalCalories() throws {
        let meal = try ClaudeService().parseMealAnalysis(from: "{\"calories\":412.6}")
        XCTAssertEqual(meal.estimatedCalories, 413)
    }

    // MARK: AI consent and errors

    func testGeminiCallIsBlockedWithoutConsent() async {
        let ai = ClaudeService()
        let oldProvider = ai.provider
        ai.setProvider(.gemini)
        let oldKey = ai.apiKey, oldConsent = ai.aiConsentGiven
        defer { ai.setAPIKey(oldKey); ai.setAIConsent(oldConsent); ai.setProvider(oldProvider) }
        ai.setAPIKey("test-key")
        ai.setAIConsent(false)
        do {
            _ = try await ai.analyzeMealText("oats")
            XCTFail("expected consentRequired")
        } catch let error as ClaudeError {
            guard case .consentRequired = error else { return XCTFail("got \(error)") }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testErrorMessages() {
        XCTAssertEqual(ClaudeError.apiError(429, "").errorDescription, "AI quota reached. Wait a bit and try again.")
        XCTAssertTrue(ClaudeError.apiError(400, "").errorDescription?.contains("400") == true)
        XCTAssertTrue(ClaudeError.networkError.errorDescription?.contains("internet") == true)
        XCTAssertTrue(ClaudeError.consentRequired("OpenAI").errorDescription?.contains("OpenAI") == true)
        XCTAssertTrue(ClaudeError.noAPIKey("Anthropic Claude").errorDescription?.contains("Anthropic Claude") == true)
        XCTAssertTrue(ClaudeError.imagesNotSupported("Local (Ollama)").errorDescription?.contains("Type it out") == true)
    }

    // MARK: Streak bonuses and check-in run

    func testStreakMilestoneXP() {
        XCTAssertEqual(GamificationService.streakMilestoneXP(from: 5, to: 6), 0)
        XCTAssertEqual(GamificationService.streakMilestoneXP(from: 6, to: 7), XPValues.sevenDayStreak)
        XCTAssertEqual(GamificationService.streakMilestoneXP(from: 7, to: 7), 0)
        XCTAssertEqual(GamificationService.streakMilestoneXP(from: 29, to: 30), XPValues.thirtyDayStreak)
        XCTAssertEqual(GamificationService.streakMilestoneXP(from: 6, to: 30), XPValues.sevenDayStreak + XPValues.thirtyDayStreak)
    }

    func testConsecutiveDayRun() {
        XCTAssertEqual(GamificationService.consecutiveDayRun([]), 0)
        XCTAssertEqual(GamificationService.consecutiveDayRun([day(0), day(-1), day(-2)]), 3)
        XCTAssertEqual(GamificationService.consecutiveDayRun([day(-1), day(-2)]), 2)   // today not done yet
        XCTAssertEqual(GamificationService.consecutiveDayRun([day(0), day(-2)]), 1)    // gap breaks the run
        XCTAssertEqual(GamificationService.consecutiveDayRun([day(-3)]), 0)
    }

    func testSevenCheckInsUnlockWeekOfMornings() throws {
        let context = try makeContext()
        for offset in 0..<7 {
            let checkIn = MorningCheckIn(date: day(-offset))
            checkIn.isComplete = true
            context.insert(checkIn)
        }
        let service = GamificationService()
        service.checkAchievements(profile: UserProfile(), context: context)
        XCTAssertTrue(service.pendingAchievements.contains { $0.achievementID == AchievementID.sleepWeek.rawValue })
    }

    // MARK: Keychain

    func testKeychainRoundTripAndDelete() {
        let account = "apex_test_account"
        defer { KeychainStore.set("", for: account) }
        XCTAssertTrue(KeychainStore.set("secret-1", for: account))
        XCTAssertEqual(KeychainStore.get(account), "secret-1")
        XCTAssertTrue(KeychainStore.set("secret-2", for: account))   // overwrite
        XCTAssertEqual(KeychainStore.get(account), "secret-2")
        XCTAssertTrue(KeychainStore.set("", for: account))           // delete
        XCTAssertNil(KeychainStore.get(account))
    }

    func testLegacyUserDefaultsKeyMovesToKeychain() {
        let name = UserDefaultsKeys.claudeAPIKey
        let ud = UserDefaults.standard
        let oldKeychain = KeychainStore.get(name), oldDefaults = ud.string(forKey: name)
        defer {
            KeychainStore.set(oldKeychain ?? "", for: name)
            if let oldDefaults { ud.set(oldDefaults, forKey: name) } else { ud.removeObject(forKey: name) }
        }
        KeychainStore.set("", for: name)
        ud.set("legacy-key", forKey: name)

        let ai = ClaudeService()

        XCTAssertEqual(ai.apiKey(for: .gemini), "legacy-key")
        XCTAssertEqual(KeychainStore.get(name), "legacy-key")
        XCTAssertNil(ud.string(forKey: name), "plaintext copy should be removed")
    }

    // MARK: Missing Health data

    func testNoHealthDataIsUnknownNotLow() {
        XCTAssertEqual(MorningCheckIn.sleepScore(hours: 0, hrv: 0), 0)
        XCTAssertEqual(MorningCheckIn.recoveryRating(score: 0), "Unknown")
        XCTAssertEqual(MorningCheckIn.sleepScore(hours: 7.5, hrv: 100), 100)
        XCTAssertEqual(MorningCheckIn.recoveryRating(score: 15), "Low")
        XCTAssertGreaterThan(MorningCheckIn.sleepScore(hours: 8, hrv: 0), 0)   // sleep alone still scores
    }

    func testHealthReadTypesCoverEveryFetcher() {
        let needed: [HKObjectType] = [
            HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.appleExerciseTime),
            HKQuantityType(.restingHeartRate), HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.vo2Max),
            HKQuantityType(.respiratoryRate), HKQuantityType(.bodyMass), HKCategoryType(.sleepAnalysis),
            HKCategoryType(.mindfulSession), HKObjectType.activitySummaryType(), HKObjectType.workoutType(),
        ]
        for type in needed {
            XCTAssertTrue(HealthKitService.readTypes.contains(type), "\(type) is read but not requested")
        }
    }

    // MARK: Body figure

    func testBodyFigureRegionsAreValid() {
        let bounds = CGRect(origin: .zero, size: BodyFigure.canvas).insetBy(dx: -1, dy: -1)
        for side in [BodyFigure.Side.front, .back] {
            let regions = BodyFigure.regions(side)
            XCTAssertFalse(regions.isEmpty)
            var groups = Set<MuscleGroup>()
            for region in regions {
                XCTAssertFalse(region.path.isEmpty)
                XCTAssertTrue(bounds.contains(region.path.boundingBox), "\(region.group ?? "neutral") region leaves the canvas")
                if let name = region.group {
                    guard let group = MuscleGroup(rawValue: name) else { return XCTFail("unknown group \(name)") }
                    XCTAssertTrue(MuscleGroupTracker.trackedGroups.contains(group))
                    groups.insert(group)
                }
            }
            let expected: Set<MuscleGroup> = side == .front
                ? [.chest, .shoulders, .biceps, .core, .legs]
                : [.back, .shoulders, .triceps, .legs]
            XCTAssertEqual(groups, expected, "\(side) shows the wrong muscle groups")
        }
    }

    // MARK: Heat scale

    func testHeatScaleGoesFromBlueToRed() {
        func rgb(_ c: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            return (r, g, b)
        }
        for scheme in [ColorScheme.light, .dark] {
            let low = rgb(MuscleGroupTracker.heatColor(sets: 1, scheme: scheme))
            let high = rgb(MuscleGroupTracker.heatColor(sets: 10, scheme: scheme))
            XCTAssertGreaterThan(low.b, low.r, "1 set should be blue")
            XCTAssertGreaterThan(high.r, high.b, "10 sets should be red")
            XCTAssertEqual(MuscleGroupTracker.heatColor(sets: 0, scheme: scheme), MuscleGroupTracker.coolColor(scheme))
            XCTAssertEqual(MuscleGroupTracker.heatColor(sets: 25, scheme: scheme), MuscleGroupTracker.heatColor(sets: 10, scheme: scheme))
        }
    }

    // MARK: AI providers

    private func spec(image: Bool = false, json: Bool = false) -> AIRequestSpec {
        AIRequestSpec(
            system: "sys",
            messages: [AIMessage(role: .user, text: "hi"), AIMessage(role: .assistant, text: "yo"), AIMessage(role: .user, text: "again")],
            maxTokens: 300, wantsJSON: json, imageJPEG: image ? Data([1, 2, 3]) : nil
        )
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testKeysTravelInHeadersNeverTheURL() throws {
        for provider in AIProvider.allCases where provider.isCloud {
            let request = try provider.urlRequest(spec(), apiKey: "SECRET-KEY", model: provider.defaultModel)
            XCTAssertFalse(request.url!.absoluteString.contains("SECRET-KEY"), "\(provider) puts the key in the URL")
            XCTAssertTrue((request.allHTTPHeaderFields ?? [:]).values.joined().contains("SECRET-KEY"), "\(provider) sends no key")
            XCTAssertEqual(request.httpMethod, "POST")
        }
    }

    func testGeminiRequestShape() throws {
        let request = try AIProvider.gemini.urlRequest(spec(image: true), apiKey: "K", model: "gemini-test")
        XCTAssertEqual(request.url?.host, "generativelanguage.googleapis.com")
        XCTAssertTrue(request.url!.path.hasSuffix("gemini-test:generateContent"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "K")
        let json = try body(request)
        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.map { $0["role"] as? String }, ["user", "model", "user"])
        XCTAssertEqual((contents[0]["parts"] as? [Any])?.count, 1)
        let lastParts = try XCTUnwrap(contents[2]["parts"] as? [[String: Any]])
        XCTAssertEqual(lastParts.count, 2, "image goes on the last user message")
        XCTAssertEqual((lastParts[1]["inline_data"] as? [String: Any])?["mime_type"] as? String, "image/jpeg")
        XCTAssertNotNil(json["systemInstruction"])
        XCTAssertEqual((json["generationConfig"] as? [String: Any])?["maxOutputTokens"] as? Int, 300 + AIProvider.reasoningHeadroom)
    }

    func testOpenAIRequestShape() throws {
        let request = try AIProvider.openai.urlRequest(spec(image: true, json: true), apiKey: "K", model: "gpt-test")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer K")
        let json = try body(request)
        XCTAssertEqual(json["model"] as? String, "gpt-test")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user", "assistant", "user"])
        let last = try XCTUnwrap(messages[3]["content"] as? [[String: Any]])
        let url = try XCTUnwrap((last[1]["image_url"] as? [String: Any])?["url"] as? String)
        XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertEqual((json["response_format"] as? [String: Any])?["type"] as? String, "json_object")
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 300 + AIProvider.reasoningHeadroom)
        let plain = try body(AIProvider.openai.urlRequest(spec(), apiKey: "K", model: "m"))
        XCTAssertNil(plain["response_format"])
    }

    func testAnthropicRequestShape() throws {
        let request = try AIProvider.anthropic.urlRequest(spec(image: true), apiKey: "K", model: "claude-test")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "K")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let json = try body(request)
        XCTAssertEqual(json["system"] as? String, "sys")
        XCTAssertEqual(json["max_tokens"] as? Int, 300)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
        let blocks = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(blocks[0]["type"] as? String, "image")
        let source = try XCTUnwrap(blocks[0]["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["type"] as? String, "base64")
    }

    func testLocalRequestShapeAndNoImages() throws {
        let request = try AIProvider.local.urlRequest(spec(json: true), apiKey: "", model: "llama-test", localBaseURL: "http://10.0.0.5:11434")
        XCTAssertEqual(request.url?.absoluteString, "http://10.0.0.5:11434/api/chat")
        let json = try body(request)
        XCTAssertEqual(json["model"] as? String, "llama-test")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual(json["format"] as? String, "json")
        XCTAssertEqual((json["options"] as? [String: Any])?["num_predict"] as? Int, 300 + AIProvider.reasoningHeadroom)
        XCTAssertThrowsError(try AIProvider.local.urlRequest(spec(image: true), apiKey: "", model: "m", localBaseURL: "http://x"))
    }

    func testReplyParsingPerProvider() throws {
        func data(_ s: String) -> Data { Data(s.utf8) }
        XCTAssertEqual(try AIProvider.gemini.parseReply(data(#"{"candidates":[{"content":{"parts":[{"text":"hel"},{"text":"lo"}]}}]}"#)), "hello")
        XCTAssertEqual(try AIProvider.openai.parseReply(data(#"{"choices":[{"message":{"content":"hello"}}]}"#)), "hello")
        XCTAssertEqual(try AIProvider.anthropic.parseReply(data(#"{"content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"hel"},{"type":"text","text":"lo"}]}"#)), "hello")
        XCTAssertEqual(try AIProvider.local.parseReply(data(#"{"message":{"content":"hello"}}"#)), "hello")
        for provider in AIProvider.allCases {
            XCTAssertThrowsError(try provider.parseReply(data("not json")), "\(provider) accepted garbage")
            XCTAssertThrowsError(try provider.parseReply(data("{}")), "\(provider) accepted an empty reply")
        }
        XCTAssertThrowsError(try AIProvider.local.parseReply(data(#"{"message":{"content":"","thinking":"hidden"}}"#)))
    }

    func testProviderKeysModelsAndConsentAreSeparate() {
        let ai = ClaudeService()
        let providers: [AIProvider] = [.gemini, .openai, .anthropic]
        let oldKeys = providers.map { ai.apiKey(for: $0) }
        let oldConsent = providers.map { ai.consent(for: $0) }
        defer {
            for (i, p) in providers.enumerated() { ai.setAPIKey(oldKeys[i], for: p); ai.setConsent(oldConsent[i], for: p); ai.setModel("", for: p) }
        }
        ai.setAPIKey("g-key", for: .gemini)
        ai.setAPIKey("o-key", for: .openai)
        ai.setAPIKey("a-key", for: .anthropic)
        XCTAssertEqual([ai.apiKey(for: .gemini), ai.apiKey(for: .openai), ai.apiKey(for: .anthropic)], ["g-key", "o-key", "a-key"])
        XCTAssertEqual(AIProvider.gemini.keychainAccount, "apex_claude_api_key", "Gemini keeps the account earlier builds used")

        ai.setConsent(true, for: .openai)
        ai.setConsent(false, for: .anthropic)
        XCTAssertTrue(ai.consent(for: .openai))
        XCTAssertFalse(ai.consent(for: .anthropic))

        XCTAssertEqual(ai.model(for: .openai), AIProvider.openai.defaultModel)
        ai.setModel("gpt-custom", for: .openai)
        XCTAssertEqual(ai.model(for: .openai), "gpt-custom")
        ai.setModel("  ", for: .openai)
        XCTAssertEqual(ai.model(for: .openai), AIProvider.openai.defaultModel)
    }

    func testMissingKeyAndConsentErrorsNameTheProvider() async {
        let ai = ClaudeService()
        let oldProvider = ai.provider, oldKey = ai.apiKey(for: .openai), oldConsent = ai.consent(for: .openai)
        defer { ai.setAPIKey(oldKey, for: .openai); ai.setConsent(oldConsent, for: .openai); ai.setProvider(oldProvider) }
        ai.setProvider(.openai)
        ai.setAPIKey("", for: .openai)
        XCTAssertFalse(ai.isConfigured)
        do {
            _ = try await ai.analyzeMealText("oats")
            XCTFail("expected noAPIKey")
        } catch let error as ClaudeError {
            guard case .noAPIKey(let name) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(name, "OpenAI")
        } catch { XCTFail("unexpected \(error)") }

        ai.setAPIKey("k", for: .openai)
        ai.setConsent(false, for: .openai)
        XCTAssertTrue(ai.isConfigured)
        do {
            _ = try await ai.analyzeMealText("oats")
            XCTFail("expected consentRequired")
        } catch let error as ClaudeError {
            guard case .consentRequired(let company) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(company, "OpenAI")
        } catch { XCTFail("unexpected \(error)") }
    }

    // MARK: Plan timing

    func testNextPlanBlock() {
        let times = ["07:00", "08:30", "13:00", "22:00"]
        XCTAssertEqual(PlanTiming.nextIndex(times: times, now: 6 * 60), 0)
        XCTAssertEqual(PlanTiming.nextIndex(times: times, now: 8 * 60 + 30), 1, "a block starting now is next")
        XCTAssertEqual(PlanTiming.nextIndex(times: times, now: 9 * 60), 2)
        XCTAssertEqual(PlanTiming.nextIndex(times: times, now: 23 * 60), 3, "after the last block, show the last one")
        XCTAssertNil(PlanTiming.nextIndex(times: [], now: 600))
        XCTAssertNil(PlanTiming.nextIndex(times: ["soon", "25:99"], now: 600))
        XCTAssertEqual(PlanTiming.nextIndex(times: ["??", "10:00"], now: 600), 1, "unparsable times are skipped")
        XCTAssertEqual(PlanTiming.minutes("07:05"), 425)
        XCTAssertNil(PlanTiming.minutes("7"))
    }

    // MARK: Provider errors and model lists

    func testProviderErrorDetailIsShown() {
        let gemini = #"{"error":{"code":404,"message":"models/gemini-x is not found for API version v1beta","status":"NOT_FOUND"}}"#
        let openai = #"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#
        let anthropic = #"{"type":"error","error":{"type":"not_found_error","message":"model: claude-x"}}"#
        XCTAssertEqual(AIProvider.errorDetail(fromBody: gemini), "models/gemini-x is not found for API version v1beta")
        XCTAssertEqual(AIProvider.errorDetail(fromBody: openai), "Incorrect API key provided")
        XCTAssertEqual(AIProvider.errorDetail(fromBody: anthropic), "model: claude-x")
        XCTAssertNil(AIProvider.errorDetail(fromBody: "<html>bad gateway</html>"))
        XCTAssertNil(AIProvider.errorDetail(fromBody: ""))

        let notFound = ClaudeError.apiError(404, gemini).errorDescription ?? ""
        XCTAssertTrue(notFound.contains("not found for API version"))
        XCTAssertTrue(notFound.contains("Find available models"), "404 should point at the model finder")
        XCTAssertTrue((ClaudeError.apiError(401, openai).errorDescription ?? "").contains("Incorrect API key provided"))
        XCTAssertEqual(ClaudeError.apiError(429, gemini).errorDescription, "AI quota reached. Wait a bit and try again.")
    }

    func testModelListRequestsAndParsing() throws {
        for provider in AIProvider.allCases where provider.isCloud {
            let request = try XCTUnwrap(provider.modelsRequest(apiKey: "SECRET-KEY"))
            XCTAssertFalse(request.url!.absoluteString.contains("SECRET-KEY"))
            XCTAssertTrue((request.allHTTPHeaderFields ?? [:]).values.joined().contains("SECRET-KEY"))
        }
        XCTAssertNil(AIProvider.local.modelsRequest(apiKey: ""))

        let gemini = Data(#"{"models":[{"name":"models/gemini-b","supportedGenerationMethods":["generateContent"]},{"name":"models/embedding-1","supportedGenerationMethods":["embedContent"]},{"name":"models/gemini-a","supportedGenerationMethods":["generateContent","countTokens"]}]}"#.utf8)
        XCTAssertEqual(AIProvider.gemini.parseModels(gemini), ["gemini-a", "gemini-b"])
        let openai = Data(#"{"data":[{"id":"gpt-4o"},{"id":"text-embedding-3-small"},{"id":"o3-mini"},{"id":"whisper-1"},{"id":"gpt-4o"}]}"#.utf8)
        XCTAssertEqual(AIProvider.openai.parseModels(openai), ["gpt-4o", "o3-mini"])
        let anthropic = Data(#"{"data":[{"id":"claude-b"},{"id":"claude-a"}]}"#.utf8)
        XCTAssertEqual(AIProvider.anthropic.parseModels(anthropic), ["claude-a", "claude-b"])
        XCTAssertEqual(AIProvider.gemini.parseModels(Data("nope".utf8)), [])
    }
}
