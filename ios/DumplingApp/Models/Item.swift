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

    var sourceEmoji: String {
        switch sourceApp?.lowercased() {
        case "safari":    return "🧭"
        case "chrome":    return "🌐"
        case "instagram": return "📸"
        case "spotify":   return "🎧"
        case "linkedin":  return "💼"
        case "twitter/x": return "🐦"
        case "tiktok":    return "🎵"
        case "mail":      return "📧"
        default:          return "📥"
        }
    }

    var tagColor: String {
        switch quickTag {
        case "reminder":      return "FFB3C6"
        case "event":         return "B3D9FF"
        case "music":         return "D9B3FF"
        case "software_idea": return "FFF3B3"
        case "link_save":     return "B3FFD9"
        default:              return "FAFAF0"
        }
    }
}
