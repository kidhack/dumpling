import Foundation
import OSLog

private let logger = Logger(subsystem: "com.kidhack.dumpling.ShareExtension", category: "ShareViewModel")

@MainActor
final class ShareViewModel: ObservableObject {

    @Published var isExtracting = true
    @Published var isSaving = false
    @Published var errorMessage: String? = nil

    @Published var extractedURL: String? = nil
    @Published var extractedText: String? = nil
    @Published var hasImage = false

    var previewText: String {
        extractedURL ?? extractedText ?? (hasImage ? "(image)" : "(nothing extracted)")
    }

    /// Returns true once the item is safely queued, whether or not the relay upload succeeded.
    func save(userNote: String?, quickTag: String?) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        var item = PendingItem(
            contentURL: extractedURL,
            contentText: extractedText,
            sourceApp: nil,
            userNote: userNote,
            quickTag: quickTag
        )

        if RelayClient.isConfigured, item.contentURL != nil || item.contentText != nil {
            do {
                try await RelayClient.upload(id: item.id, payload: item.relayPayload, timeout: 8)
                item.syncedAt = Date()
                logger.info("Relay upload succeeded for \(item.id, privacy: .public)")
            } catch {
                logger.error("Relay upload failed, app will retry: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            logger.info("Relay upload skipped (not configured or no URL/text)")
        }

        do {
            try AppGroup.enqueue(item)
            logger.info("Enqueue succeeded: url=\(item.contentURL ?? "nil", privacy: .public), note=\(userNote != nil), synced=\(item.syncedAt != nil)")
            return true
        } catch {
            logger.error("Enqueue failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't save item"
            return false
        }
    }
}
