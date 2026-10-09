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
}

enum PageReader {

    static func fetch(_ url: URL, timeout: TimeInterval = 10) async -> PageInfo? {
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return parse(html: String(decoding: data.prefix(3_000_000), as: UTF8.self))
    }

    static func parse(html: String) -> PageInfo {
        PageInfo(
            title: meta("og:title", in: html) ?? meta("twitter:title", in: html) ?? titleTag(in: html),
            description: meta("og:description", in: html) ?? meta("description", in: html),
            event: jsonLDEvent(in: html) ?? embeddedEvent(in: html)
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
