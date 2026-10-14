import CoreData
import Foundation

/// A user-made group of items, like a trip. Deleting a list keeps its items; they just leave the list.
/// Backed by Core Data (entity "ItemList" in DumplingModel) so it can be shared through iCloud.
@objc(DumplingList)
final class ItemList: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var createdAt: Date
    /// SF Symbol and color chosen in Edit List; nil means the default list icon.
    @NSManaged var symbolName: String?
    @NSManaged var colorName: String?
    @NSManaged private var items: NSSet?

    @nonobjc static func fetchRequest() -> NSFetchRequest<ItemList> {
        NSFetchRequest<ItemList>(entityName: "ItemList")
    }

    /// Every item, archived ones included (they keep their list, so unarchiving puts them back).
    var itemsArray: [Item] { (items?.allObjects as? [Item]) ?? [] }
    /// What the list shows: archived items appear only in Archived.
    var activeItems: [Item] { itemsArray.filter { !$0.isArchived } }
    var itemCount: Int { activeItems.count }

    convenience init(context: NSManagedObjectContext, name: String) {
        self.init(context: context)
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}

extension ItemList: Identifiable {}
