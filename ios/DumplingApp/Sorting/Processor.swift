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

            var page: PageInfo?
            if let url = item.contentURL.flatMap(URL.init(string:)) {
                page = await PageReader.fetch(url)
            }

            let decision: SortDecision
            do {
                decision = try await Sorter.sort(prompt: Sorter.describe(item, page: page), quickTag: item.quickTag)
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

            let plan = Sorter.plan(decision, item: item, page: page)
            record(plan, on: item, pageEvent: page?.event != nil)
            await file(item, plan: plan, filer: filer)
        }
        return nil
    }

    private static func record(_ plan: Sorter.Plan, on item: Item, pageEvent: Bool) {
        item.category = plan.category.rawValue
        item.title = plan.title
        item.relevantDate = plan.start
        item.isAllDay = plan.allDay
        item.location = plan.location
        item.sortError = nil
        logger.info("Sorted \(item.id, privacy: .public) as \(plan.category.rawValue, privacy: .public), start=\(plan.start?.description ?? "none", privacy: .public), fromPageData=\(pageEvent)")
    }

    /// Files an item the user edited, using its current fields.
    static func fileNow(_ item: Item, filer: Filer) async {
        let plan = Sorter.Plan(
            category: item.category.flatMap(ItemCategory.init(rawValue:)) ?? .other,
            title: item.displayTitle, start: item.relevantDate, end: nil,
            allDay: item.isAllDay, location: item.location
        )
        item.sortError = nil
        await file(item, plan: plan, filer: filer)
    }

    private static func file(_ item: Item, plan: Sorter.Plan, filer: Filer) async {
        let notes = [item.contentURL, item.userNote, item.contentText].compactMap { $0 }.joined(separator: "\n")
        let url = item.contentURL.flatMap(URL.init(string:))

        do {
            let result: Filer.Result
            switch plan.category {
            case .event:
                guard let start = plan.start else {
                    item.status = "kept"
                    item.sortError = "Looks like an event, but no date was found."
                    return
                }
                result = try await filer.fileEvent(title: plan.title, notes: notes, url: url, start: start,
                                                   end: plan.end, allDay: plan.allDay, location: plan.location)
            case .task:
                result = try await filer.fileReminder(title: plan.title, notes: notes, url: url,
                                                      due: plan.start, allDay: plan.allDay)
            case .link, .idea, .music, .other:
                item.status = "kept"
                return
            }
            item.status = "filed"
            item.filedTo = result.alreadyExisted ? "Already in \(result.place)" : result.place
            item.eventKitID = result.id
            item.archivedAt = nil
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
