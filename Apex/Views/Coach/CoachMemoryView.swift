import SwiftUI
import SwiftData

/// What the coach remembers between conversations: goals, notes, schedule changes from chat and past chats.
/// Everything here can be forgotten, and any change here rebuilds today's plan.
struct CoachMemoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CoachMemory.createdAt, order: .reverse) private var memories: [CoachMemory]
    @Query(sort: \CoachMessageRecord.timestamp) private var chatHistory: [CoachMessageRecord]
    @Query private var scheduleEntries: [WorkoutScheduleEntry]

    /// Called after past chats are deleted so the open conversation clears too.
    var onForgetChats: () -> Void = {}

    @State private var newText = ""
    @State private var newKind: CoachMemoryKind = .goal
    @State private var todayOnly = false
    @State private var confirmingForgetChats = false
    @State private var confirmingForgetAll = false
    @FocusState private var fieldFocused: Bool

    private var chatDays: Int {
        Set(chatHistory.map { $0.timestamp.startOfDay }).count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Type", selection: $newKind) {
                        ForEach(CoachMemoryKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        TextField(newKind == .goal ? "e.g. Bench 100 kg by March"
                                  : (todayOnly ? "e.g. Furniture shopping at 13:30" : "e.g. Left knee is sore, no jumping"),
                                  text: $newText, axis: .vertical)
                            .focused($fieldFocused)
                            .lineLimit(1...3)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(trimmed.isEmpty)
                    }
                    if newKind == .note {
                        Toggle("Only today", isOn: $todayOnly)
                    }
                } header: {
                    Text("Tell the coach")
                } footer: {
                    Text("Today's plan updates itself when you add or forget something here. The coach also saves goals, notes and changes to your weekly schedule when you mention them in chat. They go to your AI provider with coach messages and plan requests.")
                }

                ForEach(CoachMemoryKind.allCases, id: \.self) { kind in
                    let items = memories.filter { $0.kind == kind }
                    if !items.isEmpty {
                        Section(kind.pluralLabel) {
                            ForEach(items) { memory in
                                row(memory)
                                    .swipeActions {
                                        Button(role: .destructive) { delete(memory) } label: {
                                            Label("Forget", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }

                if !coachSchedule.isEmpty {
                    Section {
                        ForEach(coachSchedule) { group in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "calendar")
                                    .foregroundStyle(ApexColor.accent)
                                    .frame(width: 20)
                                Text(group.label)
                                    .foregroundStyle(ApexColor.textPrimary)
                            }
                            .swipeActions {
                                Button(role: .destructive) { remove(group.entries) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("Weekly schedule from chat")
                    } footer: {
                        Text("Swipe to take a session off your week. You can also change it in Workouts, Edit plan.")
                    }
                }

                Section {
                    LabeledContent("Saved chats", value: chatDays == 0 ? "None" : "\(chatHistory.count) messages over \(chatDays) day\(chatDays == 1 ? "" : "s")")
                    if !chatHistory.isEmpty {
                        Button("Forget past chats", role: .destructive) { confirmingForgetChats = true }
                    }
                    if !memories.isEmpty || !chatHistory.isEmpty {
                        Button("Forget everything", role: .destructive) { confirmingForgetAll = true }
                    }
                } header: {
                    Text("Conversations")
                } footer: {
                    Text("Today's chat stays on screen. A short recap of the last \(CoachMemoryEngine.maxPastSessions) days with a chat is sent with each message so the coach can refer back. Everything is stored on this iPhone only.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ApexColor.background.ignoresSafeArea())
            .onAppear(perform: forgetExpired)
            .navigationTitle("Coach Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(ApexColor.accent)
                }
            }
            .confirmationDialog("Forget past chats?", isPresented: $confirmingForgetChats, titleVisibility: .visible) {
                Button("Forget chats", role: .destructive) { forgetChats() }
            } message: {
                Text("Deletes every saved coach message. Goals and notes stay.")
            }
            .confirmationDialog("Forget everything?", isPresented: $confirmingForgetAll, titleVisibility: .visible) {
                Button("Forget everything", role: .destructive) {
                    for memory in memories { context.delete(memory) }
                    forgetChats()
                }
            } message: {
                Text("Deletes all goals, notes and saved coach messages.")
            }
        }
    }

    private var trimmed: String { newText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func row(_ memory: CoachMemory) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: memory.kind.icon)
                .foregroundStyle(ApexColor.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(memory.text)
                    .foregroundStyle(ApexColor.textPrimary)
                let scope = memory.item.scopeLabel()
                Text("\(memory.addedByCoach ? "Saved from chat" : "Added by you") · \(scope.isEmpty ? memory.createdAt.mediumDate : scope.capitalizedFirst)")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            }
        }
    }

    private func add() {
        let text = CoachMemoryEngine.clip(trimmed, CoachMemoryEngine.maxMemoryLength)
        guard text.isNotEmpty, !CoachMemoryEngine.isDuplicate(text, of: memories.map(\.text)) else {
            newText = ""
            return
        }
        let today = Date().startOfDay
        let oneDay = newKind == .note && todayOnly
        context.insert(CoachMemory(kind: newKind, text: text, addedByCoach: false,
                                   validFrom: oneDay ? today : nil, validUntil: oneDay ? today : nil))
        try? context.save()
        newText = ""
        todayOnly = false
        fieldFocused = false
    }

    /// Schedule sessions the coach set from chat, grouped so "tennis Mon–Fri at 11:30" is one row.
    private struct ScheduleGroup: Identifiable {
        let label: String
        let entries: [WorkoutScheduleEntry]
        var id: String { label }
    }

    private var coachSchedule: [ScheduleGroup] {
        let mine = scheduleEntries.filter { $0.addedByCoach && $0.isEnabled }
        let groups = Dictionary(grouping: mine) { "\($0.workoutTypeRaw)|\($0.startMinutes ?? -1)|\($0.startsOn?.timeIntervalSince1970 ?? 0)" }
        return groups.values.map { entries in
            let first = entries[0]
            let label = PlanUpdateEngine.describe(type: first.workoutType, days: entries.map(\.dayOfWeek),
                                                  startMinutes: first.startMinutes, startsOn: first.startsOn)
            return ScheduleGroup(label: label, entries: entries)
        }
        .sorted { $0.label < $1.label }
    }

    private func remove(_ entries: [WorkoutScheduleEntry]) {
        for entry in entries { context.delete(entry) }
        try? context.save()
    }

    private func forgetExpired() {
        let expired = memories.filter { $0.item.isExpired() }
        guard !expired.isEmpty else { return }
        for memory in expired { context.delete(memory) }
        try? context.save()
    }

    private func delete(_ memory: CoachMemory) {
        context.delete(memory)
        try? context.save()
    }

    private func forgetChats() {
        for record in chatHistory { context.delete(record) }
        try? context.save()
        onForgetChats()
    }
}
