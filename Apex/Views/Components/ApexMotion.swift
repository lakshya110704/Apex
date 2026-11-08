import SwiftUI

/// Immediate, interruptible press feedback: the surface answers the finger at once and
/// springs back from wherever it is, even if released mid-press.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Flat dashboard tile: small label, one big thing.
struct ApexTile<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(ApexColor.accent)
                Text(title).apexLabel()
            }
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(16)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Which of the last N days had any logged activity.
enum ActiveDays {
    /// Oldest first, ending today. A day is active if any date falls on it.
    static func lastDays(_ count: Int, dates: [Date], today: Date = Date()) -> [(day: Date, active: Bool)] {
        let cal = Calendar.current
        let logged = Set(dates.map { cal.startOfDay(for: $0) })
        let start = cal.startOfDay(for: today)
        return (0..<max(count, 0)).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: start).map { ($0, logged.contains($0)) }
        }
    }
}

/// Share of calories from each macro (protein 4, carbs 4, fat 9 kcal per gram).
enum MacroSplit {
    static func shares(protein: Double, carbs: Double, fat: Double) -> (protein: Double, carbs: Double, fat: Double)? {
        let p = max(protein, 0) * 4, c = max(carbs, 0) * 4, f = max(fat, 0) * 9
        let total = p + c + f
        guard total > 0 else { return nil }
        return (p / total, c / total, f / total)
    }
}

/// How much of the week's plan has been done.
enum WeekPlan {
    /// A planned session counts as done when a workout of that type was logged that day.
    static func progress(planned: [(day: Int, type: WorkoutType)], doneByDay: [Int: Set<WorkoutType>]) -> (done: Int, total: Int) {
        (planned.filter { doneByDay[$0.day]?.contains($0.type) == true }.count, planned.count)
    }
}

/// Picks which block of the day plan comes next.
enum PlanTiming {
    /// Minutes since midnight for "HH:MM", or nil if it is not a time.
    static func minutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// Index of the first block at or after `now` (minutes since midnight). If the day is over, the last block with a valid time.
    static func nextIndex(times: [String], now: Int) -> Int? {
        let valid = times.enumerated().compactMap { index, time in minutes(time).map { (index, $0) } }
        guard !valid.isEmpty else { return nil }
        return valid.first(where: { $0.1 >= now })?.0 ?? valid.last?.0
    }
}
