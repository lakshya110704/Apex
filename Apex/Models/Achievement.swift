import Foundation
import SwiftData

@Model
final class Achievement {
    var achievementID: String
    var name: String
    var achievementDescription: String
    var iconName: String
    var xpReward: Int
    var isUnlocked: Bool
    var dateUnlocked: Date?

    init(id: AchievementID) {
        let info = id.info
        self.achievementID = id.rawValue
        self.name = info.name
        self.achievementDescription = info.description
        self.iconName = info.icon
        self.xpReward = info.xpReward
        self.isUnlocked = false
        self.dateUnlocked = nil
    }

    func unlock() {
        guard !isUnlocked else { return }
        isUnlocked = true
        dateUnlocked = Date()
    }
}
