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

                    // AI data sharing
                    Section {
                        Toggle("Share data with Google Gemini", isOn: Binding(
                            get: { claude.aiConsentGiven },
                            set: { claude.setAIConsent($0) }
                        ))
                        .foregroundStyle(ApexColor.textPrimary)
                        .tint(ApexColor.accent)
                        .listRowBackground(ApexColor.cardBg)
                    } header: {
                        Text("AI data sharing").foregroundStyle(ApexColor.textSecondary)
                    } footer: {
                        Text("When on, your health and activity summary, calendar event titles, meal photos and chat messages are sent to Google's Gemini API using your own key. Off by default. A local Ollama server does not send data to Google. AI output is an estimate, not medical or dietary advice.")
                            .foregroundStyle(ApexColor.textSecondary)
                    }

                    // API Key Section
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                if showAPIKey {
                                    TextField("AIza...", text: $apiKeyText)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(ApexColor.textPrimary)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                } else {
                                    SecureField("AIza...", text: $apiKeyText)
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
                            .onSubmit { saveAPIKey() }

                            if claude.apiKey.isNotEmpty {
                                Label("Key saved", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(ApexColor.success)
                            }
                        }
                        .listRowBackground(ApexColor.cardBg)

                        Button("Save API Key") { saveAPIKey() }
                            .foregroundStyle(ApexColor.accent)
                            .listRowBackground(ApexColor.cardBg)

                        Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                            Label("Get your free API key →", systemImage: "key.fill")
                                .font(.subheadline)
                                .foregroundStyle(ApexColor.accent)
                        }
                        .listRowBackground(ApexColor.cardBg)
                    } header: {
                        Text("Google AI (Required for meal analysis + planning)").foregroundStyle(ApexColor.textSecondary)
                    } footer: {
                        Text("Your API key is stored locally on your device and never shared.").foregroundStyle(ApexColor.textSecondary)
                    }

                    // Local AI Section
                    Section {
                        // Status row
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
                                Label("Connected — \(claude.localAIModel)", systemImage: "checkmark.circle.fill")
                                    .font(.caption.bold()).foregroundStyle(ApexColor.success)
                            } else {
                                Label("Unreachable", systemImage: "xmark.circle.fill")
                                    .font(.caption.bold()).foregroundStyle(ApexColor.danger)
                            }
                        }
                        .listRowBackground(ApexColor.cardBg)

                        HStack {
                            Text("PC IP Address")
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

                        Button("Save & Check Connection") { saveLocalAI() }
                            .foregroundStyle(ApexColor.accentCyan)
                            .listRowBackground(ApexColor.cardBg)

                    } header: {
                        Text("Local AI (Ollama)").foregroundStyle(ApexColor.textSecondary)
                    } footer: {
                        Text("Run Ollama on your PC with OLLAMA_HOST=0.0.0.0. When connected, the coach runs fully locally — no API needed. Gemini is the fallback when away from home.")
                            .foregroundStyle(ApexColor.textSecondary)
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
            }
            .navigationTitle("Settings")
            .preferredColorScheme(.dark)
            .onAppear {
                nameText = profile?.name ?? ""
                apiKeyText = claude.apiKey
                githubText = profile?.githubUsername ?? ""
                localHostText = claude.localAIHost
                localPortText = claude.localAIPort == 0 ? "11434" : "\(claude.localAIPort)"
                localModelText = claude.localAIModel.isNotEmpty ? claude.localAIModel : "llama3.2"
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

    private func saveAPIKey() {
        let trimmed = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        claude.setAPIKey(trimmed)
    }

    private func saveLocalAI() {
        let port = Int(localPortText) ?? 11434
        claude.setLocalAI(host: localHostText, port: port, model: localModelText)
    }
}
