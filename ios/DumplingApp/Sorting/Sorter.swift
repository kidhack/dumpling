import Foundation
import FoundationModels

@Generable
enum ItemCategory: String, CaseIterable {
    case event, task, location, shopping, media, link, idea

    /// Also reads categories saved before Music became Media and Other became Idea.
    init?(stored: String?) {
        switch stored {
        case "music": self = .media
        case "other": self = .idea
        default:
            guard let stored, let category = ItemCategory(rawValue: stored) else { return nil }
            self = category
        }
    }
}

/// What kind of media, for the model to choose. Mirrors `MediaKind`, which the share extension also uses.
@Generable
enum MediaType: String, CaseIterable {
    case music, book, podcast, audiobook, article, blog, video
}

@Generable
struct SortDecision {
    @Guide(description: "event: a specific happening on a date (concert, dinner, appointment). task: something the user should do (call, book, reply, pay). location: a place to remember or visit with no specific date (restaurant, bar, park, address). shopping: a product to buy or research (a product page, gear, a gift idea, a store listing). media: something to read, watch or listen to (a song, album, book, podcast, audiobook, news article, blog post or video). link: a website, app or tool to check out. idea: an idea, a note to self, or anything else.")
    var category: ItemCategory

    @Guide(description: "What kind of media it is, or would be: music (song, album, artist), book, podcast, audiobook, article (news story), blog (blog post or personal essay) or video. Ignored unless the category is media.")
    var mediaType: MediaType

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
        A bare URL with no note asking for an action is not a task. Articles, news stories, blog posts, \
        essays, videos, songs, books and podcasts are media; a link is a website, app or tool to check out. \
        Product pages and things to buy are shopping. Restaurants, cafes, \
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
        var mediaKind: MediaKind?
        var title: String
        var start: Date?
        var end: Date?
        var allDay: Bool
        var location: String?
    }

    static func plan(_ decision: SortDecision, item: Item, page: PageInfo?) -> Plan {
        let resolved = resolveDate(grounded(decision.datePhrase, in: sharedText(of: item, page: page)))
        var plan = Plan(category: decision.category,
                        mediaKind: MediaKind(rawValue: decision.mediaType.rawValue),
                        title: cleanTitle(decision.title, for: item),
                        start: resolved?.date, end: nil, allDay: resolved?.allDay ?? true,
                        location: decision.location)
        // Links to well-known media services say exactly what they are.
        if let kind = mediaKind(forLink: item.contentURL), (category(forTag: item.quickTag) ?? .media) == .media {
            plan.category = .media
            plan.mediaKind = kind
            plan.location = nil
            return plan
        }
        // What a page declares itself (schema.org or og:type) beats the model's reading of it: an article, a
        // blog post, a video, a product... unless the user tagged the item otherwise.
        if item.quickTag == nil, page?.place == nil, page?.event == nil, page?.looksLikeVenue != true {
            if let kind = page?.declaredMedia {
                plan.category = .media
                plan.mediaKind = kind
                plan.location = nil
                plan.start = nil
                return plan
            }
            if page?.declaresProduct == true {
                plan.category = .shopping
                plan.location = nil
                plan.start = nil
                return plan
            }
        }
        // A maps link names its place exactly; it beats the model unless the user tagged the item otherwise.
        if let place = page?.place, (category(forTag: item.quickTag) ?? .location) == .location {
            plan.category = .location
            plan.title = place.name
            plan.location = place.address
            plan.start = nil
            return plan
        }
        // A page's structured event data is exact; it beats the model unless the user tagged the item otherwise.
        if let event = page?.event, (category(forTag: item.quickTag) ?? .event) == .event {
            plan.category = .event
            plan.start = event.start
            plan.end = event.end
            plan.allDay = event.allDay
            // The model's location guesses from page prose are unreliable; trust only structured venue data here.
            plan.location = event.location
        } else if item.quickTag == nil, plan.start == nil, plan.category != .location, page?.looksLikeVenue == true {
            // A restaurant's or shop's own website is a place, whatever the model said.
            plan.category = .location
            plan.title = page?.title.map(placeName) ?? plan.title
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
        // Dates are for events and tasks. An article's publish date (often in its URL) isn't when to do anything.
        if plan.category != .event && plan.category != .task {
            plan.start = nil
            plan.end = nil
        }
        // A real address beats the model's guess, which is often just the place's name.
        if plan.category == .location {
            let found = detectedAddress(in: [item.contentText, item.userNote].compactMap { $0 }.joined(separator: "\n")) ?? page?.address
            plan.location = found ?? plan.location
        } else if plan.category != .event {
            // Only places and events have an address; for anything else the model's guess was the URL or title.
            plan.location = nil
        }
        return plan
    }

    /// Page titles like "The Franklin Mortgage & Investment Co. | Bar in Philadelphia" name the place first.
    static func placeName(_ title: String) -> String {
        for separator in [" | ", " • ", " · ", " – ", " — ", " - "] {
            if let first = title.components(separatedBy: separator).first, first.count >= 2, first != title {
                return first.trimmingCharacters(in: .whitespaces)
            }
        }
        return title
    }

    /// The kind of media a link to a well-known service is: Apple Music, Spotify, Apple Podcasts, Apple Books,
    /// Audible, Goodreads, YouTube and so on. Nil for anything else.
    static func mediaKind(forLink urlString: String?) -> MediaKind? {
        guard let url = urlString.flatMap(URL.init(string:)), var host = url.host()?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasPrefix("m.") { host.removeFirst(2) }
        let path = url.path().lowercased()
        switch host {
        case "music.apple.com", "tidal.com", "listen.tidal.com", "soundcloud.com", "music.youtube.com", "deezer.com":
            return .music
        case "podcasts.apple.com", "overcast.fm", "pca.st", "pocketcasts.com", "castro.fm":
            return .podcast
        case "books.apple.com":
            return path.contains("/audiobook/") ? .audiobook : .book
        case "audible.com", "audible.co.uk":
            return .audiobook
        case "goodreads.com", "bookshop.org":
            return path.contains("/book") ? .book : nil
        case "youtube.com", "youtu.be", "vimeo.com", "tiktok.com":
            return .video
        case "open.spotify.com":
            if path.hasPrefix("/episode") || path.hasPrefix("/show") { return .podcast }
            if path.hasPrefix("/audiobook") { return .audiobook }
            return .music
        default:
            return host.hasSuffix(".bandcamp.com") || host == "bandcamp.com" ? .music : nil
        }
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

    private static let genericTitles: Set<String> = ["", "reminder", "task", "event", "link", "idea", "music", "media", "shopping", "other", "note", "website"]

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
