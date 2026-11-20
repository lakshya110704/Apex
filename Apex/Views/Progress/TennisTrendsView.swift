import SwiftUI
import SwiftData
import Charts

/// Tennis over time: volume, intensity, streak, win rate, drills and opponents.
struct TennisTrendsView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) private var workouts: [WorkoutSession]

    private var entries: [TennisTrends.Entry] {
        workouts.filter { $0.type == .tennis }.map { TennisTrends.Entry($0) }
    }

    var body: some View {
        let entries = entries
        ZStack {
            ApexColor.background.ignoresSafeArea()
            ScrollView {
                if entries.isEmpty {
                    EmptyStateView(
                        icon: "figure.tennis",
                        title: "No Tennis Yet",
                        subtitle: "Log a tennis session in Workouts and your trends show up here."
                    )
                    .padding(.top, 40)
                } else {
                    content(entries)
                }
            }
        }
        .navigationTitle("Tennis Trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ entries: [TennisTrends.Entry]) -> some View {
        let weeks = TennisTrends.weeks(entries, count: 12)
        let months = TennisTrends.months(entries, count: 6)
        let drills = TennisTrends.drills(entries)
        let opponents = TennisTrends.opponents(entries)
        return VStack(spacing: 16) {
            summaryGrid(entries: entries, weeks: weeks)
            volumeCard(weeks)
            intensityCard(weeks)
            winRateCard(months, overall: TennisTrends.record(entries))
            drillsCard(drills)
            if !opponents.isEmpty { opponentsCard(opponents) }
            Spacer(minLength: 32)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Summary

    private func summaryGrid(entries: [TennisTrends.Entry], weeks: [TennisTrends.Week]) -> some View {
        let thisWeek = weeks.last
        let streak = TennisTrends.weekStreak(entries)
        let record = TennisTrends.record(entries)
        let recentRates = weeks.suffix(4).compactMap(\.averageHeartRate)
        let recentHR = recentRates.isEmpty ? nil : recentRates.reduce(0, +) / recentRates.count
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile("This week", icon: "calendar",
                 value: hoursText(thisWeek?.minutes ?? 0),
                 caption: sessionsText(thisWeek?.sessions ?? 0))
            tile("Week streak", icon: "flame.fill",
                 value: "\(streak)",
                 caption: streak == 1 ? "week in a row" : "weeks in a row")
            tile("Win rate", icon: "trophy.fill",
                 value: record.winRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "–",
                 caption: record.played > 0 ? "\(record.text) in \(record.played) \(record.played == 1 ? "match" : "matches")" : "No scores logged")
            tile("Avg HR", icon: "heart.fill",
                 value: recentHR.map { "\($0)" } ?? "–",
                 caption: recentHR == nil ? "No heart rate, last 4 wks" : "bpm, last 4 weeks")
        }
    }

    private func tile(_ title: String, icon: String, value: String, caption: String) -> some View {
        ApexTile(title: title, systemImage: icon) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .apexDisplay(40)
                    .foregroundStyle(ApexColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            }
        }
    }

    // MARK: - Volume

    private func volumeCard(_ weeks: [TennisTrends.Week]) -> some View {
        let total = weeks.reduce(0) { $0 + $1.minutes }
        return ApexSectionCard(title: "Hours per week", systemImage: "chart.bar.fill", accentColor: ApexColor.tennis) {
            Text("\(hoursText(total)) over the last 12 weeks")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ApexColor.textPrimary)
            Chart(weeks, id: \.start) { week in
                BarMark(
                    x: .value("Week", week.start, unit: .weekOfYear),
                    y: .value("Hours", Double(week.minutes) / 60)
                )
                .foregroundStyle(ApexColor.tennis)
                .cornerRadius(3)
            }
            .chartXAxis { weekAxis }
            .frame(height: 160)
        }
    }

    // MARK: - Intensity

    private func intensityCard(_ weeks: [TennisTrends.Week]) -> some View {
        let withHR = weeks.filter { $0.averageHeartRate != nil }
        return ApexSectionCard(title: "Intensity", systemImage: "heart.fill", accentColor: ApexColor.accent) {
            if withHR.isEmpty {
                Text("No heart rate on your tennis sessions in the last 12 weeks. Sessions imported from Apple Watch, or with Avg HR filled in, show up here.")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            } else {
                Text("Average heart rate per week")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ApexColor.textPrimary)
                Chart(withHR, id: \.start) { week in
                    LineMark(
                        x: .value("Week", week.start, unit: .weekOfYear),
                        y: .value("BPM", week.averageHeartRate ?? 0)
                    )
                    .foregroundStyle(ApexColor.accent)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Week", week.start, unit: .weekOfYear),
                        y: .value("BPM", week.averageHeartRate ?? 0)
                    )
                    .foregroundStyle(ApexColor.accent)
                }
                // Points sit mid-week, so the domain must run to the end of the last week.
                .chartXScale(domain: (weeks.first?.start ?? Date())...(weeks.last.flatMap { Calendar.current.date(byAdding: .day, value: 7, to: $0.start) } ?? Date()))
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { weekAxis }
                .frame(height: 140)
            }
        }
    }

    private var weekAxis: some AxisContent {
        AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
        }
    }

    // MARK: - Win rate

    private func winRateCard(_ months: [TennisTrends.Month], overall: TennisTrends.Record) -> some View {
        ApexSectionCard(title: "Win rate by month", systemImage: "trophy.fill", accentColor: ApexColor.warning) {
            if overall.played == 0 {
                Text("Log a score (sets or games) on a tennis session to see your win rate. Drill-only sessions are not counted as matches.")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            } else {
                Chart(months, id: \.start) { month in
                    BarMark(
                        x: .value("Month", month.start, unit: .month),
                        y: .value("Win rate", (month.record.winRate ?? 0) * 100)
                    )
                    .foregroundStyle(month.record.played > 0 ? ApexColor.accent : Color.clear)
                    .cornerRadius(3)
                    .annotation(position: .top) {
                        if month.record.played > 0 {
                            Text(month.record.text)
                                .font(.caption2.bold())
                                .foregroundStyle(ApexColor.textSecondary)
                        }
                    }
                }
                .chartYScale(domain: 0...118) // headroom so the label on a 100% bar stays inside the chart
                .chartYAxis {
                    AxisMarks(values: [0.0, 50.0, 100.0]) { value in
                        AxisGridLine()
                        AxisValueLabel { Text("\(Int(value.as(Double.self) ?? 0))%") }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                    }
                }
                .frame(height: 150)
                Text("Won when you take more sets, or more games if no sets were logged. Labels show wins–losses, plus draws when there are any.")
                    .font(.caption2)
                    .foregroundStyle(ApexColor.textSecondary)
            }
        }
    }

    // MARK: - Drills

    private func drillsCard(_ drills: [TennisTrends.DrillStat]) -> some View {
        let stale = TennisTrends.staleDrills(drills)
        let untried = TennisDrillDatabase.all.filter { name in !drills.contains { $0.name == name } }
        let top = Array(drills.prefix(5))
        let maxCount = max(top.first?.count ?? 1, 1)
        return ApexSectionCard(title: "Drills", systemImage: "figure.tennis", accentColor: ApexColor.tennis) {
            if drills.isEmpty {
                Text("No drills logged yet. Pick the drills you worked on when you log a session.")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            } else {
                Text("Most practiced").apexLabel()
                ForEach(top, id: \.name) { drill in
                    HStack(spacing: 10) {
                        Text(drill.name)
                            .font(.caption.bold())
                            .foregroundStyle(ApexColor.textPrimary)
                            .lineLimit(1)
                            .frame(width: 130, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ApexColor.tennis)
                                .frame(width: geo.size.width * Double(drill.count) / Double(maxCount), height: 8)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(height: 16)
                        Text("\(drill.count)×")
                            .font(.caption.bold())
                            .foregroundStyle(ApexColor.textSecondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                if !stale.isEmpty {
                    Divider().background(ApexColor.cardBg2)
                    Text("Not practiced in 3 weeks").apexLabel()
                    ForEach(stale.prefix(5), id: \.name) { drill in
                        HStack {
                            Text(drill.name)
                                .font(.caption.bold())
                                .foregroundStyle(ApexColor.textPrimary)
                            Spacer()
                            Text("last \(drill.lastPracticed.dayAndMonth)")
                                .font(.caption)
                                .foregroundStyle(ApexColor.warning)
                        }
                    }
                }
                if !untried.isEmpty {
                    Text("\(untried.count) drills from the list never logged, for example \(untried.prefix(2).joined(separator: " and ")).")
                        .font(.caption2)
                        .foregroundStyle(ApexColor.textSecondary)
                }
            }
        }
    }

    // MARK: - Opponents

    private func opponentsCard(_ opponents: [TennisTrends.Opponent]) -> some View {
        ApexSectionCard(title: "Opponents", systemImage: "person.2.fill", accentColor: ApexColor.accent) {
            ForEach(Array(opponents.prefix(10).enumerated()), id: \.offset) { index, opponent in
                if index > 0 { Divider().background(ApexColor.cardBg2) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(opponent.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(ApexColor.textPrimary)
                        Spacer()
                        Text(opponent.record.played > 0 ? opponent.record.text : "No score")
                            .font(.subheadline.bold())
                            .foregroundStyle(recordColor(opponent.record))
                    }
                    Text("Last played \(opponent.lastPlayed.mediumDate)")
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                    if let note = opponent.latestNote {
                        Text("“\(note)”")
                            .font(.caption)
                            .italic()
                            .foregroundStyle(ApexColor.textSecondary)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    private func recordColor(_ record: TennisTrends.Record) -> Color {
        guard record.played > 0 else { return ApexColor.textSecondary }
        if record.won > record.lost { return ApexColor.success }
        if record.won < record.lost { return ApexColor.danger }
        return ApexColor.textPrimary
    }

    // MARK: - Formatting

    private func hoursText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let tenths = Int((Double(minutes) / 6).rounded())  // hours to one decimal, rounded half up
        return tenths % 10 == 0 ? "\(tenths / 10)h" : "\(tenths / 10).\(tenths % 10)h"
    }

    private func sessionsText(_ count: Int) -> String {
        count == 1 ? "1 session" : "\(count) sessions"
    }
}
