import SwiftUI
import SwiftData

@main
struct DumplingApp: App {
    /// Syncs to the user's private iCloud database. The store stays in the App Group container, where it
    /// has always lived. Without an iCloud account it simply stays local.
    let container: ModelContainer = {
        let schema = Schema([Item.self, ItemList.self, RoutingRule.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.com.kidhack.dumpling"))
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Couldn't open the item store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
