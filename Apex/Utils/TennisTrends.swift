import Foundation

/// Pure logic behind the Tennis Trends screen. Works on plain values so it can be tested
/// without SwiftData.
enum TennisTrends {

    /// One tennis session, reduced to what the trends need.
    struct Entry {
        var date: Date
        var minutes: Int
        var averageHeartRate: Int
        var details: TennisDetails?
        var notes: String = ""

        init(date: Date, minutes: Int, averageHeartRate: Int = 0, details: TennisDetails? = nil, notes: String = "") {
            self.date = date
            self.minutes = minutes
            self.averageHeartRate = averageHeartRate
            self.details = details
            self.notes = notes
        }

        init(_ session: WorkoutSession) {
            self.init(date: session.date,
                      minutes: session.durationMinutes,
                      averageHeartRate: session.averageHeartRate,
                      details: session.tennisDetails,
                      notes: session.notes)
        }

        var result: MatchResult? { MatchResult(details) }
    }

    /// A session counts as a match when a score was logged. Sets decide it; games only when no sets were logged.
    enum MatchResult: Equatable {
        case won, lost, drawn

        init?(_ details: TennisDetails?) {
            guard let d = details else { return nil }
            var us = d.setsWon, them = d.setsLost
            if us + them == 0 {
                us = d.gamesWon
                them = d.gamesLost
            }
            guard us + them > 0 else { return nil }
            self = us > them ? .won : (us < them ? .lost : .drawn)
        }
    }

    struct Record: Equatable {
        var won = 0
        var lost = 0
        var drawn = 0
        var played: Int { won + lost + drawn }
        /// Wins over matches played, nil with no matches.
        var winRate: Double? { played > 0 ? Double(won) / Double(played) : nil }
        var text: String { drawn > 0 ? "\(won)–\(lost)–\(drawn)" : "\(won)–\(lost)" }

        mutating func add(_ result: MatchResult?) {
            switch result {
            case .won: won += 1
            case .lost: lost += 1
            case .drawn: drawn += 1
            case nil: break
            }
        }
    }

    static func record(_ entries: [Entry]) -> Record {
        var r = Record()
        entries.forEach { r.add($0.result) }
        return r
    }

    // MARK: Weeks

    struct Week: Equatable {
        var start: Date
        var sessions: Int
        var minutes: Int
        /// Mean of the sessions that have a heart rate, nil if none do.
        var averageHeartRate: Int?
        var record: Record
    }

    /// The last `count` calendar weeks, oldest first, ending with the week containing `now`. Empty weeks included.
    static func weeks(_ entries: [Entry], count: Int, now: Date = Date(), calendar: Calendar = .current) -> [Week] {
        guard count > 0, let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<count).reversed().compactMap { back -> Week? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: current),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let inWeek = entries.filter { $0.date >= start && $0.date < end }
            let rates = inWeek.map(\.averageHeartRate).filter { $0 > 0 }
            return Week(
                start: start,
                sessions: inWeek.count,
                minutes: inWeek.reduce(0) { $0 + max($1.minutes, 0) },
                averageHeartRate: rates.isEmpty ? nil : Int((Double(rates.reduce(0, +)) / Double(rates.count)).rounded()),
                record: record(inWeek)
            )
        }
    }

    /// Consecutive weeks with at least one session, counting back from this week.
    /// This week not played yet does not break the streak; it is simply not counted.
    static func weekStreak(_ entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        let played = Set(entries.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start })
        var start = played.contains(current) ? current : calendar.date(byAdding: .weekOfYear, value: -1, to: current)
        var streak = 0
        while let s = start, played.contains(s) {
            streak += 1
            start = calendar.date(byAdding: .weekOfYear, value: -1, to: s)
        }
        return streak
    }

    // MARK: Months

    struct Month: Equatable {
        var start: Date
        var record: Record
    }

    /// The last `count` calendar months, oldest first, ending with the current month.
    static func months(_ entries: [Entry], count: Int, now: Date = Date(), calendar: Calendar = .current) -> [Month] {
        guard count > 0, let current = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        return (0..<count).reversed().compactMap { back -> Month? in
            guard let start = calendar.date(byAdding: .month, value: -back, to: current),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            return Month(start: start, record: record(entries.filter { $0.date >= start && $0.date < end }))
        }
    }

    // MARK: Drills

    struct DrillStat: Equatable {
        var name: String
        var count: Int
        var lastPracticed: Date
    }

    /// Drills you have practiced, most often first (ties: most recent first).
    static func drills(_ entries: [Entry]) -> [DrillStat] {
        var byName: [String: DrillStat] = [:]
        for entry in entries {
            for drill in Set(entry.details?.drillsPracticed ?? []) {
                if var stat = byName[drill] {
                    stat.count += 1
                    stat.lastPracticed = max(stat.lastPracticed, entry.date)
                    byName[drill] = stat
                } else {
                    byName[drill] = DrillStat(name: drill, count: 1, lastPracticed: entry.date)
                }
            }
        }
        return byName.values.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.lastPracticed > $1.lastPracticed
        }
    }

    /// Drills you practiced before but not in the last `days` days, longest gap first.
    static func staleDrills(_ stats: [DrillStat], days: Int = 21, now: Date = Date(), calendar: Calendar = .current) -> [DrillStat] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else { return [] }
        return stats.filter { $0.lastPracticed < cutoff }.sorted { $0.lastPracticed < $1.lastPracticed }
    }

    // MARK: Opponents

    struct Opponent: Equatable {
        var name: String
        var record: Record
        var lastPlayed: Date
        /// Notes from the most recent session against them that has any.
        var latestNote: String?
    }

    /// Everyone you logged as an opponent, matched ignoring case and spaces, most recent first.
    static func opponents(_ entries: [Entry]) -> [Opponent] {
        var groups: [String: [Entry]] = [:]
        for entry in entries {
            let name = entry.details?.opponent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            let key = name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            groups[key, default: []].append(entry)
        }
        return groups.values.compactMap { group -> Opponent? in
            let sorted = group.sorted { $0.date > $1.date }
            guard let latest = sorted.first else { return nil }
            let note = sorted.lazy
                .map { $0.notes.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })
            return Opponent(
                name: latest.details?.opponent.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                record: record(group),
                lastPlayed: latest.date,
                latestNote: note
            )
        }
        .sorted { $0.lastPlayed > $1.lastPlayed }
    }
}
