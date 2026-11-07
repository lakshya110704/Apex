import SwiftUI

// MARK: - Design System

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

private func adaptiveUIColor(light: UInt32, dark: UInt32) -> UIColor {
    UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
}

private func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(adaptiveUIColor(light: light, dark: dark))
}

/// One accent (blue). Status colors are only for status. Every color adapts to light and dark.
enum ApexColor {
    static let background    = adaptive(light: 0xF2F3F6, dark: 0x0B0C0F)
    static let cardBg        = adaptive(light: 0xFFFFFF, dark: 0x16181D)
    static let cardBg2       = adaptive(light: 0xE7E9EE, dark: 0x22252C)
    static let accent        = adaptive(light: 0x0A5CFF, dark: 0x4C8DFF)
    static let accentCyan    = accent   // secondary accent retired; kept so call sites stay valid
    static let success       = adaptive(light: 0x0B8A4A, dark: 0x2FD67B)
    static let warning       = adaptive(light: 0xC77800, dark: 0xFFB224)
    static let danger        = adaptive(light: 0xD6303A, dark: 0xFF5C61)
    static let tennis        = adaptive(light: 0x4F9A00, dark: 0xB8F13F)
    static let textPrimary   = adaptive(light: 0x0B0C0F, dark: 0xFFFFFF)
    static let textSecondary = adaptive(light: 0x5E6370, dark: 0x9AA0AE)
    /// Text drawn on top of an accent or status color fill.
    static let onAccent      = adaptive(light: 0xFFFFFF, dark: 0x0B0C0F)
    static let tabBar        = adaptiveUIColor(light: 0xFFFFFF, dark: 0x16181D)
}

// MARK: - Gamification

enum XPValues {
    static let logGymWorkout    = 60
    static let logTennisSession = 80
    static let logMeal          = 25
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
    static let aiConsent     = "apex_ai_consent"
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
            return ("Week of Mornings", "Complete 7 morning check-ins in a row", "moon.zzz.fill", 150)
        }
    }
}

