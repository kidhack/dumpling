import CloudKit
import CoreData
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.kidhack.dumpling", category: "Sharing")

/// iCloud sharing for lists, on top of NSPersistentCloudKitContainer.
///
/// A shared list and its items live in a share zone: in the owner's private store, or in a participant's
/// shared store. Core Data can't relate objects across stores or zones, so moving an item into or out of a
/// shared list copies it to the right place and deletes the original.
@MainActor
enum Sharing {
    private static var persistence: Persistence { .shared }
    private static var container: NSPersistentCloudKitContainer { persistence.container }

    // MARK: - State

    /// The CloudKit share for a list, if it's shared (by the user or with them).
    static func share(for list: ItemList) -> CKShare? {
        (try? container.fetchShares(matching: [list.objectID]))?[list.objectID]
    }

    static func isShared(_ list: ItemList) -> Bool {
        isInSharedStore(list) || share(for: list) != nil
    }

    /// True for lists and items someone else shared with the user.
    static func isInSharedStore(_ object: NSManagedObject) -> Bool {
        object.objectID.persistentStore == persistence.sharedStore
    }

    static func isOwner(of list: ItemList) -> Bool { !isInSharedStore(list) }

    static func canEdit(_ list: ItemList) -> Bool {
        container.canUpdateRecord(forManagedObjectWith: list.objectID)
    }

    // MARK: - People

    /// Everyone on a shared list, owner first.
    static func participants(of list: ItemList) -> [CKShare.Participant] {
        guard let share = share(for: list) else { return [] }
        return share.participants
            .filter { $0.acceptanceStatus != .removed }
            .sorted { ($0.role == .owner ? 0 : 1, displayName($0)) < ($1.role == .owner ? 0 : 1, displayName($1)) }
    }

    static func displayName(_ participant: CKShare.Participant) -> String {
        let identity = participant.userIdentity
        if let components = identity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !name.isEmpty { return name }
        }
        return identity.lookupInfo?.emailAddress ?? identity.lookupInfo?.phoneNumber ?? "Someone"
    }

    static func isCurrentUser(_ participant: CKShare.Participant, in list: ItemList) -> Bool {
        share(for: list)?.currentUserParticipant == participant
    }

    /// "you", a participant's name, or nil when the person isn't known (e.g. the list isn't shared).
    static func name(for userID: String?, in list: ItemList?) -> String? {
        guard let userID else { return nil }
        if userID == Hearts.myID { return "you" }
        guard let list, let share = share(for: list) else { return nil }
        if let match = share.participants.first(where: { $0.userIdentity.userRecordID?.recordName == userID }) {
            return share.currentUserParticipant == match ? "you" : displayName(match)
        }
        return nil
    }

    // MARK: - Sharing a list

    /// Shares the list (and its items), or returns its existing share.
    static func shareList(_ list: ItemList) async throws -> CKShare {
        if let existing = share(for: list) { return existing }
        let (_, share, _) = try await container.share([list] + list.itemsArray, to: nil)
        share[CKShare.SystemFieldKey.title] = list.name
        share.publicPermission = .none
        return share
    }

    /// Saves changes the sharing sheet made (participants, permissions, title).
    static func persistUpdatedShare(_ share: CKShare, for list: ItemList) {
        guard let store = list.objectID.persistentStore else { return }
        container.persistUpdatedShare(share, in: store) { _, error in
            if let error { logger.error("Saving share failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    // MARK: - Accepting

    static func accept(_ metadata: CKShare.Metadata) {
        guard let sharedStore = persistence.sharedStore else { return }
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error {
                logger.error("Accepting share failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.info("Accepted shared list \(metadata.share.recordID.zoneID.zoneName, privacy: .public)")
            }
        }
    }

    // MARK: - Moving items

    /// Puts an item in a list (or out of one, with `nil`), moving it between stores or share zones as needed.
    static func move(_ item: Item, to list: ItemList?, in context: NSManagedObjectContext) async {
        guard item.list?.objectID != list?.objectID else { return }

        let destinationStore = list.flatMap { $0.objectID.persistentStore } ?? persistence.privateStore
        let destinationShare = list.flatMap(share(for:))
        let currentShare = item.list.flatMap(share(for:))
        let sameStore = item.objectID.persistentStore == destinationStore
        let sameShare = currentShare?.recordID == destinationShare?.recordID

        if sameStore && sameShare {
            item.list = list
            return
        }

        if sameStore, let destinationShare, currentShare == nil, !isInSharedStore(item) {
            // The owner adding a private item to their own shared list: share it into the list's zone.
            item.list = list
            try? context.save()
            do {
                _ = try await container.share([item], to: destinationShare)
            } catch {
                logger.error("Adding item to share failed: \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        // Different store or zone: copy into the destination and remove the original.
        guard let destinationStore else { return }
        let copy = Item(context: context)
        context.assign(copy, to: destinationStore)
        copyFields(from: item, to: copy, store: destinationStore)
        copy.list = list
        context.delete(item)
    }

    /// Owner deleting a shared list: items come back unlisted to the private store, then the share goes away.
    /// A participant "deleting" leaves the list instead.
    static func delete(_ list: ItemList, in context: NSManagedObjectContext) async {
        if isInSharedStore(list) {
            await leave(list)
            return
        }
        guard let share = share(for: list) else {
            context.delete(list)
            try? context.save()
            return
        }
        for item in list.itemsArray { await move(item, to: nil, in: context) }
        context.delete(list)
        try? context.save()
        do {
            try await container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID,
                                                              in: persistence.privateStore)
        } catch {
            logger.error("Removing share failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The owner stopped sharing from the sharing sheet: keep the list and items by copying them back to the
    /// private store's default zone, then remove the share zone.
    static func stopSharing(_ list: ItemList) async {
        guard isOwner(of: list), let share = share(for: list), let privateStore = persistence.privateStore else { return }
        let context = persistence.viewContext
        let copy = ItemList(context: context, name: list.name)
        context.assign(copy, to: privateStore)
        copy.createdAt = list.createdAt
        for item in list.itemsArray {
            let itemCopy = Item(context: context)
            context.assign(itemCopy, to: privateStore)
            copyFields(from: item, to: itemCopy, store: privateStore)
            itemCopy.list = copy
        }
        try? context.save()
        do {
            try await container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: privateStore)
        } catch {
            logger.error("Removing share failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Participant leaving a list someone shared with them: removes the local copy, not the owner's.
    static func leave(_ list: ItemList) async {
        guard let share = share(for: list) else { return }
        do {
            try await container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: persistence.sharedStore)
        } catch {
            logger.error("Leaving share failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `store` is passed in because a new object only reports its store after it has been saved.
    private static func copyFields(from source: Item, to copy: Item, store: NSPersistentStore) {
        copy.id = source.id
        copy.timestamp = source.timestamp
        copy.contentURL = source.contentURL
        copy.contentText = source.contentText
        copy.sourceApp = source.sourceApp
        copy.userNote = source.userNote
        copy.quickTag = source.quickTag
        copy.status = source.status
        copy.syncedAt = source.syncedAt
        copy.category = source.category
        copy.title = source.title
        copy.relevantDate = source.relevantDate
        copy.filedTo = source.filedTo
        copy.eventKitID = source.eventKitID
        copy.sortError = source.sortError
        copy.location = source.location
        copy.latitude = source.latitude
        copy.longitude = source.longitude
        copy.isAllDay = source.isAllDay
        copy.archivedAt = source.archivedAt
        copy.isHearted = source.isHearted
        copy.otherHearts = source.otherHearts
        copy.createdByID = source.createdByID
        // Hearts belong to the item, so they move with it into the copy's store.
        guard let context = copy.managedObjectContext else { return }
        for heart in source.heartRecords {
            let heartCopy = Heart(context: context, userID: heart.userID)
            context.assign(heartCopy, to: store)
            heartCopy.id = heart.id
            heartCopy.createdAt = heart.createdAt
            heartCopy.item = copy
        }
    }
}
