import Foundation
import FoundationModels

@Generable
enum ItemCategory: String {
    case event, task, link, idea, music, other
}

@Generable
struct SortDecision {
    @Guide(description: "event: a specific happening on a date (concert, dinner, appointment). task: something the user should do (buy, call, book, reply). link: an article, video or page to read or watch later. idea: an idea or note to self. music: a song, album or artist. other: anything else.")
    var category: ItemCategory

    @Guide(description: "A specific 2-6 word title. No URL. Don't start with 'Reminder to' or 'Remember to'.")
    var title: String

    @Guide(description: "The date and time words exactly as written in the item, e.g. 'this Saturday 10am', 'Oct 24', 'before Friday'. Copy them; don't convert or calculate. Empty if the item has no date.")
    var datePhrase: String?

    @Guide(description: "Venue or address for an event, if stated.")
    var location: String?
}

enum Sorter {
    static let instructions = """
        You sort things the user shared from their phone. Read the URL, text, the user's note and \
        quick tag, and decide what kind of item it is. The user's note states their intent and \
        outranks your reading of the content. Resolve relative dates ("Saturday", "next week") \
        against the current time you're given. You can't open links; judge from the URL and text. \
        A bare URL with no note asking for an action is a link, not a task. Only use date words \
        that appear in the shared item itself, never the current time.
        """

    enum Unavailable: Error {
        case model(SystemLanguageModel.Availability.UnavailableReason)
    }

    static var unavailableReason: SystemLanguageModel.Availability.UnavailableReason? {
        if case .unavailable(let reason) = SystemLanguageModel.default.availability { return reason }
        return nil
    }

    static func describe(_ item: Item, now: Date = .now) -> String {
        var lines = ["Current local time: \(now.formatted(.dateTime.weekday(.wide).year().month().day().hour().minute()))"]
        if let url = item.contentURL { lines.append("URL: \(url)") }
        if let text = item.contentText { lines.append("Text: \(text)") }
        if let note = item.userNote { lines.append("User's note: \(note)") }
        if let tag = item.tagLabel { lines.append("Quick tag chosen by user: \(tag)") }
        return lines.joined(separator: "\n")
    }

    /// The share sheet's quick tag is an explicit choice, so it wins over the model's category.
    static func category(forTag tag: String?) -> ItemCategory? {
        switch tag {
        case "reminder": return .task
        case "event": return .event
        case "music": return .music
        case "software_idea": return .idea
        case "link_save": return .link
        default: return nil
        }
    }

    static func sort(prompt: String, quickTag: String?) async throws -> SortDecision {
        if let reason = unavailableReason { throw Unavailable.model(reason) }
        let session = LanguageModelSession(instructions: instructions)
        var decision = try await session.respond(to: prompt, generating: SortDecision.self).content
        if let forced = category(forTag: quickTag) { decision.category = forced }
        return decision
    }

    private static let timeWords = try! NSRegularExpression(
        pattern: #"\b\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)|\b\d{1,2}:\d{2}\b|\bnoon\b|\bmidnight\b|\btonight\b"#,
        options: [.caseInsensitive]
    )

    private static let genericTitles: Set<String> = ["", "reminder", "task", "event", "link", "idea", "music", "other", "note", "website"]

    /// The small model sometimes titles an item with its category; use the site or text instead.
    static func cleanTitle(_ title: String, for item: Item) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard genericTitles.contains(trimmed.lowercased()) else { return trimmed }
        if let host = item.contentURL.flatMap({ URL(string: $0)?.host() }) {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        let words = (item.contentText ?? "").split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "Shared item" : words
    }

    /// The text the user actually shared. URL separators become spaces so "oct-24" matches "Oct 24".
    static func sharedText(of item: Item) -> String {
        [item.contentURL, item.contentText, item.userNote]
            .compactMap { $0 }
            .joined(separator: " ")
            .replacingOccurrences(of: #"[-_/+.]"#, with: " ", options: .regularExpression)
    }

    /// The model sometimes copies the current-time line as a date; only keep phrases found in the item.
    static func grounded(_ phrase: String?, in shared: String) -> String? {
        guard let phrase = phrase?.trimmingCharacters(in: .whitespacesAndNewlines), !phrase.isEmpty else { return nil }
        let normalized = phrase.replacingOccurrences(of: #"[-_/+.]"#, with: " ", options: .regularExpression)
        return shared.range(of: normalized, options: [.caseInsensitive, .diacriticInsensitive]) != nil ? phrase : nil
    }

    /// Turns the model's date words into a date with Apple's date parser; the small model is bad at date math.
    /// Without explicit time words the result is all-day.
    static func resolveDate(_ phrase: String?) -> (date: Date, allDay: Bool)? {
        guard let phrase = phrase?.trimmingCharacters(in: .whitespacesAndNewlines), !phrase.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: phrase, range: NSRange(phrase.startIndex..., in: phrase)),
              let date = match.date
        else { return nil }

        let hasTime = timeWords.firstMatch(in: phrase, range: NSRange(phrase.startIndex..., in: phrase)) != nil
        return hasTime ? (date, false) : (Calendar.current.startOfDay(for: date), true)
    }
}
