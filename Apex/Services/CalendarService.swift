import Foundation
import EventKit
import Observation

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startTime: Date
    let endTime: Date
    let calendarName: String
    let isAllDay: Bool

    var durationMinutes: Int { max(0, Int(endTime.timeIntervalSince(startTime) / 60)) }
    var timeRange: String { isAllDay ? "All day" : "\(startTime.shortTime) – \(endTime.shortTime)" }
    var summary: String { "\(timeRange): \(title)" }
}

@Observable
final class CalendarService {
    var todayEvents: [CalendarEvent] = []
    var isAuthorized = false

    private let store = EKEventStore()

    func requestAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            isAuthorized = true
            await fetchTodayEvents()
        case .notDetermined:
            do {
                let granted = try await store.requestFullAccessToEvents()
                isAuthorized = granted
                if granted { await fetchTodayEvents() }
            } catch {
                isAuthorized = false
            }
        default:
            isAuthorized = false
        }
    }

    func fetchTodayEvents() async {
        guard isAuthorized else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        todayEvents = events
            .compactMap { e -> CalendarEvent? in
                guard let title = e.title, !title.isEmpty,
                      let startDate = e.startDate, let endDate = e.endDate else { return nil }
                return CalendarEvent(
                    id: e.eventIdentifier ?? UUID().uuidString,
                    title: title,
                    startTime: startDate,
                    endTime: endDate,
                    calendarName: e.calendar?.title ?? "",
                    isAllDay: e.isAllDay
                )
            }
            .sorted { $0.startTime < $1.startTime }
    }
}
