import Foundation

/// Shared App Group helpers. Both the main app and share extension use this suite.
enum AppGroup {
    static let suiteName = "group.com.kidhack.dumpling"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Settings (written by main app, read by extension)

    static var relayURL: String {
        get { defaults.string(forKey: "relay_url") ?? "" }
        set { defaults.set(newValue, forKey: "relay_url") }
    }

    static var authToken: String {
        get { defaults.string(forKey: "auth_token") ?? "" }
        set { defaults.set(newValue, forKey: "auth_token") }
    }

    // MARK: - Pending items queue (written by extension, read + cleared by main app)

    static func enqueue(_ item: PendingItem) {
        var queue = pendingItems()
        queue.append(item)
        if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: "pending_items")
        }
    }

    static func dequeueAll() -> [PendingItem] {
        guard let data = defaults.data(forKey: "pending_items"),
              let items = try? JSONDecoder().decode([PendingItem].self, from: data)
        else { return [] }
        defaults.removeObject(forKey: "pending_items")
        return items
    }

    private static func pendingItems() -> [PendingItem] {
        guard let data = defaults.data(forKey: "pending_items"),
              let items = try? JSONDecoder().decode([PendingItem].self, from: data)
        else { return [] }
        return items
    }
}

// MARK: - Transfer type (extension → app)

struct PendingItem: Codable {
    var contentURL: String?
    var contentText: String?
    var sourceApp: String?
    var userNote: String?
    var quickTag: String?
    var timestamp: Date = Date()
}
