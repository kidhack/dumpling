import CoreData
import Foundation

/// A shared item. Backed by Core Data (entity "Item" in DumplingModel) so lists can be shared through iCloud.
@objc(DumplingItem)
final class Item: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var timestamp: Date
    @NSManaged var contentURL: String?
    @NSManaged var contentText: String?
    @NSManaged var sourceApp: String?
    @NSManaged var userNote: String?
    @NSManaged var quickTag: String?
    /// "pending" (not sorted yet) | "filed" (in Reminders/Calendar) | "kept" (stays in Dumpling) | "failed"
    @NSManaged var status: String
    @NSManaged var syncedAt: Date?

    // Set by on-device sorting
    @NSManaged var category: String?
    @NSManaged var title: String?
    @NSManaged var relevantDate: Date?
    @NSManaged var filedTo: String?
    @NSManaged var eventKitID: String?
    @NSManaged var sortError: String?
    @NSManaged var location: String?
    @NSManaged var isAllDay: Bool
    @NSManaged var archivedAt: Date?
    @NSManaged var list: ItemList?
    /// iCloud user record names, for "Added by" and "Edited by" on shared lists.
    @NSManaged var createdByID: String?
    @NSManaged var modifiedByID: String?
    @NSManaged var modifiedAt: Date?
    @NSManaged private var hearts: NSSet?
    /// The user's own heart.
    @NSManaged var isHearted: Bool

    // Optional numbers are stored as objects, so they go through KVC.
    var latitude: Double? {
        get { value(forKey: "latitude") as? Double }
        set { setValue(newValue, forKey: "latitude") }
    }

    var longitude: Double? {
        get { value(forKey: "longitude") as? Double }
        set { setValue(newValue, forKey: "longitude") }
    }

    /// Hearts from other people on a shared list.
    var otherHearts: Int {
        get { Int(value(forKey: "otherHearts") as? Int64 ?? 0) }
        set { setValue(Int64(newValue), forKey: "otherHearts") }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<Item> {
        NSFetchRequest<Item>(entityName: "Item")
    }

    /// Every item across the private and shared stores, oldest first.
    static func all(in context: NSManagedObjectContext) -> [Item] {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    convenience init(
        context: NSManagedObjectContext,
        id: UUID = UUID(),
        contentURL: String? = nil,
        contentText: String? = nil,
        sourceApp: String? = nil,
        userNote: String? = nil,
        quickTag: String? = nil
    ) {
        self.init(context: context)
        self.id = id
        self.timestamp = Date()
        self.contentURL = contentURL
        self.contentText = contentText
        self.sourceApp = sourceApp
        self.userNote = userNote
        self.quickTag = quickTag
        self.status = "pending"
        self.createdByID = Hearts.myID
    }

    /// Stamps who changed the item and when. Only saves made on this device count: CloudKit imports
    /// merge into the view context without saving it, so other people's changes keep their own stamps.
    /// Heart and sync bookkeeping aren't edits.
    override func willSave() {
        super.willSave()
        guard !isDeleted, managedObjectContext === Persistence.shared.viewContext else { return }
        let changed = Set(changedValues().keys)
        guard !changed.isSubset(of: ["modifiedByID", "modifiedAt", "syncedAt", "hearts", "latitude", "longitude"]) else { return }
        // Primitive setters so this doesn't trigger another round of willSave.
        setPrimitiveValue(Hearts.myID, forKey: "modifiedByID")
        setPrimitiveValue(Date(), forKey: "modifiedAt")
    }

    // MARK: - Display helpers

    /// The relay rejects items with neither a URL nor text (e.g. image-only shares).
    var isUploadable: Bool { contentURL != nil || contentText != nil }

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

    var heartRecords: [Heart] { (hearts?.allObjects as? [Heart]) ?? [] }

    func heart(by userID: String) -> Heart? { heartRecords.first { $0.userID == userID } }

    /// Distinct people who hearted the item. `isHearted` is the pre-per-person flag, kept until converted.
    var heartedByMe: Bool { Hearts.myID.map { heart(by: $0) != nil } ?? false }
    var otherHeartCount: Int { Set(heartRecords.map(\.userID)).subtracting([Hearts.myID ?? ""]).count }
    var heartCount: Int { (heartedByMe ? 1 : 0) + otherHeartCount }

    /// In a list someone else shared with the user. These only show inside their list.
    var isFromSharedList: Bool { objectID.persistentStore == Persistence.shared.sharedStore }

    var isFiled: Bool { status == "filed" }
    /// Filed by the user to keep, without a Calendar or Reminders entry.
    var isSavedForLater: Bool { isFiled && eventKitID == nil }

    func saveForLater() {
        status = "filed"
        filedTo = "Saved for Later"
        eventKitID = nil
        archivedAt = nil
    }

    func moveToInbox() {
        status = "kept"
        filedTo = nil
        eventKitID = nil
        archivedAt = nil
    }
    var isArchived: Bool { archivedAt != nil }
    /// Open items: not filed, archived, or put in a list (a list is where it was filed to).
    var isInInbox: Bool { !isFiled && !isArchived && list == nil }
    /// Filed items that haven't been archived.
    var isInFiled: Bool { isFiled && !isArchived }

    var preview: String {
        if let url = contentURL { return url }
        if let text = contentText { return text }
        return "(no content)"
    }

    var tagLabel: String? {
        CategoryKind(quickTag: quickTag)?.label ?? quickTag
    }
}

extension Item: Identifiable {}
