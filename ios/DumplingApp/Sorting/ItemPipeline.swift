import Foundation
import FoundationModels
import Observation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.kidhack.dumpling", category: "Pipeline")

/// Imports shared items, sorts and files them, and uploads to the relay if configured.
/// One instance for the whole app so tabs never run it twice at once.
@MainActor
@Observable
final class ItemPipeline {
    let filer = Filer()
    private(set) var modelUnavailable: SystemLanguageModel.Availability.UnavailableReason?
    private var isRunning = false

    func refresh(_ context: ModelContext) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        importQueue(into: context)
        let items = (try? context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        resortMapLinksOnce(items)
        modelUnavailable = await Processor.processPending(items, filer: filer)
        try? context.save()
        await upload(items)
        try? context.save()
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

    private func importQueue(into context: ModelContext) {
        let pending = AppGroup.dequeueAll()
        for p in pending {
            let item = Item(id: p.id, contentURL: p.contentURL, contentText: p.contentText,
                            sourceApp: p.sourceApp, userNote: p.userNote, quickTag: p.quickTag)
            item.timestamp = p.timestamp
            item.syncedAt = p.syncedAt
            context.insert(item)
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
