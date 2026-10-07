import Foundation
import SwiftData

@Model
final class RoutingRule {
    var id: UUID
    var pattern: String
    var patternType: String   // "substring" | "domain" | "regex"
    var contentType: String   // "event" | "reminder" | "music" | etc.
    var action: String
    var target: String
    var isEnabled: Bool
    var matchCount: Int
    var createdAt: Date

    init(
        pattern: String,
        patternType: String = "substring",
        contentType: String,
        action: String,
        target: String
    ) {
        self.id = UUID()
        self.pattern = pattern
        self.patternType = patternType
        self.contentType = contentType
        self.action = action
        self.target = target
        self.isEnabled = true
        self.matchCount = 0
        self.createdAt = Date()
    }
}
