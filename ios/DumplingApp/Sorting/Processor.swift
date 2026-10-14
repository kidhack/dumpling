import Foundation
import FoundationModels
import MapKit
import OSLog

private let logger = Logger(subsystem: "com.kidhack.dumpling", category: "Sorting")

/// Sorts pending items on-device and files them. Runs while the app is in the foreground.
@MainActor
enum Processor {

    /// How long a phone leaves someone else's new item for their phone to sort, before sorting it itself.
    static let ownerSortWindow: TimeInterval = 10 * 60

    /// Returns why the on-device model couldn't run, if that stopped processing early.
    /// `sortingNow` is sorted even if someone else added it (the user asked to sort it again).
    static func processPending(_ items: [Item], filer: Filer,
                               sortingNow: UUID? = nil) async -> SystemLanguageModel.Availability.UnavailableReason? {
        for item in items where item.status == "pending" {
            // On a shared list, only the phone that added an item sorts it, so two phones don't both do the
            // work; the result syncs over. If it's still unsorted after a while, any phone takes it.
            if item.id != sortingNow, let creator = item.createdByID, creator != Hearts.myID,
               Date.now.timeIntervalSince(item.timestamp) < ownerSortWindow {
                continue
            }
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
            if plan.category == .location {
                await locate(item, place: page?.place, near: recentCoordinate(in: items, excluding: item))
            }
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

    /// Gives a Location item map coordinates and, when it was missing, a full address.
    static func locate(_ item: Item, place: Place?, near: CLLocationCoordinate2D?) async {
        if let place, place.coordinate == nil || place.address == nil,
           let found = await Places.lookup(place, near: near) {
            item.location = item.location ?? found.address
            item.latitude = found.latitude
            item.longitude = found.longitude
        } else if let coordinate = place?.coordinate {
            item.latitude = coordinate.latitude
            item.longitude = coordinate.longitude
        } else if let address = item.location, let coordinate = await Places.geocode(address) {
            item.latitude = coordinate.latitude
            item.longitude = coordinate.longitude
        }
    }

    /// A map position for a saved place that doesn't have one, or only has a city's. Searches Apple Maps
    /// for the place's name with whatever address it has, reading its web page for an address first when
    /// it has none. Falls back to the address alone only when it's a street address.
    @MainActor
    static func findPlace(for item: Item, near: CLLocationCoordinate2D?) async -> Place? {
        let name = placeName(item.displayTitle)
        var address = item.location.flatMap { $0 == item.displayTitle || $0 == name ? nil : $0 }
        if address == nil, let url = item.contentURL.flatMap(URL.init(string:)), let page = await PageReader.fetch(url) {
            if let place = page.place, place.coordinate != nil { return place }
            address = page.address
        }
        if let found = await Places.lookup(Place(name: name, address: address), near: near) { return found }
        if let address, isStreetAddress(address), let coordinate = await Places.geocode(address) {
            return Place(name: name, address: address, latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        return nil
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

    /// "614 n. 2nd st, Philadelphia" is; "Philadelphia, PA" isn't (it would pin the city center).
    static func isStreetAddress(_ text: String) -> Bool {
        text.range(of: #"^\s*\d+[A-Za-z]?\s+\S"#, options: .regularExpression) != nil
    }

    /// Where the user's most recently shared place is, to disambiguate name-only lookups.
    private static func recentCoordinate(in items: [Item], excluding current: Item) -> CLLocationCoordinate2D? {
        items.filter { $0.id != current.id && $0.latitude != nil && $0.longitude != nil }
            .max { $0.timestamp < $1.timestamp }
            .map { CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!) }
    }

    /// Files an item the user edited, using its current fields. `target` files a link or idea as a
    /// reminder or event without changing its category.
    static func fileNow(_ item: Item, as target: ItemCategory? = nil, filer: Filer) async {
        let plan = Sorter.Plan(
            category: target ?? item.category.flatMap(ItemCategory.init(rawValue:)) ?? .other,
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
            case .location, .link, .idea, .music, .other:
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
