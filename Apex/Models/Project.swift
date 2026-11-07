import Foundation
import SwiftData

enum ProjectCategory: String, Codable, CaseIterable {
    case startup    = "Startup"
    case study      = "Study"
    case fitness    = "Fitness"
    case personal   = "Personal"
    case work       = "Work"
    case creative   = "Creative"

    var systemImage: String {
        switch self {
        case .startup:  return "flame.fill"
        case .study:    return "book.fill"
        case .fitness:  return "dumbbell.fill"
        case .personal: return "person.fill"
        case .work:     return "briefcase.fill"
        case .creative: return "paintbrush.fill"
        }
    }

    var color: String {
        switch self {
        case .startup:  return "accent"
        case .study:    return "accentCyan"
        case .fitness:  return "tennis"
        case .personal: return "warning"
        case .work:     return "success"
        case .creative: return "danger"
        }
    }
}

@Model
final class Project {
    var name: String
    var category: ProjectCategory
    var isActive: Bool
    var createdAt: Date
    var lastFocusedAt: Date?
    var totalFocusDays: Int

    init(name: String, category: ProjectCategory) {
        self.name = name
        self.category = category
        self.isActive = true
        self.createdAt = Date()
        self.totalFocusDays = 0
    }
}

@Model
final class MorningCheckIn {
    var date: Date
    var energyLevel: Int        // 1–5
    var sleepScore: Int         // 0–100
    var recoveryRating: String  // "Low" / "Moderate" / "High" / "Peak"
    var focusProjectIDs: [String]    // Project persistent IDs as strings
    var focusProjectNames: [String]  // Names for quick AI context lookup
    var customFocusNote: String
    var aiMotivation: String
    var isComplete: Bool

    init(date: Date = Date()) {
        self.date = date
        self.energyLevel = 3
        self.sleepScore = 0
        self.recoveryRating = "Moderate"
        self.focusProjectIDs = []
        self.focusProjectNames = []
        self.customFocusNote = ""
        self.aiMotivation = ""
        self.isComplete = false
    }

    static func sleepScore(hours: Double, hrv: Double) -> Int {
        guard hours > 0 || hrv > 0 else { return 0 }   // no Health data, not a bad night
        var score = 0
        // Sleep duration (60 pts)
        switch hours {
        case 7.5...:    score += 60
        case 7..<7.5:   score += 55
        case 6..<7:     score += 40
        case 5..<6:     score += 25
        default:        score += 10
        }
        // HRV (40 pts)
        switch hrv {
        case 100...:    score += 40
        case 70..<100:  score += 32
        case 50..<70:   score += 22
        case 30..<50:   score += 12
        default:        score += 5
        }
        return min(score, 100)
    }

    static func recoveryRating(score: Int) -> String {
        switch score {
        case ...0: return "Unknown"
        case 80...: return "Peak"
        case 60..<80: return "High"
        case 40..<60: return "Moderate"
        default: return "Low"
        }
    }
}
