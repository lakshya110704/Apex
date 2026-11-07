import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]
    @Query(sort: \MorningCheckIn.date, order: .reverse) private var checkIns: [MorningCheckIn]

    @Query(sort: \EveningCheckIn.date, order: .reverse) private var eveningCheckIns: [EveningCheckIn]

    @State private var healthKit    = HealthKitService()
    @State private var claude       = ClaudeService()
    @State private var gamification = GamificationService()
    @State private var calendar     = CalendarService()
    @State private var github       = GitHubService()
    @State private var focusTimer   = FocusTimerService()
    @State private var selectedTab  = 0
    @State private var showMorningCheckIn  = false
    @State private var showEveningCheckIn  = false

    private var todayCheckInDone: Bool {
        checkIns.first.map { $0.date.isToday && $0.isComplete } ?? false
    }
    private var todayEveningDone: Bool {
        eveningCheckIns.first.map { $0.date.isToday } ?? false
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(healthKit: healthKit, claude: claude, gamification: gamification, calendar: calendar, github: github, focusTimer: focusTimer)
                .tabItem { Label("Today",    systemImage: "sun.max.fill") }
                .tag(0)

            WorkoutsView(gamification: gamification, healthKit: healthKit)
                .tabItem { Label("Workouts", systemImage: "dumbbell.fill") }
                .tag(1)

            NutritionView(claude: claude, gamification: gamification)
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
                .tag(2)

            ApexProgressView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                .tag(3)

            CoachView(claude: claude, healthKit: healthKit, calendar: calendar, github: github)
                .tabItem { Label("Coach", systemImage: "brain.head.profile") }
                .tag(4)
        }
        .tint(ApexColor.accent)
        .fullScreenCover(isPresented: $showMorningCheckIn) {
            MorningCheckInView(healthKit: healthKit, claude: claude)
        }
        .fullScreenCover(isPresented: $showEveningCheckIn) {
            EveningCheckInView(claude: claude, healthKit: healthKit)
        }
        .onAppear {
            // Create default profile if needed
            if profiles.isEmpty {
                let profile = UserProfile(name: "")
                context.insert(profile)
                gamification.fetchOrCreateAchievements(context: context)
            }

            // Show morning check-in if not done today
            if !todayCheckInDone {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showMorningCheckIn = true
                }
            }

            // Show evening check-in after 7pm if not done
            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= 19 && !todayEveningDone {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showEveningCheckIn = true
                }
            }

            // Heavy condensed large titles
            UINavigationBar.appearance().largeTitleTextAttributes = [
                .font: UIFont.systemFont(ofSize: 34, weight: .heavy, width: .condensed)
            ]

            // Tab bar follows the system appearance
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = ApexColor.tabBar
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        .task {
            await gamification.notifications.requestAuthorization()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background, let profile = profiles.first else { return }
            gamification.notifications.scheduleReminderIfNeeded(profile: profile)
        }
    }
}
