import SwiftUI
import SwiftData

struct WorkoutScheduleEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [WorkoutScheduleEntry]

    // Mon-Sun order for display
    private let weekdays: [(Int, String)] = [
        (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Set your recurring weekly training plan. Apex will track what you scheduled vs. what you actually did.")
                            .font(.subheadline)
                            .foregroundStyle(ApexColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.top, 4)

                        ForEach(weekdays, id: \.0) { dayNum, dayName in
                            dayRow(dayNum: dayNum, dayName: dayName)
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Weekly Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(ApexColor.accent)
                }
            }
        }
    }

    private func dayRow(dayNum: Int, dayName: String) -> some View {
        let dayEntries = entries.filter { $0.dayOfWeek == dayNum && $0.isEnabled }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ApexColor.textPrimary)
                    .frame(width: 40, alignment: .leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WorkoutType.allCases, id: \.self) { type in
                            let isSelected = dayEntries.contains { $0.workoutType == type }
                            typeChip(type: type, isSelected: isSelected) {
                                toggleEntry(dayNum: dayNum, type: type, currentlySelected: isSelected)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if !dayEntries.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(ApexColor.success)
                    Text(dayEntries.map { $0.workoutType.rawValue }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                }
                .padding(.leading, 44)
            }

            Divider().background(ApexColor.cardBg2).padding(.leading, 44)
        }
        .padding(.horizontal)
    }

    private func typeChip(type: WorkoutType, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let color = Color.workoutTypeColor(type)
        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: type.systemImage)
                    .font(.caption2)
                Text(type.rawValue)
                    .font(.caption.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.2) : ApexColor.cardBg)
            .foregroundStyle(isSelected ? color : ApexColor.textSecondary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1))
        }
    }

    private func toggleEntry(dayNum: Int, type: WorkoutType, currentlySelected: Bool) {
        if currentlySelected {
            if let existing = entries.first(where: { $0.dayOfWeek == dayNum && $0.workoutType == type }) {
                context.delete(existing)
            }
        } else {
            let entry = WorkoutScheduleEntry(dayOfWeek: dayNum, workoutType: type)
            context.insert(entry)
        }
    }
}
