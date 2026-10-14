import SwiftUI
import CoreData

/// Like Mail: one stack with the Lists screen at its root, opened on the Inbox (its back arrow goes to Lists).
struct ContentView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var pipeline = ItemPipeline()
    @State private var path = Self.launchPath

    /// Debug builds can open on another screen (env DUMPLING_START_TAB=lists, saved, favorites or archived) so
    /// screens can be checked without tapping.
    private static var launchPath: NavigationPath {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["DUMPLING_START_TAB"] {
        case "lists": return NavigationPath()
        case "saved": return NavigationPath([ItemsSection.saved])
        case "favorites": return NavigationPath([ItemsSection.favorites])
        case "archived", "filed": return NavigationPath([ItemsSection.archived])
        default: break
        }
        #endif
        return NavigationPath([ItemsSection.inbox])
    }

    /// The item a tapped nearby notification asks to show.
    private var notifiedItem: Binding<Item?> {
        Binding {
            NearbyAlerts.shared.openItemID.flatMap { Item.with(id: $0, in: modelContext) }
        } set: { item in
            if item == nil { NearbyAlerts.shared.openItemID = nil }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ListsView(path: $path)
                // Swipe back from the left edge, or from anywhere on the background.
                .swipeBackEnabled()
                // On every screen: the app opens a screen in (the Inbox), so Lists may never have appeared.
                .navigationDestination(for: ItemsSection.self) { ItemsListView(section: $0).swipeBackEnabled() }
                .navigationDestination(for: ItemList.self) { ListDetailView(list: $0).swipeBackEnabled() }
                .navigationDestination(for: Item.self) {
                    ItemDetailView(item: $0, filer: pipeline.filer).swipeBackEnabled()
                }
        }
        .environment(pipeline)
        .sheet(item: notifiedItem) { item in
            NavigationStack { ItemDetailView(item: item, filer: pipeline.filer) }
        }
        .task {
            NearbyAlerts.shared.appBecame(active: scenePhase == .active)
            await Hearts.prepare(modelContext)
            await pipeline.refresh(modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            NearbyAlerts.shared.appBecame(active: phase == .active)
            if phase == .active {
                Task { await pipeline.refresh(modelContext) }
                // Re-pick the closest places to watch for where the user is now.
                if !NearbyAlerts.shared.watches.isEmpty { Task { await NearbyAlerts.shared.sync() } }
            }
        }
    }
}
