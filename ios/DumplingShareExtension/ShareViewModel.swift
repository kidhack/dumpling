import Foundation

/// Manages state for the share sheet UI.
/// Phase 0: logs extracted payload to console, no network calls.
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

        // Phase 0: log payload, no network
        print("[Dumpling] payload:")
        print("  url:       \(url ?? "(none)")")
        print("  text:      \(text ?? "(none)")")
        print("  image:     \(imageData.map { "\($0.count) bytes" } ?? "(none)")")
        print("  sourceApp: \(sourceApp ?? "(none)")")
        print("  note:      \(userNote ?? "(none)")")
        print("  quickTag:  \(quickTag ?? "(none)")")

        try? await Task.sleep(nanoseconds: 400_000_000)
        result = .success("Logged! 🥟")
    }
}
