import Foundation

/// UserDefaults suite shared by the app and the share extension.
enum AppGroup {
    static let suiteName = "group.com.kidhack.dumpling"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Settings (written by the app, read by both)

    static var relayURL: String {
        get { defaults.string(forKey: "relay_url") ?? "" }
        set { defaults.set(newValue, forKey: "relay_url") }
    }

    static var authToken: String {
        get { defaults.string(forKey: "auth_token") ?? "" }
        set { defaults.set(newValue, forKey: "auth_token") }
    }

    // MARK: - Pending queue (written by the extension, drained by the app)

    private static let queueKey = "pending_items"

    static func enqueue(_ item: PendingItem) throws {
        var queue = pendingItems()
        queue.append(item)
        defaults.set(try JSONEncoder().encode(queue), forKey: queueKey)
    }

    static func dequeueAll() -> [PendingItem] {
        let items = pendingItems()
        defaults.removeObject(forKey: queueKey)
        return items
    }

    private static func pendingItems() -> [PendingItem] {
        guard let data = defaults.data(forKey: queueKey),
              let items = try? JSONDecoder().decode([PendingItem].self, from: data)
        else { return [] }
        return items
    }
}

/// An item handed from the share extension to the app.
struct PendingItem: Codable, Sendable {
    var id = UUID()
    var contentURL: String?
    var contentText: String?
    var sourceApp: String?
    var userNote: String?
    var quickTag: String?
    var timestamp = Date()
    /// Set when the extension managed to upload the item itself.
    var syncedAt: Date?

    init(contentURL: String?, contentText: String?, sourceApp: String?, userNote: String?, quickTag: String?) {
        self.contentURL = contentURL
        self.contentText = contentText
        self.sourceApp = sourceApp
        self.userNote = userNote
        self.quickTag = quickTag
    }

    // Items queued by older builds have no id or syncedAt; decode them instead of dropping the queue.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        contentURL = try c.decodeIfPresent(String.self, forKey: .contentURL)
        contentText = try c.decodeIfPresent(String.self, forKey: .contentText)
        sourceApp = try c.decodeIfPresent(String.self, forKey: .sourceApp)
        userNote = try c.decodeIfPresent(String.self, forKey: .userNote)
        quickTag = try c.decodeIfPresent(String.self, forKey: .quickTag)
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        syncedAt = try c.decodeIfPresent(Date.self, forKey: .syncedAt)
    }
}
