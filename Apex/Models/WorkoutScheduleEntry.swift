import Foundation
import SwiftData

@Model
final class WorkoutScheduleEntry {
    var dayOfWeek: Int       // 1=Sunday, 2=Monday, …, 7=Saturday (matches Calendar weekday)
    var workoutTypeRaw: String
    var isEnabled: Bool

    var workoutType: WorkoutType {
        get { WorkoutType(rawValue: workoutTypeRaw) ?? .other }
        set { workoutTypeRaw = newValue.rawValue }
    }

    init(dayOfWeek: Int, workoutType: WorkoutType) {
        self.dayOfWeek = dayOfWeek
        self.workoutTypeRaw = workoutType.rawValue
        self.isEnabled = true
    }
}
