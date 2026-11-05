import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String
    var xpPoints: Int
    var workoutStreak: Int
    var mealStreak: Int
    var lastWorkoutDate: Date?
    var lastMealDate: Date?
    var claudeAPIKey: String
    var githubUsername: String
    var createdAt: Date

    // Computed helpers (non-persisted)
    var level: Int { LevelThresholds.level(for: xpPoints) }
    var levelProgress: Double { LevelThresholds.progress(for: xpPoints) }
    var xpForNextLevel: Int { LevelThresholds.xpForNextLevel(currentXP: xpPoints) }

    init(name: String = "", claudeAPIKey: String = "", githubUsername: String = "") {
        self.name = name
        self.xpPoints = 0
        self.workoutStreak = 0
        self.mealStreak = 0
        self.claudeAPIKey = claudeAPIKey
        self.githubUsername = githubUsername
        self.createdAt = Date()
    }
}
