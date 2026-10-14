import Foundation

/// A place's weekly hours, read from schema.org data on its web page.
struct OpeningHours: Codable, Sendable, Equatable {
    struct Span: Codable, Sendable, Equatable {
        /// 1 = Sunday ... 7 = Saturday, matching Calendar's weekday.
        var weekday: Int
        /// Minutes after midnight. `close` is less than `open` when the place stays open past midnight.
        var open: Int
        var close: Int
    }

    var spans: [Span]

    /// True, false, or nil when the hours say nothing about that day.
    func isOpen(at date: Date, calendar: Calendar = .current) -> Bool? {
        guard !spans.isEmpty else { return nil }
        let weekday = calendar.component(.weekday, from: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let yesterday = weekday == 1 ? 7 : weekday - 1
        for span in spans {
            let overnight = span.close <= span.open
            if span.weekday == weekday && minute >= span.open && (overnight || minute < span.close) { return true }
            // Still open from last night.
            if overnight && span.weekday == yesterday && minute < span.close { return true }
        }
        return false
    }

    /// When today's open span ends, for "Open until 10 PM".
    func closing(after date: Date, calendar: Calendar = .current) -> Date? {
        let weekday = calendar.component(.weekday, from: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let yesterday = weekday == 1 ? 7 : weekday - 1
        let midnight = calendar.startOfDay(for: date)
        for span in spans {
            let overnight = span.close <= span.open
            if span.weekday == weekday && minute >= span.open && (overnight || minute < span.close) {
                return calendar.date(byAdding: .minute, value: span.close + (overnight ? 24 * 60 : 0), to: midnight)
            }
            if overnight && span.weekday == yesterday && minute < span.close {
                return calendar.date(byAdding: .minute, value: span.close, to: midnight)
            }
        }
        return nil
    }

    /// "10 AM", or "10:30 AM" when there are minutes.
    static func clock(_ date: Date) -> String {
        Calendar.current.component(.minute, from: date) == 0
            ? date.formatted(.dateTime.hour()) : date.formatted(.dateTime.hour().minute())
    }

    /// One line per run of days with the same hours: "Tue–Sat 12 PM–10 PM".
    var summary: [String] {
        let symbols = Calendar.current.shortWeekdaySymbols
        func clock(_ minutes: Int) -> String {
            let date = Calendar.current.date(bySettingHour: minutes / 60 % 24, minute: minutes % 60, second: 0, of: .now) ?? .now
            return OpeningHours.clock(date)
        }
        // Monday-first, the way hours are usually listed.
        let order = [2, 3, 4, 5, 6, 7, 1]
        var lines: [String] = []
        var run: [Int] = []
        var runHours = ""
        func flush() {
            guard let first = run.first, let last = run.last else { return }
            let days = first == last ? symbols[first - 1] : "\(symbols[first - 1])–\(symbols[last - 1])"
            lines.append("\(days) \(runHours)")
        }
        for day in order {
            let hours = spans.filter { $0.weekday == day }
                .sorted { $0.open < $1.open }
                .map { "\(clock($0.open))–\(clock($0.close))" }
                .joined(separator: ", ")
            if !hours.isEmpty && hours == runHours {
                run.append(day)
            } else {
                flush()
                run = hours.isEmpty ? [] : [day]
                runHours = hours
            }
        }
        flush()
        return lines
    }

    // MARK: - schema.org

    /// From a business node's `openingHoursSpecification` or `openingHours`.
    static func from(schemaNode node: [String: Any]) -> OpeningHours? {
        var spans: [Span] = []
        let specs = (node["openingHoursSpecification"] as? [[String: Any]])
            ?? (node["openingHoursSpecification"] as? [String: Any]).map { [$0] } ?? []
        for spec in specs {
            guard let open = minutes(spec["opens"] as? String), let close = minutes(spec["closes"] as? String) else { continue }
            let days: [Any] = (spec["dayOfWeek"] as? [Any]) ?? [spec["dayOfWeek"] as Any]
            for day in days.compactMap({ ($0 as? String).flatMap(weekday(named:)) }) {
                // 00:00–00:00 is how some sites say "closed".
                if open == close && open == 0 { continue }
                spans.append(Span(weekday: day, open: open, close: close))
            }
        }
        if spans.isEmpty {
            let lines: [String] = (node["openingHours"] as? [String]) ?? (node["openingHours"] as? String).map { [$0] } ?? []
            // A later line replaces earlier hours for its days: "Tu-Su 10:00-17:00", "Th 10:00-21:00".
            for line in lines {
                let parsed = parseLine(line)
                let days = Set(parsed.map(\.weekday))
                spans.removeAll { days.contains($0.weekday) }
                spans += parsed
            }
        }
        return spans.isEmpty ? nil : OpeningHours(spans: spans)
    }

    /// "Mo-Fr 09:00-17:00", "Tu,Th 10:00-22:00", "Sa 12:00-02:00".
    static func parseLine(_ line: String) -> [Span] {
        var spans: [Span] = []
        for part in line.split(separator: ";") {
            let pieces = part.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            let days = expandDays(String(pieces[0]))
            for range in pieces[1].split(separator: ",") {
                let ends = range.split(separator: "-")
                guard ends.count == 2, let open = minutes(String(ends[0])), let close = minutes(String(ends[1])) else { continue }
                spans += days.map { Span(weekday: $0, open: open, close: close) }
            }
        }
        return spans
    }

    private static let twoLetter = ["Su": 1, "Mo": 2, "Tu": 3, "We": 4, "Th": 5, "Fr": 6, "Sa": 7]

    private static func expandDays(_ text: String) -> [Int] {
        var days: [Int] = []
        for group in text.split(separator: ",") {
            let ends = group.split(separator: "-").compactMap { twoLetter[String($0.prefix(2)).capitalized] }
            if ends.count == 2 {
                var day = ends[0]
                while true {
                    days.append(day)
                    if day == ends[1] { break }
                    day = day == 7 ? 1 : day + 1
                }
            } else if let day = ends.first {
                days.append(day)
            }
        }
        return days
    }

    /// "Monday", "https://schema.org/Monday" or "Mo".
    private static func weekday(named value: String) -> Int? {
        let name = value.split(separator: "/").last.map(String.init) ?? value
        return twoLetter[String(name.prefix(2)).capitalized]
    }

    /// "09:00", "9:00:00", "24:00".
    private static func minutes(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0...24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}
