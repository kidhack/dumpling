import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var pipeline = ItemPipeline()
    @State private var selection: ItemsSection = .inbox

    var body: some View {
        TabView(selection: $selection) {
            ForEach(ItemsSection.allCases) { section in
                Tab(section.rawValue, systemImage: section.systemImage, value: section) {
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
        .modelContainer(for: [Item.self, RoutingRule.self], inMemory: true)
}
