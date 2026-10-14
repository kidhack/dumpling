import CoreData

/// The Core Data model from Dumpling.xcdatamodeld. Each version is kept in the bundle so Core Data can
/// upgrade existing stores automatically. Version 1 matches the schema SwiftData originally created.
enum DumplingModel {
    // Loaded once and never changed after the defaults below, so sharing it across threads is safe.
    nonisolated(unsafe) static let shared: NSManagedObjectModel = load()

    /// CloudKit requires a default on every non-optional attribute, and .xcdatamodel files can't hold UUID
    /// defaults, so they're set here. Real IDs are always set in initializers. Defaults don't affect hashes.
    private static let placeholderID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private static func load() -> NSManagedObjectModel {
        // On device the compiled model loads read-only (from the optimized .omo), so edit a copy.
        guard let url = Bundle.main.url(forResource: "Dumpling", withExtension: "momd"),
              let loaded = NSManagedObjectModel(contentsOf: url),
              let model = loaded.copy() as? NSManagedObjectModel
        else { fatalError("Dumpling.momd is missing from the app bundle") }
        for entity in model.entities {
            entity.attributesByName["id"]?.defaultValue = placeholderID
        }
        return model
    }
}
