import SwiftUI

@main
struct DumplingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let persistence = Persistence.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
    }
}
