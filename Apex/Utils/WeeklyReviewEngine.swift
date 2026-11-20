import Foundation

/// Pure logic behind the weekly coach review: which week it covers, the numbers it is built from,
/// the request sent to the model, and the schedule changes it suggests.
///
/// The numbers are worked out on device, so the review screen shows them even without an AI key.
/// The model only writes the words on top and may suggest up to two changes to the weekly schedule,
/// which you accept one by one. Nothing is changed until you tap Accept.
enum WeeklyReviewEngine {

    // MARK: Which week

    /// Weeks run Monday to Sunday, whatever the device's first weekday is.
    static func mondayCalendar(_ base: Calendar = .current) -> Calendar {
        var cal = base
        cal.firstWeekday = 2
        return cal
    }

    /// The Monday the review covers: on Sunday the week ending today, any other day the last full week.
    static func reviewWeekStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let cal = mondayCalendar(calendar)
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        if cal.component(.weekday, from: now) == 1 { return thisWeek }
        return cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek) ?? thisWeek
    }

    /// True from 18:00 on Sunday through Monday: when Today offers the review, if it has not been written yet.
    static func isReviewTime(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: now)
        return (weekday == 1 && calendar.component(.hour, from: now) >= notificationHour) || weekday == 2
    }

    /// Sunday evening reminder hour.
    static let notificationHour = 18

    // MARK: Inputs

    struct Session {
        var date: Date
        var type: WorkoutType
        var minutes: Int
        var tennis: TennisDetails? = nil

        init(date: Date, type: WorkoutType, minutes: Int, tennis: TennisDetails? = nil) {
            self.date = date
            self.type = type
            self.minutes = minutes
            self.tennis = tennis
        }

        init(_ session: WorkoutSession) {
            self.init(date: session.date, type: session.type, minutes: session.durationMinutes, tennis: session.tennisDetails)
        }
    }

    /// One enabled session in the weekly schedule.
    struct Slot: Equatable {
        var dayOfWeek: Int          // 1 = Sunday … 7 = Saturday
        var type: WorkoutType
        var startsOn: Date? = nil

        init(dayOfWeek: Int, type: WorkoutType, startsOn: Date? = nil) {
            self.dayOfWeek = dayOfWeek
            self.type = type
            self.startsOn = startsOn
        }

        init(_ entry: WorkoutScheduleEntry) {
            self.init(dayOfWeek: entry.dayOfWeek, type: entry.workoutType, startsOn: entry.startsOn)
        }

        func applies(on date: Date, calendar: Calendar) -> Bool {
            guard calendar.component(.weekday, from: date) == dayOfWeek else { return false }
            guard let startsOn else { return true }
            return calendar.startOfDay(for: startsOn) <= calendar.startOfDay(for: date)
        }
    }

    struct CheckIn: Equatable {
        var date: Date
        var sleepScore: Int     // 0 = not reported
        var energy: Int         // 1–5

        init(date: Date, sleepScore: Int, energy: Int) {
            self.date = date
            self.sleepScore = sleepScore
            self.energy = energy
        }

        init(_ checkIn: MorningCheckIn) {
            self.init(date: checkIn.date, sleepScore: checkIn.sleepScore, energy: checkIn.energyLevel)
        }
    }

    // MARK: Numbers

    struct TypeTotal: Equatable {
        var type: WorkoutType
        var sessions: Int
        var minutes: Int
    }

    struct Stats: Equatable {
        var weekStart: Date
        /// Scheduled sessions that were due (days already over, plus today's if it was done).
        var planned: Int
        /// Scheduled sessions you did.
        var done: Int
        /// "Gym Tue", in day order.
        var missed: [String]
        /// Sessions logged that were not on the schedule.
        var extra: Int
        var sessions: Int
        var minutes: Int
        var byType: [TypeTotal]
        var previousSessions: Int
        var previousMinutes: Int
        var tennisRecord: TennisTrends.Record
        /// Drills you used to practice but have not in three weeks.
        var staleDrills: [String]
        var checkIns: Int
        var averageSleepScore: Int?
        var averageEnergy: Double?
        var goals: [String]

        /// "4 of 5", or nil when nothing was scheduled.
        var adherenceText: String? { planned > 0 ? "\(done) of \(planned)" : nil }
    }

    static func stats(weekStart: Date, sessions: [Session], schedule: [Slot], checkIns: [CheckIn],
                      goals: [String], now: Date = Date(), calendar: Calendar = .current) -> Stats {
        let cal = mondayCalendar(calendar)
        let start = cal.startOfDay(for: weekStart)
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        let previousStart = cal.date(byAdding: .day, value: -7, to: start) ?? start
        let today = cal.startOfDay(for: now)

        let inWeek = sessions.filter { $0.date >= start && $0.date < end && $0.date <= now }
        let previous = sessions.filter { $0.date >= previousStart && $0.date < start }

        // Planned against done, matching each logged session to at most one slot.
        var unused = inWeek
        var planned = 0, done = 0
        var missed: [String] = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: start), day <= now else { continue }
            for slot in schedule where slot.applies(on: day, calendar: cal) {
                if let i = unused.firstIndex(where: { $0.type == slot.type && cal.isDate($0.date, inSameDayAs: day) }) {
                    unused.remove(at: i)
                    planned += 1
                    done += 1
                } else if cal.startOfDay(for: day) < today {
                    planned += 1
                    missed.append("\(slot.type.rawValue) \(shortWeekday(day, calendar: cal))")
                }
                // Today's session not done yet is neither done nor missed.
            }
        }

        let byType: [TypeTotal] = WorkoutType.allCases.compactMap { type in
            let ofType = inWeek.filter { $0.type == type }
            guard !ofType.isEmpty else { return nil }
            return TypeTotal(type: type, sessions: ofType.count, minutes: ofType.reduce(0) { $0 + max($1.minutes, 0) })
        }

        let tennisInWeek = inWeek.filter { $0.type == .tennis }
        var record = TennisTrends.Record()
        tennisInWeek.forEach { record.add(TennisTrends.MatchResult($0.tennis)) }
        let allTennis = sessions.filter { $0.type == .tennis && $0.date < end }
            .map { TennisTrends.Entry(date: $0.date, minutes: $0.minutes, details: $0.tennis) }
        let reference = min(now, cal.date(byAdding: .second, value: -1, to: end) ?? now)
        let stale = TennisTrends.staleDrills(TennisTrends.drills(allTennis), days: 21, now: reference, calendar: cal)
            .prefix(2).map(\.name)

        let weekCheckIns = checkIns.filter { $0.date >= start && $0.date < end }
        let scores = weekCheckIns.map(\.sleepScore).filter { $0 > 0 }
        let energies = weekCheckIns.map(\.energy).filter { $0 > 0 }

        return Stats(
            weekStart: start,
            planned: planned,
            done: done,
            missed: missed,
            extra: unused.count,
            sessions: inWeek.count,
            minutes: inWeek.reduce(0) { $0 + max($1.minutes, 0) },
            byType: byType,
            previousSessions: previous.count,
            previousMinutes: previous.reduce(0) { $0 + max($1.minutes, 0) },
            tennisRecord: record,
            staleDrills: Array(stale),
            checkIns: weekCheckIns.count,
            averageSleepScore: scores.isEmpty ? nil : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded()),
            averageEnergy: energies.isEmpty ? nil : Double(energies.reduce(0, +)) / Double(energies.count),
            goals: goals
        )
    }

    // MARK: Request

    /// The week's numbers as the model sees them. `health` is the Watch's 7-day averages, only passed
    /// when the review covers the week ending today (they are rolling averages, not per week).
    static func dataBlock(_ s: Stats, health: (sleepHours: Double, hrv: Double)? = nil, calendar: Calendar = .current) -> String {
        let cal = mondayCalendar(calendar)
        let end = cal.date(byAdding: .day, value: 6, to: s.weekStart) ?? s.weekStart
        var lines = ["WEEK: \(CoachMemoryEngine.shortDate(s.weekStart)) to \(CoachMemoryEngine.shortDate(end))"]

        lines.append("\n── TRAINING ──")
        lines.append("Sessions logged: \(s.sessions) (\(s.minutes) min). Week before: \(s.previousSessions) (\(s.previousMinutes) min).")
        if !s.byType.isEmpty {
            lines.append("By type: " + s.byType.map { "\($0.type.rawValue) \($0.sessions)× \($0.minutes) min" }.joined(separator: ", "))
        }
        if s.planned > 0 {
            lines.append("Scheduled sessions done: \(s.done) of \(s.planned).")
            if !s.missed.isEmpty { lines.append("Missed: \(s.missed.joined(separator: ", ")).") }
        } else {
            lines.append("No sessions were scheduled.")
        }
        if s.extra > 0 { lines.append("Unscheduled sessions: \(s.extra).") }

        if s.tennisRecord.played > 0 || !s.staleDrills.isEmpty {
            lines.append("\n── TENNIS ──")
            if s.tennisRecord.played > 0 {
                let rate = Int(((s.tennisRecord.winRate ?? 0) * 100).rounded())
                lines.append("Matches: \(s.tennisRecord.text) (won \(rate)%).")
            }
            if !s.staleDrills.isEmpty {
                lines.append("Drills not practiced in 3+ weeks: \(s.staleDrills.joined(separator: ", ")).")
            }
        }

        lines.append("\n── RECOVERY ──")
        if s.checkIns > 0 {
            var parts = ["Morning check-ins: \(s.checkIns) of 7"]
            if let sleep = s.averageSleepScore { parts.append("average sleep score \(sleep)/100") }
            if let energy = s.averageEnergy { parts.append("average energy \(String(format: "%.1f", energy))/5") }
            lines.append(parts.joined(separator: ", ") + ".")
        } else {
            lines.append("No morning check-ins this week.")
        }
        if let health, health.sleepHours > 0 || health.hrv > 0 {
            var parts: [String] = []
            if health.sleepHours > 0 { parts.append("sleep \(String(format: "%.1f", health.sleepHours))h") }
            if health.hrv > 0 { parts.append("HRV \(Int(health.hrv)) ms") }
            lines.append("Watch 7-day averages: " + parts.joined(separator: ", ") + ".")
        }

        lines.append("\n── GOALS ──")
        lines.append(s.goals.isEmpty ? "None saved." : s.goals.map { "- \($0)" }.joined(separator: "\n"))
        return lines.joined(separator: "\n")
    }

    /// When suggested changes start: today if it is Monday, otherwise next Monday.
    /// Never a day already gone, so accepting a change never turns earlier days into missed sessions.
    static func suggestionStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let cal = mondayCalendar(calendar)
        let today = cal.startOfDay(for: now)
        if cal.component(.weekday, from: now) == 2 { return today }
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        return cal.date(byAdding: .day, value: 7, to: thisWeek) ?? today
    }

    /// A suggestion accepted later than planned starts today instead of on a day already gone.
    static func startingNoEarlierThanToday(_ change: PlanUpdateEngine.ScheduleChange, now: Date = Date(),
                                           calendar: Calendar = .current) -> PlanUpdateEngine.ScheduleChange {
        let today = calendar.startOfDay(for: now)
        var adjusted = change
        if let start = change.startsOn, calendar.startOfDay(for: start) < today { adjusted.startsOn = today }
        return adjusted
    }

    static func systemPrompt(name: String, nextWeek: Date) -> String {
        let who = name.isEmpty ? "the athlete" : name
        return """
        You are Apex Coach writing \(who)'s weekly review. Use only the numbers given; never invent any. \
        Under 150 words, plain sentences, no headings, no bullet lists, no filler. \
        Open with the one thing that mattered most this week. Compare with the week before where the numbers allow. \
        Name missed sessions honestly, without scolding. Tie the week to their goals. \
        Finish with one or two specific changes for next week. \
        When a change adds a session to their regular week or sets its time, also put it on its own line at the very end as \
        [schedule tennis|gym|run|other: mon wed HH:MM from \(CoachMemoryEngine.isoDay(nextWeek))] (days required, time only if you are suggesting one). \
        Such a line only adds that session on those days or sets its time; it never removes anything, so describe removals in words only. \
        At most two such lines. The app hides them and offers each one as a change the athlete can accept.
        """
    }

    /// The review text and the schedule changes it suggests, as `[schedule ...]` tags so they can be stored and parsed again.
    static func parse(_ reply: String, calendar: Calendar = .current) -> (text: String, suggestions: [String]) {
        let pattern = #"\[\s*schedule\s+[a-z]+\s*:\s*[^\]]+?\s*\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return (reply, []) }
        let ns = reply as NSString
        let tags = regex.matches(in: reply, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
            .filter { change(from: $0, calendar: calendar) != nil }
        // Any memory lines are not acted on here; just keep them off screen.
        let withoutMemory = CoachMemoryEngine.extract(from: reply).text
        let text = PlanUpdateEngine.extractScheduleChanges(from: withoutMemory, calendar: calendar).text
        return (text, Array(tags.prefix(2)))
    }

    static func change(from tag: String, calendar: Calendar = .current) -> PlanUpdateEngine.ScheduleChange? {
        PlanUpdateEngine.extractScheduleChanges(from: tag, calendar: calendar).changes.first
    }

    // MARK: Coach chat

    /// The last review, added to coach chats for a week so the coach can hold you to what it suggested.
    static func coachSection(weekStart: Date, text: String, accepted: [String], now: Date = Date(), calendar: Calendar = .current) -> String {
        let cal = mondayCalendar(calendar)
        guard let shownUntil = cal.date(byAdding: .day, value: 14, to: weekStart), now < shownUntil, text.isNotEmpty else { return "" }
        var section = "LAST WEEKLY REVIEW (week of \(CoachMemoryEngine.shortDate(weekStart))): \(CoachMemoryEngine.clip(text, 500))"
        let changes = accepted.compactMap { change(from: $0, calendar: calendar) }.map(PlanUpdateEngine.describe)
        if !changes.isEmpty { section += "\nThey accepted: " + changes.joined(separator: "; ") }
        return section
    }

    // MARK: Helpers

    static func shortWeekday(_ date: Date, calendar: Calendar = .current) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][calendar.component(.weekday, from: date) - 1]
    }
}
