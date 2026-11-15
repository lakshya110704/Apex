import Foundation
import SwiftData

@Model
final class DailyPlan {
    var id: UUID
    var date: Date
    var planText: String          // Claude's generated plan (markdown)
    var userModifications: String // Chat history with user changes
    var isCompleted: Bool
    var xpEarned: Int
    var generatedAt: Date

    init(date: Date = Date(), planText: String = "", userModifications: String = "") {
        self.id = UUID()
        self.date = date
        self.planText = planText
        self.userModifications = userModifications
        self.isCompleted = false
        self.xpEarned = 0
        self.generatedAt = Date()
    }
}

// MARK: - Chat Message (saved through CoachMessageRecord)

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }

    init(id: UUID, role: ChatRole, content: String, timestamp: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

enum ChatRole: String, Codable {
    case user      = "user"
    case assistant = "assistant"
    case system    = "system"
}
