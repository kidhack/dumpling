import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ItemsListView()
                .tabItem {
                    Label("Items", systemImage: "tray.and.arrow.down")
                }
                .tag(0)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(1)
        }
        .tint(.dBlack)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, RoutingRule.self], inMemory: true)
}
