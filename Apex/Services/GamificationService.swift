import Foundation
import SwiftData

@Observable
final class GamificationService {

    var pendingAchievements: [Achievement] = []  // newly unlocked, shown as toasts
    var xpAnimationAmount: Int = 0               // triggers floating XP animation

    let notifications = NotificationService()

    // MARK: - XP Awarding

    @discardableResult
    func awardXP(_ amount: Int, to profile: UserProfile) -> Int {
        profile.xpPoints += amount
        xpAnimationAmount = amount
        return amount
    }

    // MARK: - Workout XP

    func processWorkout(_ workout: WorkoutSession, profile: UserProfile, context: ModelContext) {
        let xp: Int
        switch workout.type {
        case .tennis: xp = XPValues.logTennisSession
        case .gym:    xp = XPValues.logGymWorkout
        case .run:    xp = XPValues.logGymWorkout
        case .other:  xp = XPValues.logGymWorkout / 2
        }
        workout.xpEarned = xp
        awardXP(xp, to: profile)
        let streakBefore = profile.workoutStreak
        updateWorkoutStreak(profile: profile)
        awardXP(Self.streakMilestoneXP(from: streakBefore, to: profile.workoutStreak), to: profile)
        checkAchievements(profile: profile, context: context)
        notifications.cancelReminder()
    }

    // MARK: - Meal XP

    func processMeal(_ meal: MealEntry, profile: UserProfile, context: ModelContext) {
        meal.xpEarned = XPValues.logMeal
        awardXP(XPValues.logMeal, to: profile)
        updateMealStreak(profile: profile)
        checkAchievements(profile: profile, context: context)
        notifications.cancelReminder()
    }

    // MARK: - Streak Management

    func updateWorkoutStreak(profile: UserProfile) {
        let today = Calendar.current.startOfDay(for: Date())
        guard let last = profile.lastWorkoutDate else {
            profile.workoutStreak = 1
            profile.lastWorkoutDate = today
            return
        }
        let daysSinceLast = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last), to: today).day ?? 0
        if daysSinceLast == 0 {
            // already logged today, don't increment streak
        } else if daysSinceLast == 1 {
            profile.workoutStreak += 1
            profile.lastWorkoutDate = today
        } else {
            profile.workoutStreak = 1
            profile.lastWorkoutDate = today
        }
    }

    func updateMealStreak(profile: UserProfile) {
        let today = Calendar.current.startOfDay(for: Date())
        guard let last = profile.lastMealDate else {
            profile.mealStreak = 1
            profile.lastMealDate = today
            return
        }
        let daysSinceLast = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last), to: today).day ?? 0
        if daysSinceLast == 0 {
            // already logged today
        } else if daysSinceLast == 1 {
            profile.mealStreak += 1
            profile.lastMealDate = today
        } else {
            profile.mealStreak = 1
            profile.lastMealDate = today
        }
    }

    /// Bonus XP for crossing the 7 and 30 day workout streak marks in a single update.
    static func streakMilestoneXP(from before: Int, to after: Int) -> Int {
        var xp = 0
        if before < 7 && after >= 7 { xp += XPValues.sevenDayStreak }
        if before < 30 && after >= 30 { xp += XPValues.thirtyDayStreak }
        return xp
    }

    /// Length of the run of consecutive days ending today or yesterday.
    static func consecutiveDayRun(_ dates: [Date]) -> Int {
        let days = Set(dates.map(\.startOfDay))
        let cal = Calendar.current
        var cursor = Date().startOfDay
        if !days.contains(cursor) { cursor = cal.date(byAdding: .day, value: -1, to: cursor)! }
        var run = 0
        while days.contains(cursor) {
            run += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return run
    }

    // MARK: - Achievement Checking

    func checkAchievements(profile: UserProfile, context: ModelContext) {
        let allWorkouts = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let allMeals    = (try? context.fetch(FetchDescriptor<MealEntry>())) ?? []
        let allAchievements = fetchOrCreateAchievements(context: context)

        let checkIns = (try? context.fetch(FetchDescriptor<MorningCheckIn>())) ?? []
        let checkInRun = Self.consecutiveDayRun(checkIns.filter(\.isComplete).map(\.date))

        let tennisCount = allWorkouts.filter { $0.type == .tennis }.count
        let gymCount    = allWorkouts.filter { $0.type == .gym }.count

        let checks: [(AchievementID, Bool)] = [
            (.firstWorkout,   !allWorkouts.isEmpty),
            (.firstMeal,      !allMeals.isEmpty),
            (.firstTennis,    tennisCount >= 1),
            (.fiveTennis,     tennisCount >= 5),
            (.twentyTennis,   tennisCount >= 20),
            (.tenGym,         gymCount >= 10),
            (.fiftyWorkouts,  allWorkouts.count >= 50),
            (.tenMeals,       allMeals.count >= 10),
            (.fiftyMeals,     allMeals.count >= 50),
            (.threeDayStreak, profile.workoutStreak >= 3),
            (.sevenDayStreak, profile.workoutStreak >= 7),
            (.thirtyDayStreak,profile.workoutStreak >= 30),
            (.thousandXP,     profile.xpPoints >= 1000),
            (.levelFive,      profile.level >= 5),
            (.sleepWeek,      checkInRun >= 7),
        ]

        for (id, condition) in checks {
            guard condition,
                  let achievement = allAchievements.first(where: { $0.achievementID == id.rawValue }),
                  !achievement.isUnlocked
            else { continue }

            achievement.unlock()
            awardXP(achievement.xpReward, to: profile)
            pendingAchievements.append(achievement)
        }
    }

    // MARK: - Seed Achievements if Needed

    func fetchOrCreateAchievements(context: ModelContext) -> [Achievement] {
        let existing = (try? context.fetch(FetchDescriptor<Achievement>())) ?? []
        if existing.count == AchievementID.allCases.count { return existing }

        // Seed any missing ones
        let existingIDs = Set(existing.map(\.achievementID))
        for id in AchievementID.allCases where !existingIDs.contains(id.rawValue) {
            let achievement = Achievement(id: id)
            context.insert(achievement)
        }
        return (try? context.fetch(FetchDescriptor<Achievement>())) ?? []
    }

    // MARK: - Pop Achievement Toast

    func popNextAchievement() -> Achievement? {
        guard !pendingAchievements.isEmpty else { return nil }
        return pendingAchievements.removeFirst()
    }
}
