import Foundation

/// Uploads items to the relay (see relay/README.md). PUT is idempotent on the item id, so retries are safe.
enum RelayClient {

    enum UploadError: Error, LocalizedError {
        case notConfigured
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Relay URL or token not set"
            case .badStatus(let code): return "Relay returned HTTP \(code)"
            }
        }
    }

    struct ItemPayload: Encodable, Sendable {
        let contentURL: String?
        let contentText: String?
        let sourceApp: String?
        let userNote: String?
        let quickTag: String?
        let sharedAt: Date

        enum CodingKeys: String, CodingKey {
            case contentURL = "content_url"
            case contentText = "content_text"
            case sourceApp = "source_app"
            case userNote = "user_note"
            case quickTag = "quick_tag"
            case sharedAt = "shared_at"
        }
    }

    static var isConfigured: Bool {
        !AppGroup.relayURL.isEmpty && !AppGroup.authToken.isEmpty
    }

    static func upload(id: UUID, payload: ItemPayload, timeout: TimeInterval = 15) async throws {
        guard isConfigured,
              let base = URL(string: AppGroup.relayURL)
        else { throw UploadError.notConfigured }

        var request = URLRequest(url: base.appending(path: "items/\(id.uuidString.lowercased())"))
        request.httpMethod = "PUT"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppGroup.authToken)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw UploadError.badStatus(code) }
    }
}

extension PendingItem {
    var relayPayload: RelayClient.ItemPayload {
        .init(contentURL: contentURL, contentText: contentText, sourceApp: sourceApp,
              userNote: userNote, quickTag: quickTag, sharedAt: timestamp)
    }
}
