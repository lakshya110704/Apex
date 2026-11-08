import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    var claude: ClaudeService
    var gamification: GamificationService

    @State private var nameText = ""
    @State private var apiKeyText = ""
    @State private var modelText = ""
    @State private var savedNotice: String?
    @State private var saveCount = 0
    @State private var isTesting = false
    @State private var testResult: (ok: Bool, text: String)?
    @State private var foundModels: [String] = []
    @State private var isFindingModels = false
    @State private var modelsError: String?
    @State private var githubText = ""
    @State private var showAPIKey = false
    @State private var showingOnboarding = false
    // Local AI
    @State private var localHostText = ""
    @State private var localPortText = "11434"
    @State private var localModelText = "llama3.2"

    var body: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()

                List {
                    // Profile Section
                    Section {
                        HStack {
                            Text("Name")
                                .foregroundStyle(ApexColor.textSecondary)
                            Spacer()
                            TextField("Your name", text: $nameText)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(ApexColor.textPrimary)
                                .autocorrectionDisabled()
                                .onSubmit { saveName() }
                        }
                        .listRowBackground(ApexColor.cardBg)

                        HStack {
                            Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                                .foregroundStyle(ApexColor.textSecondary)
                            Spacer()
                            TextField("username", text: $githubText)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(ApexColor.textPrimary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onSubmit { saveGitHub() }
                        }
                        .listRowBackground(ApexColor.cardBg)
                    } header: {
                        Text("Profile").foregroundStyle(ApexColor.textSecondary)
                    } footer: {
                        Text("GitHub username pulls today's commit activity into your AI coach context.")
                            .foregroundStyle(ApexColor.textSecondary)
                    }

                    // AI provider
                    Section {
                        Picker("Provider", selection: Binding(
                            get: { claude.provider },
                            set: { choose($0) }
                        )) {
                            ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
                        }
                        .foregroundStyle(ApexColor.textPrimary)
                        .tint(ApexColor.accent)
                        .listRowBackground(ApexColor.cardBg)
                    } header: {
                        Text("AI provider").foregroundStyle(ApexColor.textSecondary)
                    } footer: {
                        Text("Bring your own key for Gemini, OpenAI or Claude, or run a local Ollama server. Apex has no server of its own: requests go from this phone straight to the provider you pick. AI output is an estimate, not medical or dietary advice.")
                            .foregroundStyle(ApexColor.textSecondary)
                    }

                    if claude.provider.isCloud {
                        cloudProviderSection(claude.provider)
                    } else {
                        localProviderSection
                    }

                    // Stats Section
                    if let profile {
                        Section {
                            settingsStatRow(label: "Level",          value: "\(profile.level)")
                            settingsStatRow(label: "Total XP",       value: "\(profile.xpPoints.formatted()) XP")
                            settingsStatRow(label: "Workout Streak", value: "\(profile.workoutStreak) days")
                            settingsStatRow(label: "Member Since",   value: profile.createdAt.dayAndMonth)
                        } header: {
                            Text("Your Stats").foregroundStyle(ApexColor.textSecondary)
                        }
                        .listRowBackground(ApexColor.cardBg)
                    }

                    // Seed achievements
                    Section {
                        Button("Initialize Achievements") {
                            gamification.fetchOrCreateAchievements(context: context)
                        }
                        .foregroundStyle(ApexColor.warning)
                        .listRowBackground(ApexColor.cardBg)
                    } header: {
                        Text("Data").foregroundStyle(ApexColor.textSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
                .sensoryFeedback(.success, trigger: saveCount)
            }
            .navigationTitle("Settings")
            .onAppear {
                nameText = profile?.name ?? ""
                loadProviderFields()
                githubText = profile?.githubUsername ?? ""
                localHostText = claude.localAIHost
                localPortText = claude.localAIPort == 0 ? "11434" : "\(claude.localAIPort)"
                localModelText = claude.localAIModel
                if localHostText.isNotEmpty {
                    Task { await claude.checkLocalAIAvailability() }
                }
            }
        }
    }

    private func settingsStatRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(ApexColor.textSecondary)
            Spacer()
            Text(value).foregroundStyle(ApexColor.textPrimary).bold()
        }
        .listRowBackground(ApexColor.cardBg)
    }

    private func saveName() {
        if let profile {
            profile.name = nameText
        } else {
            let newProfile = UserProfile(name: nameText)
            context.insert(newProfile)
        }
    }

    private func saveGitHub() {
        if let profile {
            profile.githubUsername = githubText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func choose(_ provider: AIProvider) {
        claude.setProvider(provider)
        loadProviderFields()
    }

    private func loadProviderFields() {
        apiKeyText = claude.apiKey
        modelText = claude.provider.isCloud ? claude.model(for: claude.provider) : ""
        showAPIKey = false
        testResult = nil
        foundModels = []
        modelsError = nil
        savedNotice = nil
        loadModelsIfKeySaved()
    }

    private func showNotice(_ text: String) {
        savedNotice = text
        saveCount += 1
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { if savedNotice == text { savedNotice = nil } }
        }
    }

    private func saveCloudProvider() {
        let provider = claude.provider
        claude.setAPIKey(typedKey, for: provider)
        claude.setModel(modelText == provider.defaultModel ? "" : modelText, for: provider)
        testResult = nil
        withAnimation { showNotice(typedKey.isEmpty ? "Key removed" : "Key and model updated") }
        foundModels = []
        modelsError = nil
        loadModelsIfKeySaved()
    }

    private func chooseModel(_ name: String, for provider: AIProvider) {
        modelText = name
        claude.setModel(name == provider.defaultModel ? "" : name, for: provider)
        testResult = nil
        withAnimation { showNotice("Model updated") }
    }

    private func loadModelsIfKeySaved() {
        guard claude.provider.isCloud, !claude.apiKey.isEmpty else { return }
        let key = claude.apiKey
        Task { await loadModels(key: key) }
    }

    private var typedKey: String { apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines) }

    @ViewBuilder
    private func keyStatus(_ provider: AIProvider) -> some View {
        let saved = claude.apiKey(for: provider)
        if let notice = savedNotice {
            Label(notice, systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ApexColor.success)
        } else if typedKey.isEmpty && !saved.isEmpty {
            Label("A key is saved. Clear the field and save to remove it.", systemImage: "key.fill")
                .font(.caption)
                .foregroundStyle(ApexColor.textSecondary)
        } else if !typedKey.isEmpty && typedKey != saved {
            Label("Not saved yet. Tap Save key.", systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ApexColor.warning)
        } else if !saved.isEmpty {
            Label("Key saved", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(ApexColor.success)
        }
    }

    private func runTest() async {
        testResult = nil
        guard !typedKey.isEmpty else { testResult = (false, "Enter a key first."); return }
        isTesting = true
        defer { isTesting = false }
        do {
            try await claude.testConnection(apiKey: typedKey, model: modelText.trimmingCharacters(in: .whitespaces))
            testResult = (true, "Connected. The key and model work.")
        } catch {
            testResult = (false, error.localizedDescription)
        }
    }

    private func loadModels(key: String) async {
        modelsError = nil
        isFindingModels = true
        defer { isFindingModels = false }
        do {
            foundModels = try await claude.listModels(apiKey: key)
        } catch {
            foundModels = []
            modelsError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func modelRow(_ provider: AIProvider) -> some View {
        if isFindingModels {
            HStack {
                Text("Model").foregroundStyle(ApexColor.textSecondary)
                Spacer()
                ProgressView().scaleEffect(0.8)
            }
            .listRowBackground(ApexColor.cardBg)
        } else if !foundModels.isEmpty {
            Picker("Model", selection: Binding(
                get: { modelText },
                set: { chooseModel($0, for: provider) }
            )) {
                if !foundModels.contains(modelText) {
                    Text("\(modelText) (not available)").tag(modelText)
                }
                ForEach(foundModels, id: \.self) { Text($0).tag($0) }
            }
            .foregroundStyle(ApexColor.textPrimary)
            .tint(ApexColor.accent)
            .listRowBackground(ApexColor.cardBg)

            if !foundModels.contains(modelText) {
                Label("This key can't use \(modelText). Pick another model.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ApexColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(ApexColor.cardBg)
            }
        } else {
            HStack {
                Text("Model").foregroundStyle(ApexColor.textSecondary)
                Spacer()
                TextField(provider.defaultModel, text: $modelText)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(ApexColor.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { saveCloudProvider() }
            }
            .listRowBackground(ApexColor.cardBg)

            if let error = modelsError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(ApexColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(ApexColor.cardBg)
                Button("Reload models") { loadModelsIfKeySaved() }
                    .foregroundStyle(ApexColor.accent)
                    .listRowBackground(ApexColor.cardBg)
            } else {
                Text("The model list appears here once a valid key is saved.")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
                    .listRowBackground(ApexColor.cardBg)
            }
        }
    }

    @ViewBuilder
    private func cloudProviderSection(_ provider: AIProvider) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if showAPIKey {
                        TextField(provider.keyPlaceholder, text: $apiKeyText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(ApexColor.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField(provider.keyPlaceholder, text: $apiKeyText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(ApexColor.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(ApexColor.textSecondary)
                    }
                }
                .onSubmit { saveCloudProvider() }

                keyStatus(provider)
            }
            .listRowBackground(ApexColor.cardBg)

            Button("Save key") { saveCloudProvider() }
                .foregroundStyle(ApexColor.accent)
                .listRowBackground(ApexColor.cardBg)

            modelRow(provider)

            Button {
                Task { await runTest() }
            } label: {
                HStack {
                    Text("Test connection")
                    if isTesting { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(isTesting)
            .foregroundStyle(ApexColor.accent)
            .listRowBackground(ApexColor.cardBg)

            if let result = testResult {
                Label(result.text, systemImage: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(result.ok ? ApexColor.success : ApexColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(ApexColor.cardBg)
            }

            if let url = provider.keyURL {
                Link(destination: url) {
                    Label("Get an API key", systemImage: "key.fill")
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.accent)
                }
                .listRowBackground(ApexColor.cardBg)
            }

            Toggle("Share data with \(provider.company)", isOn: Binding(
                get: { claude.consent(for: provider) },
                set: { claude.setConsent($0, for: provider) }
            ))
            .foregroundStyle(ApexColor.textPrimary)
            .tint(ApexColor.accent)
            .listRowBackground(ApexColor.cardBg)
        } header: {
            Text("\(provider.displayName) key").foregroundStyle(ApexColor.textSecondary)
        } footer: {
            Text("When sharing is on, your health and activity summary, calendar event titles, meal photos and chat messages are sent to \(provider.company) using your own key. Off by default. The key is stored in this device's Keychain.")
                .foregroundStyle(ApexColor.textSecondary)
        }
    }

    private var localProviderSection: some View {
        Section {
            HStack {
                Text("Status")
                    .foregroundStyle(ApexColor.textSecondary)
                Spacer()
                if claude.isCheckingLocalAI {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Checking…").font(.caption).foregroundStyle(ApexColor.textSecondary)
                    }
                } else if localHostText.isEmpty {
                    Text("Not configured").font(.caption).foregroundStyle(ApexColor.textSecondary)
                } else if claude.isLocalAIAvailable {
                    Label("Connected: \(claude.localAIModel)", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold()).foregroundStyle(ApexColor.success)
                } else {
                    Label("Unreachable", systemImage: "xmark.circle.fill")
                        .font(.caption.bold()).foregroundStyle(ApexColor.danger)
                }
            }
            .listRowBackground(ApexColor.cardBg)

            HStack {
                Text("Server address")
                    .foregroundStyle(ApexColor.textSecondary)
                Spacer()
                TextField("192.168.1.x", text: $localHostText)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(ApexColor.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    .onSubmit { saveLocalAI() }
            }
            .listRowBackground(ApexColor.cardBg)

            HStack {
                Text("Port")
                    .foregroundStyle(ApexColor.textSecondary)
                Spacer()
                TextField("11434", text: $localPortText)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(ApexColor.textPrimary)
                    .keyboardType(.numberPad)
                    .onSubmit { saveLocalAI() }
            }
            .listRowBackground(ApexColor.cardBg)

            HStack {
                Text("Model")
                    .foregroundStyle(ApexColor.textSecondary)
                Spacer()
                TextField("llama3.2", text: $localModelText)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(ApexColor.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { saveLocalAI() }
            }
            .listRowBackground(ApexColor.cardBg)

            Button("Save and check connection") { saveLocalAI() }
                .foregroundStyle(ApexColor.accent)
                .listRowBackground(ApexColor.cardBg)
        } header: {
            Text("Local AI (Ollama)").foregroundStyle(ApexColor.textSecondary)
        } footer: {
            Text("Run Ollama on your own computer with OLLAMA_HOST=0.0.0.0. Nothing leaves your network. Meal photo analysis is not available with a local model; use Type it out or a cloud provider.")
                .foregroundStyle(ApexColor.textSecondary)
        }
    }

    private func saveLocalAI() {
        let port = Int(localPortText) ?? 11434
        claude.setLocalAI(host: localHostText, port: port, model: localModelText)
    }
}
