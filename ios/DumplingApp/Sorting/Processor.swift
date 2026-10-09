import Foundation
import FoundationModels
import OSLog

private let logger = Logger(subsystem: "com.kidhack.dumpling", category: "Sorting")

/// Sorts pending items on-device and files them. Runs while the app is in the foreground.
@MainActor
enum Processor {

    /// Returns why the on-device model couldn't run, if that stopped processing early.
    static func processPending(_ items: [Item], filer: Filer) async -> SystemLanguageModel.Availability.UnavailableReason? {
        for item in items where item.status == "pending" {
            guard item.contentURL != nil || item.contentText != nil else {
                item.status = "kept"
                item.sortError = "Images can't be sorted yet."
                continue
            }

            let decision: SortDecision
            do {
                decision = try await Sorter.sort(prompt: Sorter.describe(item), quickTag: item.quickTag)
            } catch Sorter.Unavailable.model(let reason) {
                return reason
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .rateLimited, .assetsUnavailable:
                    logger.info("Model busy or not ready, retrying later: \(error.localizedDescription, privacy: .public)")
                    return nil
                default:
                    keep(item, because: error)
                    continue
                }
            } catch {
                keep(item, because: error)
                continue
            }

            let allDay = apply(decision, to: item)
            await file(item, decision: decision, allDay: allDay, filer: filer)
        }
        return nil
    }

    /// Records the decision on the item. Returns whether the resolved date is all-day.
    @discardableResult
    static func apply(_ decision: SortDecision, to item: Item) -> Bool {
        let resolved = Sorter.resolveDate(Sorter.grounded(decision.datePhrase, in: Sorter.sharedText(of: item)))
        item.category = decision.category.rawValue
        item.title = Sorter.cleanTitle(decision.title, for: item)
        item.relevantDate = resolved?.date
        item.sortError = nil
        logger.info("Sorted \(item.id, privacy: .public) as \(decision.category.rawValue, privacy: .public), datePhrase=\(decision.datePhrase ?? "none", privacy: .public)")
        return resolved?.allDay ?? true
    }

    private static func file(_ item: Item, decision: SortDecision, allDay: Bool, filer: Filer) async {
        let notes = [item.contentURL, item.userNote, item.contentText].compactMap { $0 }.joined(separator: "\n")
        let url = item.contentURL.flatMap(URL.init(string:))
        let title = item.title ?? decision.title

        do {
            let result: (place: String, id: String)
            switch decision.category {
            case .event:
                guard let start = item.relevantDate else {
                    item.status = "kept"
                    item.sortError = "Looks like an event, but no date was found."
                    return
                }
                result = try await filer.fileEvent(title: title, notes: notes, url: url, start: start,
                                                   allDay: allDay, location: decision.location)
            case .task:
                result = try await filer.fileReminder(title: title, notes: notes, url: url,
                                                      due: item.relevantDate, allDay: allDay)
            case .link, .idea, .music, .other:
                item.status = "kept"
                return
            }
            item.status = "filed"
            item.filedTo = result.place
            item.eventKitID = result.id
        } catch {
            logger.error("Filing failed for \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            item.status = "failed"
            item.sortError = error.localizedDescription
        }
    }

    private static func keep(_ item: Item, because error: Error) {
        logger.error("Couldn't sort \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        item.status = "kept"
        item.category = ItemCategory.other.rawValue
        item.sortError = error.localizedDescription
    }
}
