import SwiftUI
import SwiftData

struct MuscleHeatmapView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) private var workouts: [WorkoutSession]
    @State private var range: MuscleGroupTracker.TimeRange = .allTime
    @Environment(\.colorScheme) private var scheme

    private var setCounts: [MuscleGroup: Int] {
        MuscleGroupTracker.setCounts(from: workouts, range: range)
    }

    var body: some View {
        ZStack {
            ApexColor.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header

                    HStack(spacing: 24) {
                        VStack(spacing: 8) {
                            BodyFigureView(facing: .front, setCounts: setCounts)
                            Text("Front").font(.caption).foregroundStyle(ApexColor.textSecondary)
                        }
                        VStack(spacing: 8) {
                            BodyFigureView(facing: .back, setCounts: setCounts)
                            Text("Back").font(.caption).foregroundStyle(ApexColor.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    legend
                    breakdownList
                }
                .padding()
            }
        }
        .navigationTitle("Muscles Worked")
    }

    private var header: some View {
        HStack {
            Text("Sets by muscle group")
                .apexLabel()
            Spacer()
            Menu {
                ForEach(MuscleGroupTracker.TimeRange.allCases, id: \.self) { option in
                    Button(option.rawValue) { range = option }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(range.rawValue)
                    Image(systemName: "chevron.down")
                }
                .font(.caption.bold())
                .foregroundStyle(ApexColor.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ApexColor.cardBg2)
                .clipShape(Capsule())
            }
        }
    }

    private var legend: some View {
        VStack(spacing: 6) {
            LinearGradient(
                colors: [MuscleGroupTracker.coolColor(scheme), MuscleGroupTracker.hotColor(scheme)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 8)
            .clipShape(Capsule())

            HStack {
                Text("0").font(.caption2).foregroundStyle(ApexColor.textSecondary)
                Spacer()
                Text("\(MuscleGroupTracker.maxHeatSets)+ sets").font(.caption2).foregroundStyle(ApexColor.textSecondary)
            }
        }
    }

    private var breakdownList: some View {
        VStack(spacing: 0) {
            ForEach(MuscleGroupTracker.trackedGroups, id: \.self) { group in
                HStack {
                    Circle()
                        .fill(MuscleGroupTracker.heatColor(sets: setCounts[group] ?? 0, scheme: scheme))
                        .frame(width: 10, height: 10)
                    Text(group.rawValue)
                        .font(.caption)
                        .foregroundStyle(ApexColor.textPrimary)
                    Spacer()
                    Text("\(setCounts[group] ?? 0) sets")
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.textSecondary)
                }
                .padding(.vertical, 8)

                if group != MuscleGroupTracker.trackedGroups.last {
                    Divider().background(ApexColor.cardBg2)
                }
            }
        }
        .padding(14)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Body Figure

private struct BodyFigureView: View {
    enum Facing { case front, back }

    let facing: Facing
    let setCounts: [MuscleGroup: Int]
    @Environment(\.colorScheme) private var scheme

    private var summary: String {
        MuscleGroupTracker.trackedGroups
            .map { "\($0.rawValue) \(setCounts[$0] ?? 0) sets" }
            .joined(separator: ", ")
    }

    var body: some View {
        Canvas { context, size in
            let canvas = BodyFigure.canvas
            let scale = min(size.width / canvas.width, size.height / canvas.height)
            let transform = CGAffineTransform(translationX: (size.width - canvas.width * scale) / 2, y: 0)
                .scaledBy(x: scale, y: scale)
            for region in BodyFigure.regions(facing == .front ? .front : .back) {
                let path = Path(region.path).applying(transform)
                let fill: Color
                if let name = region.group, let group = MuscleGroup(rawValue: name) {
                    fill = MuscleGroupTracker.heatColor(sets: setCounts[group] ?? 0, scheme: scheme)
                } else {
                    fill = ApexColor.cardBg2
                }
                context.fill(path, with: .color(fill))
                context.stroke(path, with: .color(ApexColor.background), lineWidth: 1.2)
            }
        }
        .aspectRatio(BodyFigure.canvas.width / BodyFigure.canvas.height, contentMode: .fit)
        .frame(height: 340)
        .accessibilityElement()
        .accessibilityLabel(facing == .front ? "Front of body" : "Back of body")
        .accessibilityValue(summary)
    }
}
