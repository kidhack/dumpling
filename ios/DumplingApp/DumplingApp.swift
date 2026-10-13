import SwiftUI

@main
struct DumplingApp: App {
    private let persistence = Persistence.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
    }
}
