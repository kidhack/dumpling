// Sample items for ios/Tools/SortCheck/run.sh. Add cases here when tuning the sorter.
import Foundation
import FoundationModels

let cases: [Item] = [
    Item(url: "https://www.apple.com/iphone-duo/", note: "Duo is cool", tag: "link_save"),
    Item(url: "https://www.apple.com/", tag: "reminder"),
    Item(text: "Garden tour this Saturday 10am at Filoli, tickets $35", note: "go with Sam"),
    Item(url: "https://github.com/yonaskolb/XcodeGen"),
    Item(text: "Call the dentist to reschedule before Friday"),
    Item(url: "https://www.eventbrite.com/e/radiohead-at-the-greek-oct-24"),
]
switch SystemLanguageModel.default.availability {
case .available: print("model: available")
case .unavailable(let r): print("model: unavailable \(r)"); exit(0)
}
for item in cases {
    let started = Date()
    do {
        let d = try await Sorter.sort(prompt: Sorter.describe(item), quickTag: item.quickTag)
        let r = Sorter.resolveDate(Sorter.grounded(d.datePhrase, in: Sorter.sharedText(of: item)))
        let parsed = r.map { $0.allDay ? $0.date.formatted(date: .complete, time: .omitted) + " (all day)" : $0.date.formatted(date: .complete, time: .shortened) } ?? "-"
        print(String(format: "%.1fs", Date().timeIntervalSince(started)), "|", item.contentURL ?? item.contentText!, "\n   →", d.category, "|", Sorter.cleanTitle(d.title, for: item), "| phrase:", d.datePhrase ?? "nil", "→", parsed, "| loc:", d.location ?? "-")
    } catch {
        print("ERROR", item.contentURL ?? item.contentText!, error)
    }
}
