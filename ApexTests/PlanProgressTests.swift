import XCTest
import SwiftData
@testable import Apex

final class PlanProgressTests: XCTestCase {

    private let keys = ["07:00 wake up", "12:00 lunch", "17:00 tennis"]

    func testKeyIgnoresCaseAndPunctuation() {
        XCTAssertEqual(PlanProgress.key(time: "17:00", activity: "Tennis, 90 min!"), PlanProgress.key(time: "17:00", activity: "tennis 90 min"))
        XCTAssertNotEqual(PlanProgress.key(time: "17:00", activity: "Tennis"), PlanProgress.key(time: "18:00", activity: "Tennis"))
    }

    func testXPPerItemPlusBonusForFinishing() {
        XCTAssertEqual(PlanProgress.xp(done: 0, total: 3), 0)
        XCTAssertEqual(PlanProgress.xp(done: 2, total: 3), 2 * XPValues.planItem)
        XCTAssertEqual(PlanProgress.xp(done: 3, total: 3), 3 * XPValues.planItem + XPValues.planComplete)
        XCTAssertEqual(PlanProgress.xp(done: 0, total: 0), 0, "an empty plan is not a finished one")
    }

    func testToggleOnAndOffEarnsNothingNet() {
        let on = PlanProgress.toggle(keys[1], done: [], keys: keys, planXP: 0)
        XCTAssertEqual(on.done, [keys[1]])
        XCTAssertEqual(on.xpChange, XPValues.planItem)
        XCTAssertFalse(on.completedNow)

        let off = PlanProgress.toggle(keys[1], done: on.done, keys: keys, planXP: on.planXP)
        XCTAssertEqual(off.done, [])
        XCTAssertEqual(off.planXP, 0)
        XCTAssertEqual(on.xpChange + off.xpChange, 0)
    }

    func testFinishingTheLastItemAddsBonusOnce() {
        let two = PlanProgress.toggle(keys[2], done: [keys[0]], keys: keys, planXP: 10)
        let all = PlanProgress.toggle(keys[1], done: two.done, keys: keys, planXP: two.planXP)
        XCTAssertEqual(all.done, keys, "kept in plan order")
        XCTAssertTrue(all.completedNow)
        XCTAssertEqual(all.xpChange, XPValues.planItem + XPValues.planComplete)

        let undo = PlanProgress.toggle(keys[0], done: all.done, keys: keys, planXP: all.planXP)
        XCTAssertFalse(undo.completedNow)
        XCTAssertEqual(undo.xpChange, -(XPValues.planItem + XPValues.planComplete), "unchecking gives the bonus back too")
    }

    func testUnknownKeyChangesNothing() {
        let result = PlanProgress.toggle("09:00 gone", done: [keys[0]], keys: keys, planXP: 10)
        XCTAssertEqual(result.done, [keys[0]])
        XCTAssertEqual(result.xpChange, 0)
    }

    func testRebuildKeepsMatchingItemsAndSettlesXP() {
        // Two items done (20 XP); the rebuild keeps 07:00, drops 12:00 lunch, adds 13:30 shopping.
        let newKeys = ["07:00 wake up", "13:30 furniture shopping", "17:00 tennis"]
        let carried = PlanProgress.carryOver(done: [keys[0], keys[1]], previousXP: 20, newKeys: newKeys)
        XCTAssertEqual(carried.done, ["07:00 wake up"])
        XCTAssertEqual(carried.planXP, 10)
        XCTAssertEqual(carried.xpChange, -10)

        let same = PlanProgress.carryOver(done: keys, previousXP: 80, newKeys: keys)
        XCTAssertEqual(same.xpChange, 0, "refreshing a finished plan that comes back the same costs nothing")
    }

    func testNextSkipsDoneItems() {
        let times = ["07:00", "12:00", "17:00"]
        XCTAssertEqual(PlanProgress.nextIndex(times: times, doneFlags: [false, false, false], now: 11 * 60), 1)
        XCTAssertEqual(PlanProgress.nextIndex(times: times, doneFlags: [false, true, false], now: 11 * 60), 2)
        XCTAssertNil(PlanProgress.nextIndex(times: times, doneFlags: [false, true, true], now: 11 * 60), "never jumps back to an earlier open item")
        XCTAssertEqual(PlanProgress.nextIndex(times: times, doneFlags: [false, false, false], now: 23 * 60), 2, "late at night: the last item")
        XCTAssertNil(PlanProgress.nextIndex(times: times, doneFlags: [false, false, true], now: 23 * 60))
        XCTAssertNil(PlanProgress.nextIndex(times: times, doneFlags: [true, true, true], now: 11 * 60))
    }

    func testPlanStreak() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 21))!
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let lastWeek = cal.date(byAdding: .day, value: -7, to: now)!
        XCTAssertEqual(PlanProgress.streak(current: 0, lastCompleted: nil, now: now, calendar: cal), 1)
        XCTAssertEqual(PlanProgress.streak(current: 4, lastCompleted: yesterday, now: now, calendar: cal), 5)
        XCTAssertEqual(PlanProgress.streak(current: 5, lastCompleted: now, now: now, calendar: cal), 5)
        XCTAssertEqual(PlanProgress.streak(current: 9, lastCompleted: lastWeek, now: now, calendar: cal), 1)
        XCTAssertEqual(PlanProgress.liveStreak(current: 4, lastCompleted: yesterday, now: now, calendar: cal), 4)
        XCTAssertEqual(PlanProgress.liveStreak(current: 4, lastCompleted: lastWeek, now: now, calendar: cal), 0)
    }

    @MainActor
    func testTogglingThroughGamificationUpdatesProfileAndPlan() throws {
        let container = try ModelContainer(for: UserProfile.self, DailyPlan.self, Achievement.self, WorkoutSession.self,
                                           GymExercise.self, MealEntry.self, MorningCheckIn.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let profile = UserProfile()
        let plan = DailyPlan(planText: "")
        context.insert(profile)
        context.insert(plan)
        let service = GamificationService()

        for key in keys { service.togglePlanItem(key, keys: keys, plan: plan, profile: profile, context: context) }
        XCTAssertTrue(plan.isCompleted)
        XCTAssertEqual(plan.doneKeys, keys)
        XCTAssertEqual(profile.planStreak, 1)
        XCTAssertNotNil(profile.lastPlanCompletedDate)
        let earned = 3 * XPValues.planItem + XPValues.planComplete
        XCTAssertEqual(plan.xpEarned, earned)
        XCTAssertGreaterThanOrEqual(profile.xpPoints, earned)

        let before = profile.xpPoints
        service.togglePlanItem(keys[0], keys: keys, plan: plan, profile: profile, context: context)
        XCTAssertFalse(plan.isCompleted)
        XCTAssertEqual(profile.xpPoints, before - XPValues.planItem - XPValues.planComplete)
        service.togglePlanItem(keys[0], keys: keys, plan: plan, profile: profile, context: context)
        XCTAssertEqual(profile.planStreak, 1, "finishing again the same day does not grow the streak")
        try context.save()
    }
}
