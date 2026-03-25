import Foundation
import UniformTypeIdentifiers
import Social

/// Handles uploading shared content to the Dumpling relay.
@MainActor
class ShareViewModel: ObservableObject {

    @Published var isLoading = false
    @Published var result: UploadResult? = nil

    enum UploadResult {
        case success(String)
        case failure(String)
    }

    // MARK: - Config (read from UserDefaults shared with DumplingApp)

    static let suiteName = "group.com.dumpling.app"

    var relayURL: String {
        UserDefaults(suiteName: Self.suiteName)?.string(forKey: "relay_url")
            ?? "https://dumpling.fly.dev"
    }

    var authToken: String {
        UserDefaults(suiteName: Self.suiteName)?.string(forKey: "auth_token")
            ?? ""
    }

    // MARK: - Upload

    func upload(
        text: String?,
        url: String?,
        imageData: Data?,
        imageMimeType: String = "image/jpeg",
        sourceApp: String?,
        userNote: String?,
        quickTag: String?
    ) async {
        isLoading = true
        defer { isLoading = false }

        guard let relayBase = URL(string: relayURL) else {
            result = .failure("Invalid relay URL")
            return
        }

        let endpoint = relayBase.appendingPathComponent("/ingest")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        if let text { addField("content_text", text) }
        if let url { addField("content_url", url) }
        if let sourceApp { addField("source_app", sourceApp) }
        if let userNote { addField("user_note", userNote) }
        if let quickTag { addField("quick_tag", quickTag) }

        if let imageData {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"share.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(imageMimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(statusCode) {
                result = .success("Dumpling'd! 🥟")
            } else {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                result = .failure("Server error \(statusCode): \(msg)")
            }
        } catch {
            result = .failure(error.localizedDescription)
        }
    }
}
