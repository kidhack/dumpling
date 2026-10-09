import Foundation
import SwiftData

@Model
final class Item {
    var id: UUID
    var timestamp: Date
    var contentURL: String?
    var contentText: String?
    var sourceApp: String?
    var userNote: String?
    var quickTag: String?
    /// "pending" (not sorted yet) | "filed" (in Reminders/Calendar) | "kept" (stays in Dumpling) | "failed"
    var status: String
    var syncedAt: Date?

    // Set by on-device sorting
    var category: String?
    var title: String?
    var relevantDate: Date?
    var filedTo: String?
    var eventKitID: String?
    var sortError: String?

    init(
        id: UUID = UUID(),
        contentURL: String? = nil,
        contentText: String? = nil,
        sourceApp: String? = nil,
        userNote: String? = nil,
        quickTag: String? = nil
    ) {
        self.id = id
        self.timestamp = Date()
        self.contentURL = contentURL
        self.contentText = contentText
        self.sourceApp = sourceApp
        self.userNote = userNote
        self.quickTag = quickTag
        self.status = "pending"
    }

    // MARK: - Display helpers

    /// The relay rejects items with neither a URL nor text (e.g. image-only shares).
    var isUploadable: Bool { contentURL != nil || contentText != nil }

    var syncLabel: String {
        guard isUploadable else { return "Not supported yet" }
        guard let syncedAt else { return "Not synced" }
        return "Synced " + syncedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var relayPayload: RelayClient.ItemPayload {
        .init(contentURL: contentURL, contentText: contentText, sourceApp: sourceApp,
              userNote: userNote, quickTag: quickTag, sharedAt: timestamp)
    }

    var displayTitle: String { title ?? preview }

    var statusLabel: String {
        switch status {
        case "pending": return "Not sorted yet"
        case "filed":   return filedTo ?? "Filed"
        case "kept":    return "Kept in Dumpling"
        case "failed":  return "Couldn't file"
        default:        return status.capitalized
        }
    }

    var categoryLabel: String? { category?.capitalized }

    var preview: String {
        if let url = contentURL { return url }
        if let text = contentText { return text }
        return "(no content)"
    }

    var tagLabel: String? {
        switch quickTag {
        case "reminder":      return "Reminder"
        case "event":         return "Event"
        case "music":         return "Music"
        case "software_idea": return "Idea"
        case "link_save":     return "Saved Link"
        default:              return quickTag
        }
    }
}
