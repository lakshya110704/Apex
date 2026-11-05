import Foundation
import SwiftData

@Model
final class EveningCheckIn {
    var date: Date
    var moodRating: Int           // 1–5
    var accomplishments: String   // user's raw text
    var aiSummary: String         // AI-parsed summary
    var tomorrowPriority: String  // one key thing for tomorrow
    var isComplete: Bool

    init(date: Date = Date()) {
        self.date = date
        self.moodRating = 3
        self.accomplishments = ""
        self.aiSummary = ""
        self.tomorrowPriority = ""
        self.isComplete = false
    }
}
