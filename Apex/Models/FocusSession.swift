import Foundation
import SwiftData

@Model
final class FocusSession {
    var projectName: String
    var projectCategory: String   // stored as raw value
    var durationMinutes: Int
    var startTime: Date
    var endTime: Date?
    var date: Date

    var category: ProjectCategory {
        ProjectCategory(rawValue: projectCategory) ?? .personal
    }

    init(projectName: String, projectCategory: ProjectCategory, durationMinutes: Int) {
        self.projectName = projectName
        self.projectCategory = projectCategory.rawValue
        self.durationMinutes = durationMinutes
        self.startTime = Date()
        self.date = Date()
    }
}
