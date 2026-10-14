import CoreData
import Foundation

/// One person's heart on an item. Lives with the item, so it's shared along with a shared list.
@objc(DumplingHeart)
final class Heart: NSManagedObject {
    @NSManaged var id: UUID
    /// The iCloud user record name of whoever hearted the item.
    @NSManaged var userID: String
    @NSManaged var createdAt: Date
    @NSManaged var item: Item?

    convenience init(context: NSManagedObjectContext, userID: String) {
        self.init(context: context)
        self.id = UUID()
        self.userID = userID
        self.createdAt = Date()
    }
}
