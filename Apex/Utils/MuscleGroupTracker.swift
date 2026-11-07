import SwiftUI

enum MuscleGroupTracker {

    enum RecoveryLevel {
        case restingToday   // trained today or yesterday
        case recovering     // 2-4 days ago
        case neglected      // 5-9 days ago
        case stale          // 10+ days ago or never trained

        var label: String {
            switch self {
            case .restingToday: return "Resting"
            case .recovering:   return "Recovering"
            case .neglected:    return "Neglected"
            case .stale:        return "Stale"
            }
        }

        var color: Color {
            switch self {
            case .restingToday: return ApexColor.textSecondary
            case .recovering:   return ApexColor.success
            case .neglected:    return ApexColor.warning
            case .stale:        return ApexColor.danger
            }
        }
    }

    struct Status: Identifiable {
        let muscleGroup: MuscleGroup
        let lastTrainedDate: Date?
        var id: MuscleGroup { muscleGroup }

        var daysSinceTrained: Int? {
            guard let lastTrainedDate else { return nil }
            return Calendar.current.dateComponents(
                [.day],
                from: lastTrainedDate.startOfDay,
                to: Date().startOfDay
            ).day
        }

        var recoveryLevel: RecoveryLevel {
            guard let days = daysSinceTrained else { return .stale }
            switch days {
            case 0...1: return .restingToday
            case 2...4: return .recovering
            case 5...9: return .neglected
            default:    return .stale
            }
        }

        var gapDescription: String {
            guard let days = daysSinceTrained else { return "Never trained" }
            if days == 0 { return "Trained today" }
            if days == 1 { return "Trained yesterday" }
            return "\(days) days ago"
        }
    }

    /// Muscle groups worth tracking recovery for — excludes catch-all categories.
    static let trackedGroups: [MuscleGroup] = [.chest, .back, .legs, .shoulders, .biceps, .triceps, .core]

    /// Builds a status per tracked muscle group from gym workout history, most-neglected first.
    static func statuses(from workouts: [WorkoutSession]) -> [Status] {
        var lastTrainedDate: [MuscleGroup: Date] = [:]
        for workout in workouts where workout.type == .gym {
            for exercise in workout.gymExercises {
                let group = exercise.muscleGroup
                if let existing = lastTrainedDate[group] {
                    lastTrainedDate[group] = max(existing, workout.date)
                } else {
                    lastTrainedDate[group] = workout.date
                }
            }
        }

        return trackedGroups
            .map { Status(muscleGroup: $0, lastTrainedDate: lastTrainedDate[$0]) }
            .sorted { ($0.daysSinceTrained ?? .max) > ($1.daysSinceTrained ?? .max) }
    }

    /// The most-neglected muscle group worth suggesting today, or nil if everything's recently covered.
    static func suggestion(from statuses: [Status]) -> Status? {
        statuses.first { $0.recoveryLevel == .neglected || $0.recoveryLevel == .stale }
    }

    // MARK: - Heatmap (sets per muscle group)

    enum TimeRange: String, CaseIterable {
        case week    = "This Week"
        case month   = "Last 30 Days"
        case allTime = "Since Start"

        var startDate: Date? {
            switch self {
            case .week:    return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .month:   return Calendar.current.date(byAdding: .day, value: -30, to: Date())
            case .allTime: return nil
            }
        }
    }

    static let maxHeatSets = 10
    static func coolColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.17, green: 0.19, blue: 0.23) : Color(red: 0.86, green: 0.88, blue: 0.91)
    }
    static func hotColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.30, green: 0.55, blue: 1.0) : Color(red: 0.04, green: 0.36, blue: 1.0)
    }

    /// Total sets logged per muscle group within the given range.
    static func setCounts(from workouts: [WorkoutSession], range: TimeRange) -> [MuscleGroup: Int] {
        var counts: [MuscleGroup: Int] = [:]
        let cutoff = range.startDate
        for workout in workouts where workout.type == .gym {
            if let cutoff, workout.date < cutoff { continue }
            for exercise in workout.gymExercises {
                counts[exercise.muscleGroup, default: 0] += exercise.sets
            }
        }
        return counts
    }

    static func heatColor(sets: Int, scheme: ColorScheme) -> Color {
        let t = min(Double(sets) / Double(maxHeatSets), 1.0)
        return .lerp(coolColor(scheme), hotColor(scheme), t)
    }
}
