import Foundation

/// Pure logic behind keeping today's plan in step with what you tell Apex.
///
/// The plan itself is never edited by hand. It is built from health data plus your info: goals and notes
/// (Coach Memory) and today's part of the weekly schedule. The plan records the info it was built from;
/// when that changes, Today rebuilds the plan and says what it adjusted for.
enum PlanUpdateEngine {

    // MARK: Inputs

    /// One scheduled session as the plan sees it.
    struct ScheduleItem: Equatable {
        let type: WorkoutType
        var startMinutes: Int? = nil
    }

    /// One line per piece of info that applies on `date`, in a stable order so the same info always gives the same lines.
    static func inputLines(memories: [CoachMemoryEngine.Item], schedule: [ScheduleItem],
                           on date: Date = Date(), calendar: Calendar = .current) -> [String] {
        let active = CoachMemoryEngine.selectForPrompt(memories.filter { $0.isActive(on: date, calendar: calendar) })
        var lines = active.map { item -> String in
            let scope = item.isSingleDay(calendar: calendar) ? " (today only)" : ""
            return "\(item.kind.label)\(scope): \(item.text)"
        }
        let sessions = schedule.sorted {
            ($0.startMinutes ?? Int.max, $0.type.rawValue) < ($1.startMinutes ?? Int.max, $1.type.rawValue)
        }
        lines += sessions.map { "Scheduled: \(sessionLabel($0))" }
        return lines
    }

    /// The key a plan stores to remember what it was built from.
    static func key(_ lines: [String]) -> String { lines.joined(separator: "\n") }

    /// True when today's plan exists but was built from different info, and an automatic rebuild should run now.
    /// `lastFailedKey` stops a failing provider from being called again and again for the same info.
    static func needsRebuild(planKey: String?, currentKey: String, aiReady: Bool,
                             isGenerating: Bool, lastFailedKey: String?) -> Bool {
        guard let planKey, aiReady, !isGenerating else { return false }
        return planKey != currentKey && lastFailedKey != currentKey
    }

    /// The short "Adjusted for" text shown on the plan after a rebuild: what is new, or else what was removed.
    static func adjustmentSummary(oldKey: String, newKey: String) -> String {
        let old = Set(oldKey.split(separator: "\n").map(String.init))
        let new = newKey.split(separator: "\n").map(String.init)
        let added = new.filter { !old.contains($0) }.map(label)
        if !added.isEmpty { return added.joined(separator: "; ") }
        let newSet = Set(new)
        let removed = oldKey.split(separator: "\n").map(String.init).filter { !newSet.contains($0) }.map(label)
        if !removed.isEmpty { return "removed " + removed.joined(separator: "; ") }
        return ""
    }

    /// "Note (today only): Furniture shopping at 13:30" → "Furniture shopping at 13:30".
    static func label(_ line: String) -> String {
        guard let colon = line.range(of: ": ") else { return line }
        return String(line[colon.upperBound...])
    }

    static func sessionLabel(_ item: ScheduleItem) -> String {
        guard let start = item.startMinutes else { return item.type.rawValue }
        return "\(item.type.rawValue) at \(clock(start))"
    }

    // MARK: Prompt

    /// Added to the plan request. Empty when nothing applies.
    static func promptSection(lines: [String], previousPlan: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if !lines.isEmpty {
            parts.append("── ABOUT THE ATHLETE (their own info; always respect it) ──\n" + lines.map { "- \($0)" }.joined(separator: "\n"))
        }
        let previous = previousPlan.trimmingCharacters(in: .whitespacesAndNewlines)
        if !previous.isEmpty {
            let comps = calendar.dateComponents([.hour, .minute], from: now)
            let nowText = clock((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
            parts.append("""
            ── PREVIOUS PLAN FOR TODAY (their info changed since) ──
            \(previous)
            Time now: \(nowText). Keep items before \(nowText) exactly as they were; change only what comes after, to fit the info above.
            """)
        }
        return parts.joined(separator: "\n\n")
    }

    /// Rules added to the plan prompts so the model uses the section above.
    static let planRules = """
    If ABOUT THE ATHLETE lists an appointment or commitment with a time, put it in the plan at that time and plan around it. \
    Put scheduled sessions at their scheduled time. Respect injuries and limits in notes. Work toward their goals.
    """

    // MARK: Schedule changes from chat

    struct ScheduleChange: Equatable {
        let type: WorkoutType
        let days: [Int]          // Calendar weekdays, 1 = Sunday … 7 = Saturday, Monday first
        var startMinutes: Int? = nil
        var startsOn: Date? = nil
    }

    /// Splits a coach reply into the text to show and any `[schedule tennis: mon tue wed thu fri 11:30 from 2026-11-18]` lines.
    static func extractScheduleChanges(from reply: String, calendar: Calendar = .current) -> (text: String, changes: [ScheduleChange]) {
        let pattern = #"\[\s*schedule\s+([a-z]+)\s*:\s*([^\]]+?)\s*\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return (reply, []) }
        let ns = reply as NSString
        var changes: [ScheduleChange] = []
        for match in regex.matches(in: reply, range: NSRange(location: 0, length: ns.length)) {
            let typeName = ns.substring(with: match.range(at: 1)).lowercased()
            guard let type = WorkoutType.allCases.first(where: { $0.rawValue.lowercased() == typeName }) else { continue }
            if let change = parseSchedule(type: type, ns.substring(with: match.range(at: 2)), calendar: calendar) {
                changes.append(change)
            }
        }
        let stripped = regex.stringByReplacingMatches(in: reply, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return (CoachMemoryEngine.tidy(stripped), changes)
    }

    /// "mon-fri 11:30 from 2026-11-18" → weekdays at 11:30 starting that date. Nil when no day is named.
    static func parseSchedule(type: WorkoutType, _ body: String, calendar: Calendar = .current) -> ScheduleChange? {
        let tokens = body.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "–", with: "-")
            .split(separator: " ").map(String.init)
        var days: [Int] = []
        var start: Int?
        var startsOn: Date?
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "from", index + 1 < tokens.count {
                startsOn = CoachMemoryEngine.parseDay(tokens[index + 1], calendar: calendar)
                index += 2
                continue
            }
            if let minutes = PlanTiming.minutes(token) {
                start = minutes
            } else if let group = dayGroups[token] {
                days += group
            } else if token.contains("-") {
                let ends = token.split(separator: "-").map(String.init)
                if ends.count == 2, let a = weekday(ends[0]), let b = weekday(ends[1]) {
                    days += mondayFirst.split(from: a, to: b)
                }
            } else if let day = weekday(token) {
                days.append(day)
            }
            index += 1
        }
        let unique = mondayFirst.filter { days.contains($0) }
        guard !unique.isEmpty else { return nil }
        return ScheduleChange(type: type, days: unique, startMinutes: start, startsOn: startsOn)
    }

    /// "Tennis Mon–Fri at 11:30 from Wed 18 Nov"
    static func describe(type: WorkoutType, days: [Int], startMinutes: Int?, startsOn: Date?) -> String {
        var text = "\(type.rawValue) \(daysLabel(days))"
        if let startMinutes { text += " at \(clock(startMinutes))" }
        if let startsOn { text += " from \(CoachMemoryEngine.shortDate(startsOn))" }
        return text
    }

    static func describe(_ change: ScheduleChange) -> String {
        describe(type: change.type, days: change.days, startMinutes: change.startMinutes, startsOn: change.startsOn)
    }

    static func daysLabel(_ days: [Int]) -> String {
        let ordered = mondayFirst.filter { days.contains($0) }
        switch ordered {
        case mondayFirst: return "every day"
        case [2, 3, 4, 5, 6]: return "Mon–Fri"
        case [7, 1]: return "weekends"
        default: return ordered.map { shortNames[$0] ?? "?" }.joined(separator: ", ")
        }
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: Day names

    static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]
    private static let shortNames = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
    private static let dayGroups: [String: [Int]] = [
        "weekdays": [2, 3, 4, 5, 6], "weekday": [2, 3, 4, 5, 6],
        "weekends": [7, 1], "weekend": [7, 1],
        "daily": [2, 3, 4, 5, 6, 7, 1], "everyday": [2, 3, 4, 5, 6, 7, 1],
    ]

    static func weekday(_ token: String) -> Int? {
        let names: [(String, Int)] = [("sun", 1), ("mon", 2), ("tue", 3), ("wed", 4), ("thu", 5), ("fri", 6), ("sat", 7)]
        return names.first(where: { token.hasPrefix($0.0) })?.1
    }
}

private extension Array where Element == Int {
    /// Days from `a` to `b` in Monday-first order, wrapping past Sunday ("fri-mon").
    func split(from a: Int, to b: Int) -> [Int] {
        guard let i = firstIndex(of: a), let j = firstIndex(of: b) else { return [] }
        if i <= j { return Array(self[i...j]) }
        return Array(self[i...] + self[...j])
    }
}
