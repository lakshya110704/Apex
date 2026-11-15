import Foundation
import SwiftData

// MARK: - Saved coach chat

/// One chat message, kept so the coach conversation survives closing the app.
@Model
final class CoachMessageRecord {
    var id: UUID
    var roleRaw: String
    var content: String
    var timestamp: Date

    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .user }
    var chatMessage: ChatMessage { ChatMessage(id: id, role: role, content: content, timestamp: timestamp) }

    init(_ message: ChatMessage) {
        self.id = message.id
        self.roleRaw = message.role.rawValue
        self.content = message.content
        self.timestamp = message.timestamp
    }
}

// MARK: - Long-term memory

enum CoachMemoryKind: String, CaseIterable, Codable {
    case goal
    case note

    var label: String { self == .goal ? "Goal" : "Note" }
    var pluralLabel: String { self == .goal ? "Goals" : "Notes" }
    var icon: String { self == .goal ? "target" : "pin.fill" }
}

/// A lasting fact the coach should know in every conversation: a goal ("sub-20 5k by March")
/// or a note ("left knee is sore, no box jumps"). Saved by the coach from chat or typed by the user.
@Model
final class CoachMemory {
    var id: UUID
    var kindRaw: String
    var text: String
    var createdAt: Date
    var addedByCoach: Bool

    var kind: CoachMemoryKind { CoachMemoryKind(rawValue: kindRaw) ?? .note }
    var item: CoachMemoryEngine.Item { .init(kind: kind, text: text, createdAt: createdAt) }

    init(kind: CoachMemoryKind, text: String, addedByCoach: Bool, createdAt: Date = Date()) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.text = text
        self.createdAt = createdAt
        self.addedByCoach = addedByCoach
    }
}
