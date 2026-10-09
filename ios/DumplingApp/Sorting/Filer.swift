import EventKit
import Foundation

/// Writes sorted items into Reminders and Calendar (which sync to the Mac through iCloud),
/// reusing an existing event or reminder instead of adding a duplicate.
@MainActor
final class Filer {
    static let remindersListName = "Dumpling"

    struct Result {
        var place: String
        var id: String
        var alreadyExisted: Bool
    }

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

    let store = EKEventStore()

    // MARK: - Events

    func fileEvent(title: String, notes: String, url: URL?, start: Date, end: Date?, allDay: Bool, location: String?) async throws -> Result {
        guard try await store.requestFullAccessToEvents() else { throw FilerError.calendarDenied }

        if let existing = existingEvent(title: title, url: url, start: start) {
            return Result(place: "Calendar › \(existing.calendar.title)", id: existing.calendarItemIdentifier, alreadyExisted: true)
        }

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
        return Result(place: "Calendar › \(calendar.title)", id: event.calendarItemIdentifier, alreadyExisted: false)
    }

    /// Same link on the same day, or a similar title within an hour of the start.
    private func existingEvent(title: String, url: URL?, start: Date) -> EKEvent? {
        let day = Calendar.current.startOfDay(for: start)
        let predicate = store.predicateForEvents(withStart: day.addingTimeInterval(-86_400),
                                                 end: day.addingTimeInterval(2 * 86_400), calendars: nil)
        let candidates = store.events(matching: predicate)
        if let url, let byLink = candidates.first(where: { Self.mentions($0, url: url) }) {
            return byLink
        }
        return candidates.first {
            abs($0.startDate.timeIntervalSince(start)) <= 3600 && Self.similar($0.title ?? "", title)
        }
    }

    // MARK: - Reminders

    func fileReminder(title: String, notes: String, url: URL?, due: Date?, allDay: Bool) async throws -> Result {
        guard try await store.requestFullAccessToReminders() else { throw FilerError.remindersDenied }

        if let existing = await existingReminder(title: title, url: url) {
            return Result(place: "Reminders › \(existing.list)", id: existing.id, alreadyExisted: true)
        }

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
        return Result(place: "Reminders › \(list.title)", id: reminder.calendarItemIdentifier, alreadyExisted: false)
    }

    /// An incomplete reminder with the same link, or the same title.
    private func existingReminder(title: String, url: URL?) async -> (id: String, list: String)? {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let wantedTitle = Self.normalized(title)
        let wantedURL = url?.absoluteString
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let match = reminders?.first { reminder in
                    if let wantedURL, reminder.url?.absoluteString == wantedURL || (reminder.notes ?? "").contains(wantedURL) {
                        return true
                    }
                    return Self.normalized(reminder.title ?? "") == wantedTitle
                }
                continuation.resume(returning: match.map { ($0.calendarItemIdentifier, $0.calendar.title) })
            }
        }
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

    // MARK: - Lookup

    /// The live event or reminder an item was filed as, or nil if it was deleted.
    func calendarItem(id: String) -> EKCalendarItem? {
        store.calendarItem(withIdentifier: id)
    }

    // MARK: - Matching

    private static func mentions(_ event: EKEvent, url: URL) -> Bool {
        let link = url.absoluteString
        let base = link.components(separatedBy: "?").first ?? link
        return event.url?.absoluteString.hasPrefix(base) == true || (event.notes ?? "").contains(base)
    }

    nonisolated static func normalized(_ s: String) -> String {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Titles match if one contains the other, or they share a distinctive word (5+ letters).
    nonisolated static func similar(_ a: String, _ b: String) -> Bool {
        let x = normalized(a), y = normalized(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        if x.contains(y) || y.contains(x) { return true }
        let words = { (s: String) in Set(s.split(separator: " ").filter { $0.count >= 5 }) }
        return !words(x).isDisjoint(with: words(y))
    }
}
