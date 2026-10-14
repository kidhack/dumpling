import Foundation

/// Reads a shared page's own metadata so sorting isn't limited to the URL text.
/// Structured event data is trusted over the model; titles and descriptions are model context.
struct PageInfo: Sendable, Equatable {
    struct Event: Sendable, Equatable {
        var name: String?
        var start: Date
        var end: Date?
        var allDay: Bool
        var location: String?
    }

    var title: String?
    var description: String?
    var event: Event?
    /// A street address from structured business data or the page's visible text.
    var address: String?
    /// A place named by a maps share link (Google or Apple), read from the redirected URL.
    var place: Place?
    /// Weekly hours from structured business data.
    var hours: OpeningHours?
    /// The page's structured data says it's a place you go (a restaurant, bar, shop, museum...).
    var isVenue = false
    /// The page's visible text talks like a restaurant or bar (two or more of `venueTextWords`).
    var textReadsLikeVenue = false

    /// A venue's own website: structured data says so, or it prints a street address and its title or
    /// description reads like one. Restaurant sites otherwise often came out as ideas or links.
    var looksLikeVenue: Bool {
        if isVenue { return true }
        guard address != nil else { return false }
        if textReadsLikeVenue { return true }
        let text = [title, description].compactMap { $0 }.joined(separator: " ").lowercased()
        return Self.venueWords.contains { text.contains($0) }
    }

    /// Words a restaurant's or bar's own page uses, for small sites with no description or structured data
    /// (Sirene's says "Reserve your table", "dinner menu / wine list"). Not "menu": every site has a nav menu.
    static let venueTextWords = ["restaurant", "reservation", "reserve a table", "reserve your table", "dinner",
                                 "lunch", "brunch", "happy hour", "wine list", "cocktail", "takeout", "dine in",
                                 "private events", "bakery", "brewery", "taproom"]

    /// Food, drink and culture words. Not "shop", "store" or "market": they show up on plenty of company
    /// sites ("App Store", "marketing") that also print an office address.
    static let venueWords = ["restaurant", "café", "cafe", "coffee", "bakery", "bar ", " bar", "pub", "brewery",
                             "wine", "cocktail", "menu", "reservation", "dining", "kitchen", "eatery", "bistro",
                             "trattoria", "taqueria", "pizzeria", "izakaya", "museum", "gallery", "hotel"]
}

enum PageReader {

    static func fetch(_ url: URL, timeout: TimeInterval = 10) async -> PageInfo? {
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else {
            // Some map links don't load without a browser, but the link itself still names the place.
            return Places.fromMapsLink(url).map { PageInfo(title: $0.name, place: $0) }
        }
        // Map share links redirect to a URL that names the place; the page itself is a search or map app shell.
        if let place = Places.fromMapsLink(response.url ?? url) ?? Places.fromMapsLink(url) {
            return PageInfo(title: place.name, place: place)
        }
        return parse(html: String(decoding: data.prefix(3_000_000), as: UTF8.self))
    }

    static func parse(html: String) -> PageInfo {
        PageInfo(
            title: meta("og:title", in: html) ?? meta("twitter:title", in: html) ?? titleTag(in: html),
            description: meta("og:description", in: html) ?? meta("description", in: html),
            event: jsonLDEvent(in: html) ?? embeddedEvent(in: html),
            address: jsonLDAddress(in: html) ?? textAddress(in: html),
            hours: jsonLDHours(in: html),
            isVenue: jsonLDIsVenue(in: html),
            textReadsLikeVenue: readsLikeVenue(visibleText(in: html))
        )
    }

    // MARK: - Meta tags

    private static func meta(_ key: String, in html: String) -> String? {
        let k = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            #"<meta[^>]+(?:property|name)=["']\#(k)["'][^>]*content=["']([^"']*)["']"#,
            #"<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']\#(k)["']"#,
        ]
        for pattern in patterns {
            if let value = firstCapture(pattern, in: html) { return cleaned(value) }
        }
        return nil
    }

    private static func titleTag(in html: String) -> String? {
        firstCapture(#"<title[^>]*>(.*?)</title>"#, in: html).flatMap(cleaned)
    }

    // MARK: - schema.org Event (JSON-LD)

    private static func jsonLDEvent(in html: String) -> PageInfo.Event? {
        for block in allCaptures(#"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#, in: html) {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            for node in flatten(json) {
                guard isEvent(node["@type"]),
                      let startString = node["startDate"] as? String,
                      let start = parseISO(startString) else { continue }
                return PageInfo.Event(
                    name: (node["name"] as? String).flatMap(cleaned),
                    start: start.date,
                    end: (node["endDate"] as? String).flatMap(parseISO)?.date,
                    allDay: start.dateOnly,
                    location: locationName(node["location"])
                )
            }
        }
        return nil
    }

    // MARK: - Addresses

    /// The first schema.org node with an address (Restaurant, LocalBusiness, Place, Organization...).
    private static func jsonLDAddress(in html: String) -> String? {
        for block in allCaptures(#"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#, in: html) {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            for node in flatten(json) {
                if let address = postalAddress(node["address"]) { return address }
            }
        }
        return nil
    }

    /// schema.org types for places people go. Most businesses use LocalBusiness or a subtype of it.
    private static let venueTypes: Set<String> = [
        "localbusiness", "foodestablishment", "restaurant", "barorpub", "cafeorcoffeeshop", "bakery", "brewery",
        "winery", "distillery", "fastfoodrestaurant", "icecreamshop", "nightclub", "store", "museum",
        "artgallery", "touristattraction", "lodgingbusiness", "hotel", "park", "zoo", "aquarium",
        "movietheater", "musicvenue", "performingartstheater", "entertainmentbusiness",
    ]

    private static func jsonLDIsVenue(in html: String) -> Bool {
        for block in allCaptures(#"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#, in: html) {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            for node in flatten(json) {
                let types = (node["@type"] as? [String]) ?? (node["@type"] as? String).map { [$0] } ?? []
                if types.contains(where: { venueTypes.contains($0.lowercased()) }) { return true }
            }
        }
        return false
    }

    private static func jsonLDHours(in html: String) -> OpeningHours? {
        for block in allCaptures(#"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#, in: html) {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            for node in flatten(json) {
                if let hours = OpeningHours.from(schemaNode: node) { return hours }
            }
        }
        return nil
    }

    private static func postalAddress(_ value: Any?) -> String? {
        if let s = value as? String { return cleaned(s) }
        if let array = value as? [Any] { return array.lazy.compactMap(postalAddress).first }
        guard let a = value as? [String: Any] else { return nil }
        let parts = ["streetAddress", "addressLocality", "addressRegion", "postalCode"].compactMap { (a[$0] as? String).flatMap(cleaned) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Small business sites often only print their address in the footer.
    /// The page's text without its code or markup, one block per line, trimmed to the first 40,000 characters.
    private static func visibleText(in html: String) -> String {
        let withoutCode = html.replacingOccurrences(of: #"<(script|style|noscript)[^>]*>.*?</\1>"#, with: " ",
                                                    options: [.regularExpression, .caseInsensitive])
        let text = decodeEntities(withoutCode.replacingOccurrences(of: #"<[^>]+>"#, with: "\n", options: .regularExpression))
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\n\s*"#, with: "\n", options: .regularExpression)
        return String(text.prefix(40_000))
    }

    private static func readsLikeVenue(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return PageInfo.venueTextWords.filter { lowered.contains($0) }.count >= 2
    }

    private static func textAddress(in html: String) -> String? {
        let sample = visibleText(in: html)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue),
              let match = detector.firstMatch(in: sample, range: NSRange(sample.startIndex..., in: sample)),
              let range = Range(match.range, in: sample)
        else { return nil }
        return cleaned(sample[range].replacingOccurrences(of: "\n", with: ", "))
    }

    private static func flatten(_ json: Any) -> [[String: Any]] {
        if let array = json as? [Any] { return array.flatMap(flatten) }
        guard let dict = json as? [String: Any] else { return [] }
        return [dict] + ((dict["@graph"] as? [Any]).map(flatten) ?? [])
    }

    private static func isEvent(_ type: Any?) -> Bool {
        let types = (type as? [String]) ?? [(type as? String) ?? ""]
        return types.contains { $0 == "Event" || $0.hasSuffix("Event") }
    }

    private static func locationName(_ value: Any?) -> String? {
        if let s = value as? String { return cleaned(s) }
        if let array = value as? [Any] { return array.lazy.compactMap(locationName).first }
        guard let place = value as? [String: Any] else { return nil }
        let name = (place["name"] as? String).flatMap(cleaned)
        let address: String? = {
            if let s = place["address"] as? String { return cleaned(s) }
            guard let a = place["address"] as? [String: Any] else { return nil }
            let parts = ["streetAddress", "addressLocality", "addressRegion"].compactMap { a[$0] as? String }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }()
        let joined = [name, address].compactMap { $0 }.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    // MARK: - Embedded app data (e.g. Partiful's __NEXT_DATA__)

    private static func embeddedEvent(in html: String) -> PageInfo.Event? {
        guard let startString = firstCapture(#""startDate"\s*:\s*"([0-9]{4}-[0-9]{2}-[0-9]{2}[^"]*)""#, in: html),
              let start = parseISO(startString) else { return nil }
        let end = firstCapture(#""endDate"\s*:\s*"([0-9]{4}-[0-9]{2}-[0-9]{2}[^"]*)""#, in: html).flatMap(parseISO)
        return PageInfo.Event(name: nil, start: start.date, end: end?.date, allDay: start.dateOnly, location: nil)
    }

    // MARK: - Helpers

    /// Parses ISO 8601 with or without fractional seconds or a time. Date-only values are local all-day dates.
    static func parseISO(_ value: String) -> (date: Date, dateOnly: Bool)? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: value) { return (d, false) }
        full.formatOptions = [.withInternetDateTime]
        if let d = full.date(from: value) { return (d, false) }

        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = local.date(from: String(value.prefix(19))) { return (d, false) }
        local.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let d = local.date(from: String(value.prefix(16))) { return (d, false) }
        local.dateFormat = "yyyy-MM-dd"
        if value.count == 10, let d = local.date(from: value) { return (d, true) }
        return nil
    }

    private static func cleaned(_ value: String) -> String? {
        let decoded = decodeEntities(value)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        for (entity, char) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        allCaptures(pattern, in: text, limit: 1).first
    }

    private static func allCaptures(_ pattern: String, in text: String, limit: Int = .max) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        var results: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard results.count < limit,
                  let range = Range(match.range(at: 1), in: text) else { continue }
            results.append(String(text[range]))
        }
        return results
    }
}
