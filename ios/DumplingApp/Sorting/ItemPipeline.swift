import CoreLocation
import Foundation
import FoundationModels
import Observation
import OSLog
import CoreData

private let logger = Logger(subsystem: "com.kidhack.dumpling", category: "Pipeline")

/// Imports shared items, sorts and files them, and uploads to the relay if configured.
/// One instance for the whole app so tabs never run it twice at once.
@MainActor
@Observable
final class ItemPipeline {
    let filer = Filer()
    private(set) var modelUnavailable: SystemLanguageModel.Availability.UnavailableReason?
    private var isRunning = false

    func refresh(_ context: NSManagedObjectContext) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        importQueue(into: context)
        let items = Item.all(in: context)
        resortMapLinksOnce(items)
        modelUnavailable = await Processor.processPending(items, filer: filer)
        try? context.save()
        await completeAddressesOnce(items)
        try? context.save()
        await upload(items)
        try? context.save()
    }

    /// Places saved with a street but no city ("1206 Frankford avenue"), or just their name, were placed by
    /// guessing which street was meant; and a place far from everything else in its list (Post Haste, in a
    /// Philadelphia list, matched a street in Indiana) was placed by a bad match. Look these up once by name near
    /// the others, keeping the full address. Places in lists shared view-only are left alone.
    private func completeAddressesOnce(_ items: [Item]) async {
        let key = "completedCitylessAddresses.v2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for item in items where item.category == "location" {
            guard item.list.map(Sharing.canEdit) ?? true else { continue }
            let cityless = !(item.location.map(Places.hasCity) ?? false)
            let neighbors = Self.listNeighbors(of: item)
            let outlier = Self.isFar(item, from: neighbors)
            guard cityless || outlier else { continue }
            let near = Self.center(of: neighbors) ?? Processor.recentCoordinate(in: items, excluding: item)
            let old = (item.latitude, item.longitude, item.location)
            item.latitude = nil
            item.longitude = nil
            // An outlier's address came from the bad match too.
            if outlier { item.location = nil }
            await Processor.locate(item, place: nil, near: near)
            if item.latitude == nil, let place = await Processor.findPlace(for: item, near: near),
               let coordinate = place.coordinate {
                item.latitude = coordinate.latitude
                item.longitude = coordinate.longitude
                if let full = place.address { item.location = full }
            }
            // Found nothing better: keep what it had.
            if item.latitude == nil { (item.latitude, item.longitude, item.location) = old }
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    private static func listNeighbors(of item: Item) -> [CLLocation] {
        (item.list?.itemsArray ?? []).compactMap { other in
            guard other.id != item.id, let latitude = other.latitude, let longitude = other.longitude else { return nil }
            return CLLocation(latitude: latitude, longitude: longitude)
        }
    }

    /// More than 300 km from every other place in its list (with at least two others to go by).
    private static func isFar(_ item: Item, from neighbors: [CLLocation]) -> Bool {
        guard neighbors.count >= 2, let latitude = item.latitude, let longitude = item.longitude else { return false }
        let here = CLLocation(latitude: latitude, longitude: longitude)
        return neighbors.allSatisfy { $0.distance(from: here) > 300_000 }
    }

    private static func center(of places: [CLLocation]) -> CLLocationCoordinate2D? {
        guard !places.isEmpty else { return nil }
        let latitude = places.map(\.coordinate.latitude).reduce(0, +) / Double(places.count)
        let longitude = places.map(\.coordinate.longitude).reduce(0, +) / Double(places.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Map share links sorted before they could be read came out as "Google Search"; sort those again once.
    private func resortMapLinksOnce(_ items: [Item]) {
        let key = "resortedMapLinks.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for item in items where !item.isFiled {
            guard let host = item.contentURL.flatMap(URL.init(string:))?.host()?.lowercased(),
                  ["share.google", "maps.app.goo.gl", "goo.gl", "maps.google.com", "maps.apple.com"].contains(host)
                    || host.hasSuffix("google.com")
            else { continue }
            item.status = "pending"
            item.title = nil
            item.location = nil
            item.sortError = nil
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    private func importQueue(into context: NSManagedObjectContext) {
        let pending = AppGroup.dequeueAll()
        for p in pending {
            let item = Item(context: context, id: p.id, contentURL: p.contentURL, contentText: p.contentText,
                            sourceApp: p.sourceApp, userNote: p.userNote, quickTag: p.quickTag)
            item.timestamp = p.timestamp
            item.syncedAt = p.syncedAt
            Persistence.shared.assignToPrivateStore(item)
        }
        if !pending.isEmpty { try? context.save() }
    }

    private func upload(_ items: [Item]) async {
        guard RelayClient.isConfigured else { return }
        for item in items where item.syncedAt == nil && item.isUploadable {
            do {
                try await RelayClient.upload(id: item.id, payload: item.relayPayload)
                item.syncedAt = Date()
            } catch {
                logger.error("Upload failed for \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                break
            }
        }
    }
}
