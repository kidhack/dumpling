import Foundation
import OSLog

private let logger = Logger(subsystem: "com.kidhack.dumpling.ShareExtension", category: "ShareViewModel")

// Mirrors PendingItem in DumplingApp/Shared/AppGroup.swift — keep the two in sync.
private struct PendingItem: Codable {
    var contentURL: String?
    var contentText: String?
    var sourceApp: String?
    var userNote: String?
    var quickTag: String?
    var timestamp: Date = Date()
}

@MainActor
final class ShareViewModel: ObservableObject {

    @Published var isExtracting = true
    @Published var isLoading = false
    @Published var result: UploadResult? = nil

    @Published var extractedURL: String? = nil
    @Published var extractedText: String? = nil
    @Published var hasImage = false

    enum UploadResult {
        case success(String)
        case failure(String)
    }

    var previewText: String {
        extractedURL ?? extractedText ?? (hasImage ? "(image)" : "(nothing extracted)")
    }

    func submit(userNote: String?, quickTag: String?) {
        isLoading = true
        defer { isLoading = false }

        let item = PendingItem(
            contentURL: extractedURL,
            contentText: extractedText,
            sourceApp: nil,
            userNote: userNote,
            quickTag: quickTag
        )

        guard let defaults = UserDefaults(suiteName: "group.com.kidhack.dumpling") else {
            logger.error("Enqueue failed: App Group suite unavailable")
            result = .failure("App Group not configured")
            return
        }

        var queue: [PendingItem] = []
        if let data = defaults.data(forKey: "pending_items"),
           let existing = try? JSONDecoder().decode([PendingItem].self, from: data) {
            queue = existing
        }
        queue.append(item)

        do {
            defaults.set(try JSONEncoder().encode(queue), forKey: "pending_items")
            logger.info("Enqueue succeeded: queue size \(queue.count), url=\(self.extractedURL ?? "nil", privacy: .public), note=\(userNote != nil)")
            result = .success("Dumpling'd! 🥟")
        } catch {
            logger.error("Enqueue failed: \(error.localizedDescription, privacy: .public)")
            result = .failure("Couldn't save item")
        }
    }
}
