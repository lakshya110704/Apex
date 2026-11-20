import Foundation
import SwiftData

@Model
final class WorkoutScheduleEntry {
    var dayOfWeek: Int       // 1=Sunday, 2=Monday, …, 7=Saturday (matches Calendar weekday)
    var workoutTypeRaw: String
    var isEnabled: Bool
    /// Minutes since midnight, when a time was given ("tennis at 11:30").
    var startMinutes: Int?
    /// First day this applies, for a schedule change that starts later in the week.
    var startsOn: Date?
    /// Set when the coach added or changed this from chat, so it shows in Coach Memory and can be undone there.
    var addedByCoach: Bool = false

    var workoutType: WorkoutType {
        get { WorkoutType(rawValue: workoutTypeRaw) ?? .other }
        set { workoutTypeRaw = newValue.rawValue }
    }

    init(dayOfWeek: Int, workoutType: WorkoutType, startMinutes: Int? = nil, startsOn: Date? = nil, addedByCoach: Bool = false) {
        self.dayOfWeek = dayOfWeek
        self.workoutTypeRaw = workoutType.rawValue
        self.isEnabled = true
        self.startMinutes = startMinutes
        self.startsOn = startsOn
        self.addedByCoach = addedByCoach
    }

    /// Planned on `date`: enabled, and its start date (if any) has come.
    func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        guard let startsOn else { return true }
        return calendar.startOfDay(for: startsOn) <= calendar.startOfDay(for: date)
    }

    var planItem: PlanUpdateEngine.ScheduleItem { .init(type: workoutType, startMinutes: startMinutes) }

    /// "at 11:30 from Wed 18 Nov", or empty.
    var timingLabel: String {
        var parts: [String] = []
        if let startMinutes { parts.append("at \(PlanUpdateEngine.clock(startMinutes))") }
        if let startsOn { parts.append("from \(CoachMemoryEngine.shortDate(startsOn))") }
        return parts.joined(separator: " ")
    }
}

extension WorkoutScheduleEntry {
    /// Adds the session on each day of `change`, or turns it on and sets its time and start date if it is already there.
    /// Used for changes the coach makes from chat and for weekly review suggestions you accept. Never removes anything.
    static func apply(_ change: PlanUpdateEngine.ScheduleChange, to entries: [WorkoutScheduleEntry], in context: ModelContext) {
        for day in change.days {
            if let existing = entries.first(where: { $0.dayOfWeek == day && $0.workoutType == change.type }) {
                existing.isEnabled = true
                existing.startMinutes = change.startMinutes ?? existing.startMinutes
                existing.startsOn = change.startsOn
                existing.addedByCoach = true
            } else {
                context.insert(WorkoutScheduleEntry(dayOfWeek: day, workoutType: change.type,
                                                    startMinutes: change.startMinutes, startsOn: change.startsOn,
                                                    addedByCoach: true))
            }
        }
    }
}
