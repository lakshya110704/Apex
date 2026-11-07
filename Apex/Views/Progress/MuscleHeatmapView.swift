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

    private var mutedColor: Color { MuscleGroupTracker.coolColor(scheme) }
    private var outlineColor: Color { Color.black.opacity(scheme == .dark ? 0.55 : 0.18) }

    private func color(for group: MuscleGroup) -> Color {
        MuscleGroupTracker.heatColor(sets: setCounts[group] ?? 0, scheme: scheme)
    }

    @ViewBuilder
    private func region<S: Shape>(_ shape: S, fill: Color) -> some View {
        shape.fill(fill).overlay(shape.stroke(outlineColor, lineWidth: 1.25))
    }

    var body: some View {
        ZStack {
            // Head + neck
            region(Circle(), fill: mutedColor).frame(width: 32, height: 32).position(x: 68, y: 20)
            region(RoundedRectangle(cornerRadius: 5, style: .continuous), fill: mutedColor)
                .frame(width: 16, height: 14).position(x: 68, y: 42)

            // Shoulders / traps
            region(Capsule(), fill: color(for: .shoulders))
                .frame(width: 34, height: 20).rotationEffect(.degrees(-16)).position(x: 30, y: 58)
            region(Capsule(), fill: color(for: .shoulders))
                .frame(width: 34, height: 20).rotationEffect(.degrees(16)).position(x: 106, y: 58)

            // Torso
            if facing == .front {
                // Pecs
                region(Capsule(), fill: color(for: .chest))
                    .frame(width: 30, height: 22).rotationEffect(.degrees(-6)).position(x: 55, y: 76)
                region(Capsule(), fill: color(for: .chest))
                    .frame(width: 30, height: 22).rotationEffect(.degrees(6)).position(x: 81, y: 76)
                // Abs
                region(RoundedRectangle(cornerRadius: 14, style: .continuous), fill: color(for: .core))
                    .frame(width: 34, height: 46).position(x: 68, y: 118)
            } else {
                region(RoundedRectangle(cornerRadius: 22, style: .continuous), fill: color(for: .back))
                    .frame(width: 52, height: 74).position(x: 68, y: 92)
            }

            // Arms (biceps front, triceps back)
            let armColor = facing == .front ? color(for: .biceps) : color(for: .triceps)
            region(Capsule(), fill: armColor).frame(width: 17, height: 98).position(x: 22, y: 104)
            region(Capsule(), fill: armColor).frame(width: 17, height: 98).position(x: 114, y: 104)

            // Hands
            region(Circle(), fill: mutedColor).frame(width: 13, height: 13).position(x: 22, y: 158)
            region(Circle(), fill: mutedColor).frame(width: 13, height: 13).position(x: 114, y: 158)

            // Thighs
            region(Capsule(), fill: color(for: .legs)).frame(width: 24, height: 74).position(x: 56, y: 174)
            region(Capsule(), fill: color(for: .legs)).frame(width: 24, height: 74).position(x: 80, y: 174)

            // Calves
            region(Capsule(), fill: color(for: .legs)).frame(width: 19, height: 52).position(x: 56, y: 230)
            region(Capsule(), fill: color(for: .legs)).frame(width: 19, height: 52).position(x: 80, y: 230)

            // Feet
            region(Capsule(), fill: mutedColor).frame(width: 24, height: 11).position(x: 56, y: 260)
            region(Capsule(), fill: mutedColor).frame(width: 24, height: 11).position(x: 80, y: 260)
        }
        .frame(width: 136, height: 270)
    }
}
