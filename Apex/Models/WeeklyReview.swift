import Foundation
import SwiftData

/// The coach's review of one week (Monday to Sunday), written on request and kept on device.
@Model
final class WeeklyReview {
    var id: UUID
    /// Monday 00:00 of the week reviewed.
    var weekStart: Date
    var createdAt: Date
    var text: String
    /// Schedule changes the coach suggested, as `[schedule ...]` tags (see `WeeklyReviewEngine.parse`).
    var suggestions: [String]
    /// The suggestions you accepted, which were added to your weekly schedule.
    var accepted: [String]

    init(weekStart: Date, text: String, suggestions: [String], createdAt: Date = Date()) {
        self.id = UUID()
        self.weekStart = weekStart
        self.createdAt = createdAt
        self.text = text
        self.suggestions = suggestions
        self.accepted = []
    }
}
