import Foundation
import SwiftData

enum MuscleGroup: String, Codable, CaseIterable {
    case chest      = "Chest"
    case back       = "Back"
    case legs       = "Legs"
    case shoulders  = "Shoulders"
    case biceps     = "Biceps"
    case triceps    = "Triceps"
    case core       = "Core"
    case fullBody   = "Full Body"
    case cardio     = "Cardio"

    var systemImage: String {
        switch self {
        case .chest:     return "heart.fill"
        case .back:      return "arrow.up.backward.and.arrow.down.forward"
        case .legs:      return "figure.walk"
        case .shoulders: return "figure.arms.open"
        case .biceps:    return "hand.raised.fill"
        case .triceps:   return "hand.point.up.fill"
        case .core:      return "circle.grid.cross.fill"
        case .fullBody:  return "figure.mixed.cardio"
        case .cardio:    return "heart.circle.fill"
        }
    }
}

@Model
final class GymExercise {
    var name: String
    var muscleGroup: MuscleGroup
    var sets: Int
    var reps: Int
    var weightKg: Double
    var videoURL: String
    var order: Int
    var notes: String

    init(
        name: String,
        muscleGroup: MuscleGroup = .fullBody,
        sets: Int = 3,
        reps: Int = 10,
        weightKg: Double = 0,
        videoURL: String = "",
        order: Int = 0,
        notes: String = ""
    ) {
        self.name = name
        self.muscleGroup = muscleGroup
        self.sets = sets
        self.reps = reps
        self.weightKg = weightKg
        self.videoURL = videoURL
        self.order = order
        self.notes = notes
    }

    var volumeKg: Double { Double(sets * reps) * weightKg }

    var weightFormatted: String {
        weightKg == 0 ? "Bodyweight" : String(format: "%.1f kg", weightKg)
    }
}
