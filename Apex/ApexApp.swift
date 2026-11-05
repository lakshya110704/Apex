import SwiftUI
import SwiftData

@main
struct ApexApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            UserProfile.self,
            WorkoutSession.self,
            GymExercise.self,
            MealEntry.self,
            DailyPlan.self,
            Achievement.self,
            Project.self,
            MorningCheckIn.self,
            FocusSession.self,
            EveningCheckIn.self,
            WorkoutScheduleEntry.self,
        ])
    }
}
