import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var pipeline = ItemPipeline()
    @State private var selection: AppTab = .section(.inbox)

    enum AppTab: Hashable {
        case section(ItemsSection)
        case lists
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(ItemsSection.inbox.rawValue, systemImage: ItemsSection.inbox.systemImage, value: AppTab.section(.inbox)) {
                ItemsListView(section: .inbox)
            }
            Tab("Lists", systemImage: "list.bullet", value: AppTab.lists) {
                ListsView()
            }
            ForEach([ItemsSection.filed, .archived]) { section in
                Tab(section.rawValue, systemImage: section.systemImage, value: AppTab.section(section)) {
                    ItemsListView(section: section)
                }
            }
        }
        .environment(pipeline)
        .task { await pipeline.refresh(modelContext) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await pipeline.refresh(modelContext) } }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, ItemList.self, RoutingRule.self], inMemory: true)
}
