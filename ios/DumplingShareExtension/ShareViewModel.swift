import Foundation

// Mirrors AppGroup.PendingItem — must stay in sync with the main app's definition.
private struct PendingItem: Codable {
    var contentURL: String?
    var contentText: String?
    var sourceApp: String?
    var userNote: String?
    var quickTag: String?
    var timestamp: Date = Date()
}

/// Manages state for the share sheet UI.
/// Phase 1: saves extracted payload to App Group queue for the main app to import.
@MainActor
class ShareViewModel: ObservableObject {

    @Published var isLoading = false
    @Published var result: UploadResult? = nil

    enum UploadResult {
        case success(String)
        case failure(String)
    }

    func submit(
        text: String?,
        url: String?,
        imageData: Data?,
        sourceApp: String?,
        userNote: String?,
        quickTag: String?
    ) async {
        isLoading = true
        defer { isLoading = false }

        let item = PendingItem(
            contentURL: url,
            contentText: text,
            sourceApp: sourceApp,
            userNote: userNote,
            quickTag: quickTag
        )

        if let defaults = UserDefaults(suiteName: "group.com.kidhack.dumpling") {
            var queue: [PendingItem] = []
            if let data = defaults.data(forKey: "pending_items"),
               let existing = try? JSONDecoder().decode([PendingItem].self, from: data) {
                queue = existing
            }
            queue.append(item)
            if let encoded = try? JSONEncoder().encode(queue) {
                defaults.set(encoded, forKey: "pending_items")
            }
            result = .success("Dumpling'd! 🥟")
        } else {
            result = .failure("App Group not configured")
        }
    }
}
