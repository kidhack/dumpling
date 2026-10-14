// Runs the app's real Sorter and PageReader on this Mac's on-device model.
//   ./run.sh            built-in cases + page parser checks
//   ./run.sh <url>...   fetch and sort real links (don't commit private links as cases)
import Foundation
import FoundationModels
import MapKit

func check(_ name: String, _ ok: Bool) {
    print(ok ? "  ok  " : "  FAIL", name)
    if !ok { failures += 1 }
}
nonisolated(unsafe) var failures = 0

func parserChecks() {
    print("Page parser:")
    let jsonLD = """
        <html><head><meta property="og:title" content="Radiohead &amp; Friends">
        <script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"WebPage"},
        {"@type":"MusicEvent","name":"Radiohead","startDate":"2026-10-24T19:30:00-07:00","endDate":"2026-10-24T23:00:00-07:00",
        "location":{"@type":"Place","name":"Greek Theatre","address":{"addressLocality":"Berkeley","addressRegion":"CA"}}}]}</script>
        </head></html>
        """
    let a = PageReader.parse(html: jsonLD)
    check("og:title decoded", a.title == "Radiohead & Friends")
    check("JSON-LD event start", a.event?.start == ISO8601DateFormatter().date(from: "2026-10-25T02:30:00Z"))
    check("JSON-LD event end", a.event?.end != nil)
    check("JSON-LD venue", a.event?.location == "Greek Theatre, Berkeley, CA")
    check("JSON-LD timed", a.event?.allDay == false)

    let nextData = """
        <meta content="Fall party" property="og:title"><meta name="description" content="Come hang">
        <script id="__NEXT_DATA__">{"props":{"event":{"title":"Fall party","startDate":"2026-10-10T23:00:00.000Z"}}}</script>
        """
    let b = PageReader.parse(html: nextData)
    check("content-before-property meta", b.title == "Fall party")
    check("embedded startDate", b.event?.start == ISO8601DateFormatter().date(from: "2026-10-10T23:00:00Z"))
    check("description", b.description == "Come hang")

    let dateOnly = #"<script type="application/ld+json">{"@type":"Event","startDate":"2026-11-02"}</script>"#
    check("date-only event is all day", PageReader.parse(html: dateOnly).event?.allDay == true)
    check("no event on plain page", PageReader.parse(html: "<title>Blog post</title>").event == nil)

    let footer = "<html><body><h1>Sirene</h1><p>Dinner nightly</p><footer><p>3308 Grand Ave<br>Oakland, CA 94610</p><p>email info@example.com</p></footer><script>var x = '1 Fake St';</script></body></html>"
    check("address from visible text", PageReader.parse(html: footer).address?.hasPrefix("3308 Grand Ave") == true)
    let business = #"<script type="application/ld+json">{"@type":"Restaurant","name":"Sirene","address":{"@type":"PostalAddress","streetAddress":"3308 Grand Ave","addressLocality":"Oakland","addressRegion":"CA"}}</script>"#
    check("address from schema.org business", PageReader.parse(html: business).address == "3308 Grand Ave, Oakland, CA")
    check("no address on plain page", PageReader.parse(html: "<p>Just a blog post</p>").address == nil)

    // Opening hours. Dates below are in 2026: Oct 13 is a Tuesday.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    let spec = #"<script type="application/ld+json">{"@type":"BarOrPub","openingHoursSpecification":[{"@type":"OpeningHoursSpecification","dayOfWeek":["https://schema.org/Tuesday","https://schema.org/Wednesday"],"opens":"17:00","closes":"02:00"},{"dayOfWeek":"Saturday","opens":"12:00:00","closes":"23:00:00"}]}</script>"#
    let bar = PageReader.parse(html: spec).hours
    check("hours from openingHoursSpecification", bar?.spans.count == 3)
    check("bar open Tuesday 9 PM", bar?.isOpen(at: at(13, 21), calendar: cal) == true)
    check("bar open after midnight into Wednesday", bar?.isOpen(at: at(14, 1, 30), calendar: cal) == true)
    check("bar closed Wednesday 3 AM", bar?.isOpen(at: at(14, 3), calendar: cal) == false)
    check("bar closed Monday night", bar?.isOpen(at: at(12, 21), calendar: cal) == false)
    check("bar closes 2 AM", bar?.closing(after: at(13, 21), calendar: cal) == at(14, 2))
    check("bar closed Sunday 1 AM (Saturday isn't overnight)", bar?.isOpen(at: at(18, 1), calendar: cal) == false)

    let line = #"<script type="application/ld+json">{"@type":"Museum","openingHours":["Tu-Su 10:00-17:00","Th 10:00-21:00"]}</script>"#
    let gallery = PageReader.parse(html: line).hours
    check("hours from openingHours text", gallery != nil)
    check("gallery closed Monday", gallery?.isOpen(at: at(12, 12), calendar: cal) == false)
    check("gallery open Sunday noon", gallery?.isOpen(at: at(18, 12), calendar: cal) == true)
    check("gallery open Thursday 8 PM", gallery?.isOpen(at: at(15, 20), calendar: cal) == true)
    check("gallery closed Friday 8 PM", gallery?.isOpen(at: at(16, 20), calendar: cal) == false)
    check("no hours on plain page", PageReader.parse(html: business).hours == nil)
    print("  summary:", gallery?.summary ?? [], bar?.summary ?? [])

    // Venue websites.
    let restaurantLD = #"<title>Sirene</title><script type="application/ld+json">{"@type":"Restaurant","name":"Sirene"}</script>"#
    check("schema.org Restaurant is a venue", PageReader.parse(html: restaurantLD).looksLikeVenue)
    let barWords = "<title>Bar Hygge | Brewpub</title><footer><p>1720 Fairmount Ave<br>Philadelphia, PA 19130</p></footer>"
    check("bar title with an address is a venue", PageReader.parse(html: barWords).looksLikeVenue)
    let saas = "<title>DashOne — Smart Dashboards for Your Home</title><meta name=\"description\" content=\"Marketing made easy on the App Store\"><footer><p>500 Market St<br>San Francisco, CA 94105</p></footer>"
    check("company site with an office address isn't a venue", !PageReader.parse(html: saas).looksLikeVenue)
    let small = "<title>Sirene</title><body><p>Reserve your table here!</p><p>DINNER MENU / WINE LIST</p><footer><p>3308 Grand Ave<br>Oakland, CA</p></footer></body>"
    check("small restaurant site with no metadata is a venue", PageReader.parse(html: small).looksLikeVenue)
    let navMenu = "<title>Acme</title><body><nav>Menu</nav><p>We build software. Lunch and learn every Friday.</p><footer><p>500 Market St<br>San Francisco, CA 94105</p></footer></body>"
    check("one food word and a nav menu isn't a venue", !PageReader.parse(html: navMenu).looksLikeVenue)
    check("restaurant words without an address aren't enough", !PageReader.parse(html: "<title>10 best restaurant recipes</title>").looksLikeVenue)
}

func show(_ item: Item, page: PageInfo?) async {
    let started = Date()
    do {
        let decision = try await Sorter.sort(prompt: Sorter.describe(item, page: page), quickTag: item.quickTag)
        let plan = Sorter.plan(decision, item: item, page: page)
        let when = plan.start.map { plan.allDay ? $0.formatted(date: .complete, time: .omitted) + " (all day)"
                                                : $0.formatted(date: .complete, time: .shortened) } ?? "-"
        print(String(format: "%.1fs", Date().timeIntervalSince(started)), "|", item.contentURL ?? item.contentText ?? "",
              "\n   page:", page?.title ?? "-", page?.event != nil ? "(has event data)" : "",
              "\n   →", plan.category, plan.mediaKind.map { "(\($0.rawValue))" } ?? "", "|", plan.title, "|", when, "| loc:", plan.location ?? "-")
    } catch {
        print("ERROR", item.contentURL ?? item.contentText ?? "", error)
    }
}

let urls = Array(CommandLine.arguments.dropFirst())
if urls.isEmpty { parserChecks() }

switch SystemLanguageModel.default.availability {
case .available: print("\nModel: available")
case .unavailable(let reason): print("\nModel unavailable: \(reason)"); exit(failures == 0 ? 0 : 1)
}

if urls.isEmpty {
    let cases: [Item] = [
        Item(url: "https://www.apple.com/iphone-duo/", note: "Duo is cool", tag: "link_save"),
        Item(url: "https://www.apple.com/", tag: "reminder"),
        Item(text: "Garden tour this Saturday 10am at Filoli, tickets $35", note: "go with Sam"),
        Item(url: "https://github.com/yonaskolb/XcodeGen"),
        Item(text: "Call the dentist to reschedule before Friday"),
        Item(url: "https://www.eventbrite.com/e/radiohead-at-the-greek-oct-24"),
        Item(text: "Tartine Bakery, 600 Guerrero St, San Francisco", note: "best morning bun"),
        Item(url: "https://maps.apple.com/?q=Blue+Bottle+Coffee&address=66+Mint+St,+San+Francisco"),
        Item(text: "Try the ramen place on Valencia next time we're in the Mission"),
    ]
    for item in cases { await show(item, page: nil) }
} else {
    for url in urls {
        let page = await PageReader.fetch(URL(string: url)!)
        print("   page address:", page?.address ?? "-")
        if let place = page?.place {
            print("   maps link:", place.name, "|", place.address ?? "-")
            // Bias toward Philadelphia, as the app would after the user's recent Philly shares.
            let philly = CLLocationCoordinate2D(latitude: 39.9526, longitude: -75.1652)
            if let found = await Places.lookup(place, near: philly) {
                print("   Apple Maps:", found.name, "|", found.address ?? "-", "|", found.latitude ?? 0, found.longitude ?? 0)
            } else {
                print("   Apple Maps: no match")
            }
        }
        await show(Item(url: url, tag: nil), page: page)
        await show(Item(url: url, tag: "location"), page: page)
    }
}
exit(failures == 0 ? 0 : 1)
