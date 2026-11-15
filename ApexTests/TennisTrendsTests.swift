import XCTest
@testable import Apex

final class TennisTrendsTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }()

    /// Wednesday 2026-11-11, noon UTC.
    private var now: Date { date(2026, 11, 11) }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now)! }

    private func details(sets: (Int, Int) = (0, 0), games: (Int, Int) = (0, 0),
                         opponent: String = "", drills: [String] = []) -> TennisDetails {
        TennisDetails(court: "", opponent: opponent, setsWon: sets.0, setsLost: sets.1,
                      gamesWon: games.0, gamesLost: games.1, drillsPracticed: drills)
    }

    func testMatchResultUsesSetsThenGames() {
        XCTAssertEqual(TennisTrends.MatchResult(details(sets: (2, 1))), .won)
        XCTAssertEqual(TennisTrends.MatchResult(details(sets: (0, 2), games: (9, 3))), .lost)
        XCTAssertEqual(TennisTrends.MatchResult(details(games: (6, 4))), .won)
        XCTAssertEqual(TennisTrends.MatchResult(details(sets: (1, 1))), .drawn)
        XCTAssertNil(TennisTrends.MatchResult(details(drills: ["Lobs"])), "drills-only is not a match")
        XCTAssertNil(TennisTrends.MatchResult(nil))
    }

    func testRecordAndWinRate() {
        let entries = [
            TennisTrends.Entry(date: now, minutes: 60, details: details(sets: (2, 0))),
            TennisTrends.Entry(date: now, minutes: 60, details: details(sets: (0, 2))),
            TennisTrends.Entry(date: now, minutes: 60, details: details(sets: (2, 1))),
            TennisTrends.Entry(date: now, minutes: 60, details: details(drills: ["Lobs"])),
        ]
        let r = TennisTrends.record(entries)
        XCTAssertEqual(r.played, 3)
        XCTAssertEqual(r.text, "2–1")
        XCTAssertEqual(r.winRate!, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertNil(TennisTrends.record([]).winRate)
    }

    func testWeeksBucketsVolumeAndHeartRate() {
        let entries = [
            TennisTrends.Entry(date: date(2026, 11, 9), minutes: 60, averageHeartRate: 140),  // Mon this week
            TennisTrends.Entry(date: date(2026, 11, 11), minutes: 90, averageHeartRate: 0),   // no HR
            TennisTrends.Entry(date: date(2026, 11, 8), minutes: 45, averageHeartRate: 150),  // Sun last week
            TennisTrends.Entry(date: date(2026, 10, 1), minutes: 30),                         // too old
        ]
        let weeks = TennisTrends.weeks(entries, count: 4, now: now, calendar: cal)
        XCTAssertEqual(weeks.count, 4)
        XCTAssertEqual(weeks.last?.start, date(2026, 11, 9, hour: 0))
        XCTAssertEqual(weeks.last?.sessions, 2)
        XCTAssertEqual(weeks.last?.minutes, 150)
        XCTAssertEqual(weeks.last?.averageHeartRate, 140, "sessions without HR are left out of the mean")
        XCTAssertEqual(weeks[2].minutes, 45)
        XCTAssertEqual(weeks[0].sessions, 0)
        XCTAssertNil(weeks[0].averageHeartRate)
    }

    func testWeekStreak() {
        // Played the last 3 weeks but not yet this week: streak still 3.
        let entries = [date(2026, 11, 3), date(2026, 10, 27), date(2026, 10, 20), date(2026, 10, 6)]
            .map { TennisTrends.Entry(date: $0, minutes: 60) }
        XCTAssertEqual(TennisTrends.weekStreak(entries, now: now, calendar: cal), 3)
        // Playing this week extends it.
        let more = entries + [TennisTrends.Entry(date: now, minutes: 60)]
        XCTAssertEqual(TennisTrends.weekStreak(more, now: now, calendar: cal), 4)
        // A skipped last week breaks it.
        XCTAssertEqual(TennisTrends.weekStreak([TennisTrends.Entry(date: date(2026, 10, 27), minutes: 60)], now: now, calendar: cal), 0)
    }

    func testMonthsWinRate() {
        let entries = [
            TennisTrends.Entry(date: date(2026, 11, 2), minutes: 60, details: details(sets: (2, 0))),
            TennisTrends.Entry(date: date(2026, 10, 15), minutes: 60, details: details(sets: (0, 2))),
            TennisTrends.Entry(date: date(2026, 10, 16), minutes: 60, details: details(sets: (2, 1))),
        ]
        let months = TennisTrends.months(entries, count: 3, now: now, calendar: cal)
        XCTAssertEqual(months.map(\.record.played), [0, 2, 1])
        XCTAssertEqual(months[1].record.winRate!, 0.5, accuracy: 0.0001)
        XCTAssertEqual(months[2].record.winRate, 1)
    }

    func testDrillsCountedOncePerSessionAndStale() {
        let entries = [
            TennisTrends.Entry(date: daysAgo(1), minutes: 60, details: details(drills: ["Serve practice", "Serve practice", "Lobs"])),
            TennisTrends.Entry(date: daysAgo(30), minutes: 60, details: details(drills: ["Serve practice", "Volley practice"])),
            TennisTrends.Entry(date: daysAgo(40), minutes: 60, details: details(drills: ["Drop shots"])),
        ]
        let stats = TennisTrends.drills(entries)
        XCTAssertEqual(stats.first?.name, "Serve practice")
        XCTAssertEqual(stats.first?.count, 2)
        XCTAssertEqual(stats.first?.lastPracticed, daysAgo(1))
        XCTAssertEqual(TennisTrends.staleDrills(stats, days: 21, now: now, calendar: cal).map(\.name),
                       ["Drop shots", "Volley practice"])
    }

    func testOpponentsGroupedWithLatestNote() {
        let entries = [
            TennisTrends.Entry(date: daysAgo(10), minutes: 60, details: details(sets: (2, 0), opponent: "Rahul"), notes: "Weak backhand"),
            TennisTrends.Entry(date: daysAgo(2), minutes: 60, details: details(sets: (1, 2), opponent: " rahul "), notes: ""),
            TennisTrends.Entry(date: daysAgo(5), minutes: 60, details: details(sets: (2, 1), opponent: "Ana")),
            TennisTrends.Entry(date: daysAgo(1), minutes: 60, details: details(drills: ["Lobs"])),
        ]
        let opponents = TennisTrends.opponents(entries)
        XCTAssertEqual(opponents.count, 2)
        XCTAssertEqual(opponents[0].name, "rahul")
        XCTAssertEqual(opponents[0].record.text, "1–1")
        XCTAssertEqual(opponents[0].latestNote, "Weak backhand", "falls back to the newest session that has notes")
        XCTAssertEqual(opponents[1].name, "Ana")
        XCTAssertNil(opponents[1].latestNote)
    }
}
