import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var pipeline = ItemPipeline()
    @State private var selection: AppTab = Self.launchTab
    @State private var filterResets: [ItemsSection: Int] = [:]
    @State private var listsReset = 0

    /// Tapping the tab you're already on resets its filter to All and scrolls it to the top.
    private var tabSelection: Binding<AppTab> {
        Binding {
            selection
        } set: { tapped in
            if tapped == selection {
                switch tapped {
                case .section(let section): filterResets[section, default: 0] += 1
                case .lists: listsReset += 1
                }
            }
            selection = tapped
        }
    }

    enum AppTab: Hashable {
        case section(ItemsSection)
        case lists
    }

    /// Debug builds can open on a given tab (env DUMPLING_START_TAB=lists) so screens can be checked without tapping.
    private static var launchTab: AppTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["DUMPLING_START_TAB"] {
        case "lists": return .lists
        case "filed": return .section(.filed)
        case "archived": return .section(.archived)
        default: break
        }
        #endif
        return .section(.inbox)
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
        TabView(selection: tabSelection) {
            Tab(ItemsSection.inbox.rawValue, systemImage: ItemsSection.inbox.systemImage, value: AppTab.section(.inbox)) {
                ItemsListView(section: .inbox, filterResetToken: filterResets[.inbox, default: 0],
                              isActiveTab: selection == .section(.inbox))
            }
            Tab("Lists", systemImage: "list.bullet", value: AppTab.lists) {
                ListsView(resetToken: listsReset)
            }
            ForEach([ItemsSection.filed, .archived]) { section in
                Tab(section.rawValue, systemImage: section.systemImage, value: AppTab.section(section)) {
                    ItemsListView(section: section, filterResetToken: filterResets[section, default: 0],
                              isActiveTab: selection == .section(section))
                }
            }
        }
        .environment(pipeline)
        .sheet(item: notifiedItem) { item in
            NavigationStack { ItemDetailView(item: item, filer: pipeline.filer) }
        }
        .task {
            await Hearts.prepare(modelContext)
            await pipeline.refresh(modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await pipeline.refresh(modelContext) }
                // Re-pick the closest places to watch for where the user is now.
                if !NearbyAlerts.shared.watches.isEmpty { Task { await NearbyAlerts.shared.sync() } }
            }
        }
    }
}
