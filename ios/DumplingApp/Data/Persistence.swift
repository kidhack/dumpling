import CloudKit
import CoreData
import OSLog

private let logger = Logger(subsystem: "com.kidhack.dumpling", category: "Persistence")

/// Core Data + CloudKit. Two stores share one model:
/// - private: the user's own items and lists. The same file SwiftData used, so nothing moves or migrates.
/// - shared: lists other people share with the user (filled in by CloudKit sharing).
final class Persistence: @unchecked Sendable {
    static let shared = Persistence()
    static let cloudKitContainer = "iCloud.com.kidhack.dumpling"

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    var viewContext: NSManagedObjectContext { container.viewContext }

    private init() {
        container = NSPersistentCloudKitContainer(name: "default", managedObjectModel: DumplingModel.shared)

        let directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.suiteName)!
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let privateDescription = Self.description(at: directory.appending(path: "default.store"), scope: .private)
        let sharedDescription = Self.description(at: directory.appending(path: "shared.store"), scope: .shared)
        container.persistentStoreDescriptions = [privateDescription, sharedDescription]

        var loadError: Error?
        container.loadPersistentStores { description, error in
            if let error {
                logger.error("Store failed to load: \(error.localizedDescription, privacy: .public)")
                loadError = error
            }
        }
        if let loadError { fatalError("Couldn't open the item store: \(loadError)") }

        for store in container.persistentStoreCoordinator.persistentStores {
            switch store.url {
            case privateDescription.url: privateStore = store
            case sharedDescription.url: sharedStore = store
            default: break
            }
        }

        #if DEBUG
        // Before deploying the CloudKit schema to production (needed for TestFlight), launch once with
        // DUMPLING_INIT_CLOUDKIT_SCHEMA=1 so every record type and field exists in the development schema,
        // including fields no device has synced yet.
        if ProcessInfo.processInfo.environment["DUMPLING_INIT_CLOUDKIT_SCHEMA"] == "1" {
            do {
                try container.initializeCloudKitSchema(options: [])
                logger.info("CloudKit development schema initialized")
                print("DUMPLING: CloudKit development schema initialized")
            } catch {
                logger.error("Schema init failed: \(error.localizedDescription, privacy: .public)")
                print("DUMPLING: schema init failed: \(error)")
            }
        }
        #endif

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    /// New items and lists start in the user's private store; sharing moves them to a shared zone later.
    func assignToPrivateStore(_ object: NSManagedObject) {
        guard let privateStore, let context = object.managedObjectContext else { return }
        context.assign(object, to: privateStore)
    }

    private static func description(at url: URL, scope: CKDatabase.Scope) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainer)
        options.databaseScope = scope
        description.cloudKitContainerOptions = options
        // Required by the CloudKit mirror; the existing store already has history tracking on.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        return description
    }
}
