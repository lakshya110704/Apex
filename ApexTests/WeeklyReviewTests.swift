import XCTest
import SwiftData
@testable import Apex

final class WeeklyReviewTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1 // Sunday first, to check the review still uses Monday weeks
        return c
    }()

    private func date(_ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: hour))!
    }

    /// Monday 16 Nov 2026.
    private var weekStart: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 16))! }

    private func tennis(_ d: Date, minutes: Int = 90, sets: (Int, Int) = (0, 0), drills: [String] = []) -> WeeklyReviewEngine.Session {
        .init(date: d, type: .tennis, minutes: minutes,
              tennis: TennisDetails(court: "", opponent: "", setsWon: sets.0, setsLost: sets.1,
                                    gamesWon: 0, gamesLost: 0, drillsPracticed: drills))
    }

    // MARK: Which week

    func testReviewWeekIsThisWeekOnSundayElseLastWeek() {
        XCTAssertEqual(WeeklyReviewEngine.reviewWeekStart(now: date(11, 22, hour: 19), calendar: cal), weekStart, "Sunday: the week ending today")
        XCTAssertEqual(WeeklyReviewEngine.reviewWeekStart(now: date(11, 23), calendar: cal), weekStart, "Monday: last week")
        XCTAssertEqual(WeeklyReviewEngine.reviewWeekStart(now: date(11, 25), calendar: cal), weekStart, "Wednesday: last week")
        XCTAssertEqual(WeeklyReviewEngine.reviewWeekStart(now: date(11, 21), calendar: cal),
                       cal.date(from: DateComponents(year: 2026, month: 11, day: 9))!, "Saturday: the week before")
    }

    func testReviewTimeIsSundayEveningAndMonday() {
        XCTAssertFalse(WeeklyReviewEngine.isReviewTime(now: date(11, 22, hour: 17), calendar: cal))
        XCTAssertTrue(WeeklyReviewEngine.isReviewTime(now: date(11, 22, hour: 18), calendar: cal))
        XCTAssertTrue(WeeklyReviewEngine.isReviewTime(now: date(11, 23, hour: 9), calendar: cal))
        XCTAssertFalse(WeeklyReviewEngine.isReviewTime(now: date(11, 24), calendar: cal))
    }

    // MARK: Numbers

    private var schedule: [WeeklyReviewEngine.Slot] {
        [
            .init(dayOfWeek: 3, type: .gym),                                 // Tue
            .init(dayOfWeek: 5, type: .tennis),                              // Thu
            .init(dayOfWeek: 1, type: .tennis),                              // Sun
            .init(dayOfWeek: 4, type: .gym, startsOn: date(11, 20)),         // Wed, but only from Fri 20 Nov
        ]
    }

    private var sessions: [WeeklyReviewEngine.Session] {
        [
            .init(date: date(11, 9), type: .gym, minutes: 45),               // week before
            .init(date: date(11, 17), type: .gym, minutes: 60),              // Tue, scheduled
            tennis(date(11, 20), sets: (2, 1), drills: ["Serves"]),          // Fri, not scheduled
            .init(date: date(11, 21), type: .run, minutes: 30),              // Sat, not scheduled
            tennis(date(10, 20), drills: ["Lobs"]),                          // a month back
        ]
    }

    func testPlannedDoneMissedAndExtra() {
        let s = WeeklyReviewEngine.stats(weekStart: weekStart, sessions: sessions, schedule: schedule,
                                         checkIns: [], goals: [], now: date(11, 22), calendar: cal)
        XCTAssertEqual(s.planned, 2, "Tue gym and Thu tennis; Sunday's not done yet and Wed gym hadn't started")
        XCTAssertEqual(s.done, 1)
        XCTAssertEqual(s.missed, ["Tennis Thu"])
        XCTAssertEqual(s.extra, 2)
        XCTAssertEqual(s.sessions, 3)
        XCTAssertEqual(s.minutes, 180)
        XCTAssertEqual(s.previousSessions, 1)
        XCTAssertEqual(s.previousMinutes, 45)
        XCTAssertEqual(s.byType.map(\.type), [.tennis, .gym, .run])
        XCTAssertEqual(s.adherenceText, "1 of 2")
    }

    func testTodaysSessionCountsOnceDone() {
        let done = sessions + [tennis(date(11, 22, hour: 10), minutes: 60)]
        let s = WeeklyReviewEngine.stats(weekStart: weekStart, sessions: done, schedule: schedule,
                                         checkIns: [], goals: [], now: date(11, 22, hour: 19), calendar: cal)
        XCTAssertEqual(s.planned, 3)
        XCTAssertEqual(s.done, 2)
    }

    func testPastWeekCountsEveryScheduledDay() {
        let s = WeeklyReviewEngine.stats(weekStart: weekStart, sessions: sessions, schedule: schedule,
                                         checkIns: [], goals: [], now: date(11, 25), calendar: cal)
        XCTAssertEqual(s.planned, 3)
        XCTAssertEqual(s.missed, ["Tennis Thu", "Tennis Sun"])
    }

    func testTennisRecoveryAndGoals() {
        let checkIns: [WeeklyReviewEngine.CheckIn] = [
            .init(date: date(11, 16), sleepScore: 70, energy: 3),
            .init(date: date(11, 18), sleepScore: 81, energy: 4),
            .init(date: date(11, 19), sleepScore: 0, energy: 0),            // no Health data that morning
            .init(date: date(11, 10), sleepScore: 20, energy: 1),           // week before, left out
        ]
        let s = WeeklyReviewEngine.stats(weekStart: weekStart, sessions: sessions, schedule: schedule,
                                         checkIns: checkIns, goals: ["Sub-20 5k by March"], now: date(11, 22), calendar: cal)
        XCTAssertEqual(s.tennisRecord, TennisTrends.Record(won: 1, lost: 0, drawn: 0))
        XCTAssertEqual(s.staleDrills, ["Lobs"])
        XCTAssertEqual(s.checkIns, 3)
        XCTAssertEqual(s.averageSleepScore, 76)
        XCTAssertEqual(s.averageEnergy ?? 0, 3.5, accuracy: 0.001)
        XCTAssertEqual(s.goals, ["Sub-20 5k by March"])
    }

    func testDataBlockSaysWhatHappened() {
        let s = WeeklyReviewEngine.stats(weekStart: weekStart, sessions: sessions, schedule: schedule,
                                         checkIns: [], goals: [], now: date(11, 22), calendar: cal)
        let block = WeeklyReviewEngine.dataBlock(s, calendar: cal)
        XCTAssertTrue(block.contains("Sessions logged: 3 (180 min). Week before: 1 (45 min)."), block)
        XCTAssertTrue(block.contains("Scheduled sessions done: 1 of 2."))
        XCTAssertTrue(block.contains("Missed: Tennis Thu."))
        XCTAssertTrue(block.contains("Unscheduled sessions: 2."))
        XCTAssertTrue(block.contains("Matches: 1–0 (won 100%)."))
        XCTAssertTrue(block.contains("No morning check-ins this week."))
        XCTAssertTrue(block.contains("None saved."))
        XCTAssertFalse(block.contains("Watch 7-day"))
        XCTAssertTrue(WeeklyReviewEngine.dataBlock(s, health: (7.2, 48), calendar: cal).contains("Watch 7-day averages: sleep 7.2h, HRV 48 ms."))
    }

    // MARK: Reply

    func testParseKeepsTextAndValidSuggestions() {
        let reply = """
        Strong week: 3 sessions, up from 1.
        Thursday tennis slipped again.

        [schedule gym: wed 18:00 from 2026-11-23]
        [schedule swim: mon]
        [remember goal: play a tournament]
        [schedule tennis: sat]
        [schedule run: sun]
        """
        let (text, suggestions) = WeeklyReviewEngine.parse(reply, calendar: cal)
        XCTAssertEqual(text, "Strong week: 3 sessions, up from 1.\nThursday tennis slipped again.")
        XCTAssertEqual(suggestions, ["[schedule gym: wed 18:00 from 2026-11-23]", "[schedule tennis: sat]"], "unknown types dropped, at most two")
        let change = WeeklyReviewEngine.change(from: suggestions[0], calendar: cal)
        XCTAssertEqual(change?.type, .gym)
        XCTAssertEqual(change?.days, [4])
        XCTAssertEqual(change?.startMinutes, 18 * 60)
        XCTAssertEqual(change?.startsOn, cal.date(from: DateComponents(year: 2026, month: 11, day: 23)))
    }

    func testSuggestionsNeverStartOnADayAlreadyGone() {
        let monday23 = cal.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        let monday30 = cal.date(from: DateComponents(year: 2026, month: 11, day: 30))!
        XCTAssertEqual(WeeklyReviewEngine.suggestionStart(now: date(11, 22, hour: 19), calendar: cal), monday23, "Sunday: tomorrow")
        XCTAssertEqual(WeeklyReviewEngine.suggestionStart(now: date(11, 20), calendar: cal), monday23, "Friday, reviewing last week: next Monday, not this one")
        XCTAssertEqual(WeeklyReviewEngine.suggestionStart(now: date(11, 23), calendar: cal), monday23, "Monday: today")
        XCTAssertEqual(WeeklyReviewEngine.suggestionStart(now: date(11, 25), calendar: cal), monday30)
        XCTAssertTrue(WeeklyReviewEngine.systemPrompt(name: "Lakshya", nextWeek: monday23).contains("from 2026-11-23"))

        // Accepted a week late: starts today instead.
        let late = PlanUpdateEngine.ScheduleChange(type: .gym, days: [4], startsOn: monday23)
        XCTAssertEqual(WeeklyReviewEngine.startingNoEarlierThanToday(late, now: date(11, 26), calendar: cal).startsOn,
                       cal.startOfDay(for: date(11, 26)))
        XCTAssertEqual(WeeklyReviewEngine.startingNoEarlierThanToday(late, now: date(11, 21), calendar: cal).startsOn, monday23)
    }

    func testCoachSectionLastsTwoWeeksFromTheReviewedMonday() {
        let section = WeeklyReviewEngine.coachSection(weekStart: weekStart, text: "Good week.",
                                                      accepted: ["[schedule gym: wed 18:00]"], now: date(11, 24), calendar: cal)
        XCTAssertTrue(section.hasPrefix("LAST WEEKLY REVIEW"))
        XCTAssertTrue(section.contains("Good week."))
        XCTAssertTrue(section.contains("They accepted: Gym Wed at 18:00"))
        XCTAssertEqual(WeeklyReviewEngine.coachSection(weekStart: weekStart, text: "Good week.", accepted: [],
                                                       now: date(11, 30), calendar: cal), "")
    }

    // MARK: Accepting

    @MainActor
    func testAcceptingAddsOrUpdatesScheduleAndIsSaved() throws {
        let container = try ModelContainer(for: WorkoutScheduleEntry.self, WeeklyReview.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let wednesday = WorkoutScheduleEntry(dayOfWeek: 4, workoutType: .gym)
        wednesday.isEnabled = false
        context.insert(wednesday)
        let review = WeeklyReview(weekStart: weekStart, text: "Move gym", suggestions: ["[schedule gym: wed fri 18:00]"])
        context.insert(review)
        try context.save()

        let change = try XCTUnwrap(WeeklyReviewEngine.change(from: review.suggestions[0], calendar: cal))
        WorkoutScheduleEntry.apply(change, to: try context.fetch(FetchDescriptor<WorkoutScheduleEntry>()), in: context)
        review.accepted.append(review.suggestions[0])
        try context.save()

        let entries = try context.fetch(FetchDescriptor<WorkoutScheduleEntry>()).sorted { $0.dayOfWeek < $1.dayOfWeek }
        XCTAssertEqual(entries.map(\.dayOfWeek), [4, 6])
        XCTAssertTrue(entries.allSatisfy { $0.isEnabled && $0.startMinutes == 18 * 60 && $0.addedByCoach })
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeeklyReview>()).first?.accepted, ["[schedule gym: wed fri 18:00]"])
    }
}
