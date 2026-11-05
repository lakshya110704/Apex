import SwiftUI

// MARK: - Design System

enum ApexColor {
    static let background    = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let cardBg        = Color(red: 0.08, green: 0.08, blue: 0.13)
    static let cardBg2       = Color(red: 0.11, green: 0.11, blue: 0.18)
    static let accent        = Color(red: 0.49, green: 0.36, blue: 0.99)  // #7C5CFC purple
    static let accentCyan    = Color(red: 0.0,  green: 0.83, blue: 1.0)   // #00D4FF
    static let success       = Color(red: 0.0,  green: 0.90, blue: 0.46)  // #00E676
    static let warning       = Color(red: 1.0,  green: 0.70, blue: 0.0)   // #FFB300
    static let danger        = Color(red: 1.0,  green: 0.27, blue: 0.27)  // #FF4545
    static let tennis        = Color(red: 0.56, green: 0.93, blue: 0.28)  // #8FEE47
    static let textPrimary   = Color.white
    static let textSecondary = Color(red: 0.53, green: 0.53, blue: 0.67)  // #8888AA
    static let deepPurple    = Color(red: 0.04, green: 0.02, blue: 0.12)  // morning gradient top
    static let tabBar        = UIColor(red: 0.08, green: 0.08, blue: 0.13, alpha: 1)
}

// MARK: - Gamification

enum XPValues {
    static let logGymWorkout    = 60
    static let logTennisSession = 80
    static let logMeal          = 25
    static let completeDailyPlan = 120
    static let hitActivityRing  = 30   // per ring
    static let logSleep         = 20
    static let sevenDayStreak   = 250
    static let thirtyDayStreak  = 1000
}

enum LevelThresholds {
    static let thresholds: [Int] = [
        0,     // Level 1
        500,   // Level 2
        1200,  // Level 3
        2500,  // Level 4
        5000,  // Level 5
        9000,  // Level 6
        15000, // Level 7
        25000, // Level 8
        40000, // Level 9
        60000  // Level 10
    ]

    static func level(for xp: Int) -> Int {
        var level = 1
        for (index, threshold) in thresholds.enumerated() where xp >= threshold {
            level = index + 1
        }
        return min(level, thresholds.count)
    }

    static func progress(for xp: Int) -> Double {
        let currentLevel = level(for: xp)
        guard currentLevel < thresholds.count else { return 1.0 }
        let currentThreshold = thresholds[currentLevel - 1]
        let nextThreshold = thresholds[currentLevel]
        let span = Double(nextThreshold - currentThreshold)
        guard span > 0 else { return 1.0 }
        return Double(xp - currentThreshold) / span
    }

    static func xpForNextLevel(currentXP: Int) -> Int {
        let currentLevel = level(for: currentXP)
        guard currentLevel < thresholds.count else { return 0 }
        return thresholds[currentLevel] - currentXP
    }
}

// MARK: - UserDefaults Keys

enum UserDefaultsKeys {
    static let claudeAPIKey  = "apex_claude_api_key"
    static let localAIHost   = "apex_local_ai_host"
    static let localAIPort   = "apex_local_ai_port"
    static let localAIModel  = "apex_local_ai_model"
}

// MARK: - Achievement IDs

enum AchievementID: String, CaseIterable {
    case firstWorkout      = "first_workout"
    case firstMeal         = "first_meal"
    case firstTennis       = "first_tennis"
    case fiveTennis        = "five_tennis"
    case twentyTennis      = "twenty_tennis"
    case tenGym            = "ten_gym"
    case fiftyWorkouts     = "fifty_workouts"
    case tenMeals          = "ten_meals"
    case fiftyMeals        = "fifty_meals"
    case threeDayStreak    = "three_day_streak"
    case sevenDayStreak    = "seven_day_streak"
    case thirtyDayStreak   = "thirty_day_streak"
    case thousandXP        = "thousand_xp"
    case levelFive         = "level_five"
    case sleepWeek         = "sleep_week"

    var info: (name: String, description: String, icon: String, xpReward: Int) {
        switch self {
        case .firstWorkout:
            return ("First Rep", "Log your first workout", "flame.fill", 50)
        case .firstMeal:
            return ("Food Photographer", "Log your first meal", "camera.fill", 25)
        case .firstTennis:
            return ("On The Court", "Log your first tennis session", "figure.tennis", 75)
        case .fiveTennis:
            return ("Regular Player", "Complete 5 tennis sessions", "sportscourt.fill", 100)
        case .twentyTennis:
            return ("Grand Slam", "Complete 20 tennis sessions", "trophy.fill", 300)
        case .tenGym:
            return ("Iron Habit", "Complete 10 gym workouts", "dumbbell.fill", 150)
        case .fiftyWorkouts:
            return ("Century Club", "Log 50 total workouts", "medal.fill", 500)
        case .tenMeals:
            return ("Foodie", "Log 10 meals", "fork.knife", 100)
        case .fiftyMeals:
            return ("Nutritionist", "Log 50 meals", "chart.bar.fill", 250)
        case .threeDayStreak:
            return ("On A Roll", "3-day activity streak", "bolt.fill", 75)
        case .sevenDayStreak:
            return ("Week Warrior", "7-day activity streak", "calendar.badge.checkmark", 200)
        case .thirtyDayStreak:
            return ("Monthly Master", "30-day activity streak", "crown.fill", 750)
        case .thousandXP:
            return ("XP Hunter", "Earn 1,000 total XP", "star.fill", 100)
        case .levelFive:
            return ("Elite", "Reach Level 5", "chevron.up.2", 200)
        case .sleepWeek:
            return ("Deep Sleeper", "Track sleep 7 days in a row", "moon.zzz.fill", 150)
        }
    }
}

