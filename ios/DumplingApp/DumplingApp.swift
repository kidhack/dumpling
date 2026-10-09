import SwiftUI
import SwiftData

@main
struct DumplingApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Item.self, RoutingRule.self])
    }
}
