import Foundation
import SwiftData

enum WorkoutType: String, Codable, CaseIterable {
    case tennis = "Tennis"
    case gym    = "Gym"
    case run    = "Run"
    case other  = "Other"

    var systemImage: String {
        switch self {
        case .tennis: return "figure.tennis"
        case .gym:    return "dumbbell.fill"
        case .run:    return "figure.run"
        case .other:  return "figure.mixed.cardio"
        }
    }
}

@Model
final class WorkoutSession {
    var id: UUID
    var date: Date
    var type: WorkoutType
    var durationMinutes: Int
    var averageHeartRate: Int
    var caloriesBurned: Int
    var notes: String
    var xpEarned: Int
    var importedFromHealthKit: Bool
    var healthKitUUID: String?  // HKWorkout UUID, prevents double-import

    // Tennis details (encoded as JSON string to avoid optional relationship complexity)
    var tennisDetailsJSON: String?

    // Gym exercises stored as separate models linked by session ID
    @Relationship(deleteRule: .cascade)
    var gymExercises: [GymExercise]

    init(
        date: Date = Date(),
        type: WorkoutType,
        durationMinutes: Int = 0,
        averageHeartRate: Int = 0,
        caloriesBurned: Int = 0,
        notes: String = "",
        xpEarned: Int = 0,
        importedFromHealthKit: Bool = false,
        healthKitUUID: String? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.type = type
        self.durationMinutes = durationMinutes
        self.averageHeartRate = averageHeartRate
        self.caloriesBurned = caloriesBurned
        self.notes = notes
        self.xpEarned = xpEarned
        self.importedFromHealthKit = importedFromHealthKit
        self.healthKitUUID = healthKitUUID
        self.gymExercises = []
    }

    var durationFormatted: String {
        let hours = durationMinutes / 60
        let mins  = durationMinutes % 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}

// MARK: - Tennis Details

struct TennisDetails: Codable {
    var court: String
    var opponent: String
    var setsWon: Int
    var setsLost: Int
    var gamesWon: Int
    var gamesLost: Int
    var drillsPracticed: [String]

    var scoreFormatted: String {
        guard setsWon > 0 || setsLost > 0 else { return "Drills only" }
        return "Sets: \(setsWon)–\(setsLost)"
    }
}

extension WorkoutSession {
    var tennisDetails: TennisDetails? {
        get {
            guard let json = tennisDetailsJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(TennisDetails.self, from: data)
        }
        set {
            if let val = newValue,
               let data = try? JSONEncoder().encode(val) {
                tennisDetailsJSON = String(data: data, encoding: .utf8)
            } else {
                tennisDetailsJSON = nil
            }
        }
    }
}
