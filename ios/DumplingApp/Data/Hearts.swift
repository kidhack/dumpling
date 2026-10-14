import CloudKit
import CoreData
import OSLog

private let logger = Logger(subsystem: "com.kidhack.dumpling", category: "Hearts")

/// Per-person hearts. Each heart records the iCloud user who made it, so on a shared list everyone's hearts
/// stay separate and the same person's devices agree.
enum Hearts {
    private static let idKey = "heartsUserID"
    private static let convertedKey = "convertedLegacyHearts.v1"

    /// This user's iCloud record name, once known.
    static var myID: String? { UserDefaults.standard.string(forKey: idKey) }

    /// Looks up the iCloud user, then converts old single-flag hearts once.
    @MainActor
    static func prepare(_ context: NSManagedObjectContext) async {
        if myID == nil {
            do {
                let recordID = try await CKContainer(identifier: Persistence.cloudKitContainer).userRecordID()
                UserDefaults.standard.set(recordID.recordName, forKey: idKey)
            } catch {
                // No iCloud account: hearts still work on this device.
                logger.info("No iCloud user, using a local ID: \(error.localizedDescription, privacy: .public)")
                UserDefaults.standard.set("local-\(UUID().uuidString)", forKey: idKey)
            }
        }
        await convertLegacyHearts(context)
    }

    @MainActor
    static func toggle(_ item: Item, in context: NSManagedObjectContext) async {
        guard let me = myID else { return }
        if let mine = item.heart(by: me) {
            context.delete(mine)
            try? context.save()
        } else {
            await add(by: me, to: item, in: context)
        }
    }

    @MainActor
    private static func add(by userID: String, to item: Item, in context: NSManagedObjectContext) async {
        let heart = Heart(context: context, userID: userID)
        if let store = item.objectID.persistentStore { context.assign(heart, to: store) }
        heart.item = item
        try? context.save()
        // On a list the user shared, new records must be added to the share to reach everyone.
        if !item.isFromSharedList, let list = item.list, let share = Sharing.share(for: list) {
            do {
                _ = try await Persistence.shared.container.share([heart], to: share)
            } catch {
                logger.error("Sharing heart failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Hearts used to be one shared flag per item. Turn the user's own flagged items into their hearts.
    /// Only items in the private store: on a list shared with the user, the flag was set by the owner.
    @MainActor
    private static func convertLegacyHearts(_ context: NSManagedObjectContext) async {
        guard let me = myID, !UserDefaults.standard.bool(forKey: convertedKey) else { return }
        for item in Item.all(in: context) where item.isHearted && !item.isFromSharedList {
            if item.heart(by: me) == nil { await add(by: me, to: item, in: context) }
            item.isHearted = false
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: convertedKey)
    }
}
