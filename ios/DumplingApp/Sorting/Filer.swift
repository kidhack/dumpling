import EventKit
import Foundation

/// Writes sorted items into Reminders and Calendar. These sync to the Mac through iCloud.
@MainActor
final class Filer {
    static let remindersListName = "Dumpling"

    enum FilerError: LocalizedError {
        case remindersDenied, calendarDenied, noReminderSource, noDefaultCalendar

        var errorDescription: String? {
            switch self {
            case .remindersDenied: return "Reminders access is off. Turn it on in Settings › Apps › Dumpling."
            case .calendarDenied: return "Calendar access is off. Turn it on in Settings › Apps › Dumpling."
            case .noReminderSource: return "No Reminders account to create the Dumpling list in."
            case .noDefaultCalendar: return "No default calendar is set."
            }
        }
    }

    private let store = EKEventStore()

    /// Returns where the item went, e.g. "Reminders › Dumpling".
    func fileReminder(title: String, notes: String, url: URL?, due: Date?, allDay: Bool) async throws -> (place: String, id: String) {
        guard try await store.requestFullAccessToReminders() else { throw FilerError.remindersDenied }
        let list = try remindersList()
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = title
        reminder.notes = notes
        reminder.url = url
        if let due {
            let parts: Set<Calendar.Component> = allDay ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute]
            reminder.dueDateComponents = Calendar.current.dateComponents(parts, from: due)
        }
        try store.save(reminder, commit: true)
        return ("Reminders › \(list.title)", reminder.calendarItemIdentifier)
    }

    func fileEvent(title: String, notes: String, url: URL?, start: Date, end: Date?, allDay: Bool, location: String?) async throws -> (place: String, id: String) {
        guard try await store.requestWriteOnlyAccessToEvents() else { throw FilerError.calendarDenied }
        guard let calendar = store.defaultCalendarForNewEvents else { throw FilerError.noDefaultCalendar }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.notes = notes
        event.url = url
        event.location = location
        event.isAllDay = allDay
        event.startDate = start
        event.endDate = end ?? (allDay ? start : start.addingTimeInterval(2 * 60 * 60))
        try store.save(event, span: .thisEvent, commit: true)
        return ("Calendar › \(calendar.title)", event.calendarItemIdentifier)
    }

    private func remindersList() throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == Self.remindersListName }) {
            return existing
        }
        guard let source = store.defaultCalendarForNewReminders()?.source else { throw FilerError.noReminderSource }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = Self.remindersListName
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }
}
