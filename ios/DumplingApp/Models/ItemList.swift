import Foundation
import SwiftData

/// A user-made group of items, like a trip. Items stay in their Inbox/Filed/Archived tab too.
@Model
final class ItemList {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    /// Deleting a list keeps its items; they just leave the list. Optional because CloudKit requires it.
    @Relationship(deleteRule: .nullify, inverse: \Item.list)
    var items: [Item]? = []

    init(name: String) {
        self.name = name
    }
}
