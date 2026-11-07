import XCTest
import SwiftData
import HealthKit
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
        let oldKey = ai.apiKey, oldConsent = ai.aiConsentGiven
        defer { ai.setAPIKey(oldKey); ai.setAIConsent(oldConsent) }
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
        XCTAssertTrue(ClaudeError.consentRequired.errorDescription?.contains("Settings") == true)
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

        XCTAssertEqual(ai.apiKey, "legacy-key")
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
}
