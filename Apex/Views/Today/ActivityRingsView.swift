import SwiftUI

struct ActivityRingsView: View {
    let moveProgress: Double
    let exerciseProgress: Double
    let standProgress: Double
    let moveCalories: Double
    let exerciseMinutes: Double
    let standHours: Int

    private let outerSize: CGFloat  = 140
    private let middleSize: CGFloat = 104
    private let innerSize: CGFloat  = 68
    private let lineWidth: CGFloat  = 14

    var body: some View {
        HStack(spacing: 24) {
            // Rings
            ZStack {
                RingView(progress: moveProgress,     color: ApexColor.danger,   lineWidth: lineWidth, size: outerSize)
                RingView(progress: exerciseProgress, color: ApexColor.success,  lineWidth: lineWidth, size: middleSize)
                RingView(progress: standProgress,    color: ApexColor.accentCyan,lineWidth: lineWidth, size: innerSize)
            }
            .frame(width: outerSize, height: outerSize)

            // Stats
            VStack(alignment: .leading, spacing: 10) {
                ringStatRow(color: ApexColor.danger,    label: "Move",     value: "\(Int(moveCalories)) kcal")
                ringStatRow(color: ApexColor.success,   label: "Exercise", value: "\(Int(exerciseMinutes)) min")
                ringStatRow(color: ApexColor.accentCyan,label: "Stand",    value: "\(standHours) hrs")
            }
        }
    }

    private func ringStatRow(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(ApexColor.textSecondary)
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundStyle(ApexColor.textPrimary)
            }
        }
    }
}

#Preview {
    ActivityRingsView(
        moveProgress: 0.72,
        exerciseProgress: 0.55,
        standProgress: 0.83,
        moveCalories: 360,
        exerciseMinutes: 28,
        standHours: 10
    )
    .padding()
    .background(ApexColor.background)
}
