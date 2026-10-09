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
    var status: String  // "pending" | "routed" | "failed"

    init(
        contentURL: String? = nil,
        contentText: String? = nil,
        sourceApp: String? = nil,
        userNote: String? = nil,
        quickTag: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.contentURL = contentURL
        self.contentText = contentText
        self.sourceApp = sourceApp
        self.userNote = userNote
        self.quickTag = quickTag
        self.status = "pending"
    }

    // MARK: - Display helpers

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
