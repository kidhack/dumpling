import Foundation
import FoundationModels

@Generable
enum ItemCategory: String, CaseIterable {
    case event, task, location, link, idea, music, other
}

@Generable
struct SortDecision {
    @Guide(description: "event: a specific happening on a date (concert, dinner, appointment). task: something the user should do (buy, call, book, reply). location: a place to remember or visit with no specific date (restaurant, shop, bar, park, address). link: an article, video or page to read or watch later. idea: an idea or note to self. music: a song, album or artist. other: anything else.")
    var category: ItemCategory

    @Guide(description: "A specific 2-6 word title. No URL. Don't start with 'Reminder to' or 'Remember to'.")
    var title: String

    @Guide(description: "The date and time words exactly as written in the item, e.g. 'this Saturday 10am', 'Oct 24', 'before Friday'. Copy them; don't convert or calculate. Empty if the item has no date.")
    var datePhrase: String?

    @Guide(description: "Venue name or address for an event or location, if stated.")
    var location: String?
}

enum Sorter {
    static let instructions = """
        You sort things the user shared from their phone. Read the URL, text, the user's note and \
        quick tag, and decide what kind of item it is. The user's note states their intent and \
        outranks your reading of the content. Resolve relative dates ("Saturday", "next week") \
        against the current time you're given. When a page title and description are given, they come from the shared link itself. \
        A bare URL with no note asking for an action is a link, not a task. Restaurants, cafes, \
        bars, shops, parks and addresses are locations, even when the note says "try", "visit" or \
        "go"; a task is an errand like call, buy, book or pay. Only use date words that appear in \
        the shared item itself, never the current time.
        """

    enum Unavailable: Error {
        case model(SystemLanguageModel.Availability.UnavailableReason)
    }

    static var unavailableReason: SystemLanguageModel.Availability.UnavailableReason? {
        if case .unavailable(let reason) = SystemLanguageModel.default.availability { return reason }
        return nil
    }

    static func describe(_ item: Item, page: PageInfo? = nil, now: Date = .now) -> String {
        var lines = ["Current local time: \(now.formatted(.dateTime.weekday(.wide).year().month().day().hour().minute()))"]
        if let url = item.contentURL { lines.append("URL: \(url)") }
        if let title = page?.title { lines.append("Page title: \(title)") }
        if let description = page?.description { lines.append("Page description: \(description.prefix(600))") }
        if let text = item.contentText { lines.append("Text: \(text)") }
        if let note = item.userNote { lines.append("User's note: \(note)") }
        if let tag = item.tagLabel { lines.append("Quick tag chosen by user: \(tag)") }
        return lines.joined(separator: "\n")
    }

    /// The share sheet's quick tag is an explicit choice, so it wins over the model's category.
    static func category(forTag tag: String?) -> ItemCategory? {
        CategoryKind(quickTag: tag).flatMap { ItemCategory(rawValue: $0.rawValue) }
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

    /// What to file, after combining the model's decision with the page's own structured data.
    struct Plan: Equatable {
        var category: ItemCategory
        var title: String
        var start: Date?
        var end: Date?
        var allDay: Bool
        var location: String?
    }

    static func plan(_ decision: SortDecision, item: Item, page: PageInfo?) -> Plan {
        let resolved = resolveDate(grounded(decision.datePhrase, in: sharedText(of: item, page: page)))
        var plan = Plan(category: decision.category, title: cleanTitle(decision.title, for: item),
                        start: resolved?.date, end: nil, allDay: resolved?.allDay ?? true,
                        location: decision.location)
        // A page's structured event data is exact; it beats the model unless the user tagged the item otherwise.
        if let event = page?.event, (category(forTag: item.quickTag) ?? .event) == .event {
            plan.category = .event
            plan.start = event.start
            plan.end = event.end
            plan.allDay = event.allDay
            // The model's location guesses from page prose are unreliable; trust only structured venue data here.
            plan.location = event.location
        } else if item.quickTag == nil, plan.start == nil, plan.category != .location {
            // Undated items with a maps link or an address in what the user shared are places, whatever the
            // model said. A page's footer address alone isn't enough: plenty of non-place pages print one.
            let address = detectedAddress(in: [item.contentText, item.userNote].compactMap { $0 }.joined(separator: "\n"))
            if isMapsLink(item.contentURL) || address != nil {
                plan.category = .location
                plan.location = address ?? plan.location
                // The model titled it as a task ("buy morning bun"); the place name reads better.
                if let place = plan.location?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces),
                   !place.isEmpty, !isMapsLink(item.contentURL) {
                    plan.title = place
                }
            }
        }
        // A real address beats the model's guess, which is often just the place's name.
        if plan.category == .location {
            let found = detectedAddress(in: [item.contentText, item.userNote].compactMap { $0 }.joined(separator: "\n")) ?? page?.address
            plan.location = found ?? plan.location
        }
        return plan
    }

    static func isMapsLink(_ urlString: String?) -> Bool {
        guard let url = urlString.flatMap(URL.init(string:)), let host = url.host()?.lowercased() else { return false }
        return host == "maps.apple.com" || host == "maps.app.goo.gl" || host == "goo.gl" && url.path().hasPrefix("/maps")
            || (host.hasSuffix("google.com") && url.path().hasPrefix("/maps"))
    }

    /// A street address found by Apple's data detector, if the text contains one.
    static func detectedAddress(in text: String) -> String? {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return String(text[range])
    }

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
    static func sharedText(of item: Item, page: PageInfo? = nil) -> String {
        [item.contentURL, item.contentText, item.userNote, page?.title, page?.description]
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
