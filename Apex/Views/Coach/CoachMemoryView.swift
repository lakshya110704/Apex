import SwiftUI
import SwiftData

/// What the coach remembers between conversations: goals, notes and past chats. Everything here can be edited or forgotten.
struct CoachMemoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CoachMemory.createdAt, order: .reverse) private var memories: [CoachMemory]
    @Query(sort: \CoachMessageRecord.timestamp) private var chatHistory: [CoachMessageRecord]

    /// Called after past chats are deleted so the open conversation clears too.
    var onForgetChats: () -> Void = {}

    @State private var newText = ""
    @State private var newKind: CoachMemoryKind = .goal
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
                        TextField(newKind == .goal ? "e.g. Bench 100 kg by March" : "e.g. Left knee is sore, no jumping",
                                  text: $newText, axis: .vertical)
                            .focused($fieldFocused)
                            .lineLimit(1...3)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(trimmed.isEmpty)
                    }
                } header: {
                    Text("Tell the coach")
                } footer: {
                    Text("The coach also saves goals and notes when you mention them in chat. They go to your AI provider with every coach message.")
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
                Text("\(memory.addedByCoach ? "Saved from chat" : "Added by you") · \(memory.createdAt.mediumDate)")
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
        context.insert(CoachMemory(kind: newKind, text: text, addedByCoach: false))
        try? context.save()
        newText = ""
        fieldFocused = false
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
