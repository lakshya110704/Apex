import Foundation

/// Pure logic behind checking off items of today's plan.
///
/// Checking an item off is not editing the plan: the items stay what Apex built, you only mark what you did.
/// Each done item is worth XP, and finishing every item earns a bonus and counts toward the plan streak.
/// Unchecking gives the XP back, so tapping on and off earns nothing.
enum PlanProgress {

    /// Identifies an item across rebuilds: a rebuild keeps earlier items the same, so their keys match.
    static func key(time: String, activity: String) -> String {
        "\(time) \(CoachMemoryEngine.normalized(activity))"
    }

    /// XP a plan with `done` of `total` items checked off is worth.
    static func xp(done: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        let checked = min(done, total)
        return checked * XPValues.planItem + (checked == total ? XPValues.planComplete : 0)
    }

    struct Toggle: Equatable {
        /// Checked-off keys after the tap, in plan order.
        var done: [String]
        /// XP to add to the profile (negative when unchecking).
        var xpChange: Int
        /// The plan's XP after the tap.
        var planXP: Int
        /// True when this tap finished the last item.
        var completedNow: Bool
    }

    /// Checks `key` off, or back on if it was done. `keys` are all items of the plan, `planXP` what it has earned so far.
    static func toggle(_ key: String, done: [String], keys: [String], planXP: Int) -> Toggle {
        var set = Set(done).intersection(keys)
        let wasComplete = !keys.isEmpty && set.count == Set(keys).count
        if set.contains(key) { set.remove(key) } else if keys.contains(key) { set.insert(key) }
        let ordered = unique(keys).filter(set.contains)
        let total = unique(keys).count
        let newXP = xp(done: ordered.count, total: total)
        return Toggle(done: ordered, xpChange: newXP - planXP, planXP: newXP,
                      completedNow: !wasComplete && total > 0 && ordered.count == total)
    }

    /// After a rebuild: the items still in the new plan stay checked off, and the XP is settled to match.
    static func carryOver(done: [String], previousXP: Int, newKeys: [String]) -> (done: [String], planXP: Int, xpChange: Int) {
        let kept = unique(newKeys).filter(Set(done).contains)
        let xp = xp(done: kept.count, total: unique(newKeys).count)
        return (kept, xp, xp - previousXP)
    }

    /// Index of the item to show as next: the first not done at or after the time-based next item,
    /// otherwise the first not done at all. Nil when everything is done.
    static func nextIndex(times: [String], doneFlags: [Bool], now: Int) -> Int? {
        guard times.count == doneFlags.count else { return nil }
        let open = times.indices.filter { !doneFlags[$0] }
        guard !open.isEmpty else { return nil }
        let start = PlanTiming.nextIndex(times: times, now: now) ?? 0
        return open.first(where: { $0 >= start }) ?? open.first
    }

    /// Plan streak after finishing today's plan: +1 if yesterday's was finished, 1 after a gap, unchanged if already counted today.
    static func streak(current: Int, lastCompleted: Date?, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        guard let lastCompleted else { return 1 }
        let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastCompleted), to: today).day ?? 0
        switch gap {
        case 0:  return max(current, 1)
        case 1:  return current + 1
        default: return 1
        }
    }

    /// The streak to show: it lapses once a full day passes without a finished plan.
    static func liveStreak(current: Int, lastCompleted: Date?, now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let lastCompleted else { return 0 }
        let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastCompleted), to: calendar.startOfDay(for: now)).day ?? 0
        return gap <= 1 ? current : 0
    }

    private static func unique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }
}
