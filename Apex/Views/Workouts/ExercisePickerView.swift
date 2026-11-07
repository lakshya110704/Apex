import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (ExerciseInfo) -> Void

    @State private var searchText = ""
    @State private var selectedGroup: MuscleGroup? = nil

    private var filtered: [ExerciseInfo] {
        var list = selectedGroup.map { ExerciseDatabase.byMuscleGroup($0) } ?? ExerciseDatabase.all
        if searchText.isNotEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Muscle group filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            groupChip(nil, label: "All")
                            ForEach(MuscleGroup.allCases, id: \.self) { group in
                                groupChip(group, label: group.rawValue)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }

                    // Exercise list
                    List(filtered) { exercise in
                        Button {
                            onSelect(exercise)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(ApexColor.accent.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: exercise.muscleGroup.systemImage)
                                        .font(.caption)
                                        .foregroundStyle(ApexColor.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(ApexColor.textPrimary)
                                    HStack(spacing: 6) {
                                        Text(exercise.muscleGroup.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(ApexColor.textSecondary)
                                        Text("·")
                                            .foregroundStyle(ApexColor.textSecondary)
                                        Text(exercise.equipment)
                                            .font(.caption)
                                            .foregroundStyle(ApexColor.textSecondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(ApexColor.accent.opacity(0.6))
                            }
                        }
                        .listRowBackground(ApexColor.cardBg)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Pick Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ApexColor.textSecondary)
                }
            }
        }
    }

    private func groupChip(_ group: MuscleGroup?, label: String) -> some View {
        let isSelected = selectedGroup == group
        return Button { selectedGroup = group } label: {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? ApexColor.background : ApexColor.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? ApexColor.accent : ApexColor.cardBg2)
                .clipShape(Capsule())
        }
    }
}
