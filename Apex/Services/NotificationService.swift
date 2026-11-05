import Foundation
import UserNotifications

@Observable
final class NotificationService {
    static let reminderIdentifier = "apex_streak_reminder"
    private static let reminderHour = 20 // 8pm

    var isAuthorized = false

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        isAuthorized = granted
    }

    /// Re-evaluates today's logging state and (re)schedules a single evening reminder if a streak
    /// is at risk or nothing has been logged yet. Safe to call repeatedly — always cancels first.
    func scheduleReminderIfNeeded(profile: UserProfile) {
        cancelReminder()
        guard isAuthorized else { return }

        let loggedWorkoutToday = profile.lastWorkoutDate?.isToday ?? false
        let loggedMealToday = profile.lastMealDate?.isToday ?? false
        let workoutAtRisk = profile.workoutStreak > 0 && !loggedWorkoutToday
        let mealAtRisk = profile.mealStreak > 0 && !loggedMealToday
        let nothingLoggedToday = !loggedWorkoutToday && !loggedMealToday

        guard workoutAtRisk || mealAtRisk || nothingLoggedToday else { return }

        let content = UNMutableNotificationContent()
        content.title = "Apex"
        content.body = reminderMessage(profile: profile, workoutAtRisk: workoutAtRisk, mealAtRisk: mealAtRisk)
        content.sound = .default

        let trigger = reminderTrigger()
        let request = UNNotificationRequest(identifier: Self.reminderIdentifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
    }

    private func reminderMessage(profile: UserProfile, workoutAtRisk: Bool, mealAtRisk: Bool) -> String {
        switch (workoutAtRisk, mealAtRisk) {
        case (true, true):
            return "Your \(profile.workoutStreak)-day workout streak and \(profile.mealStreak)-day meal streak are about to break — log something before midnight."
        case (true, false):
            return "Your \(profile.workoutStreak)-day workout streak is about to break — get a session in before midnight."
        case (false, true):
            return "Your \(profile.mealStreak)-day meal streak is about to break — log a meal before midnight."
        case (false, false):
            return "You haven't logged anything today. Log a workout or meal to start a streak."
        }
    }

    /// Fires at 8pm today if it hasn't passed yet, otherwise fires shortly after the app backgrounds
    /// (covers the case where the user opens the app late in the evening).
    private func reminderTrigger() -> UNNotificationTrigger {
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = Self.reminderHour
        components.minute = 0

        if let eightPM = Calendar.current.date(from: components), eightPM > now {
            let fireComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: eightPM)
            return UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)
        }
        return UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
    }
}
