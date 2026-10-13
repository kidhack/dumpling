import CoreData
import Foundation

/// A user-made group of items, like a trip. Deleting a list keeps its items; they just leave the list.
/// Backed by Core Data (entity "ItemList" in DumplingModel) so it can be shared through iCloud.
@objc(DumplingList)
final class ItemList: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var createdAt: Date
    @NSManaged private var items: NSSet?

    @nonobjc static func fetchRequest() -> NSFetchRequest<ItemList> {
        NSFetchRequest<ItemList>(entityName: "ItemList")
    }

    var itemsArray: [Item] { (items?.allObjects as? [Item]) ?? [] }
    var itemCount: Int { items?.count ?? 0 }

    convenience init(context: NSManagedObjectContext, name: String) {
        self.init(context: context)
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}

extension ItemList: Identifiable {}
