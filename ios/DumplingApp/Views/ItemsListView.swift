import SwiftUI
import SwiftData

struct ItemsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        ItemRowView(item: item)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Items")
            .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Items Yet",
                        systemImage: "tray",
                        description: Text("Share something from any app to see it here.")
                    )
                }
            }
            .toolbar {
                if !items.isEmpty { EditButton() }
            }
        }
        .onAppear(perform: importPendingItems)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { importPendingItems() }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(items[index]) }
        try? modelContext.save()
    }

    private func importPendingItems() {
        let pending = AppGroup.dequeueAll()
        for p in pending {
            let item = Item(
                contentURL: p.contentURL,
                contentText: p.contentText,
                sourceApp: p.sourceApp,
                userNote: p.userNote,
                quickTag: p.quickTag
            )
            item.timestamp = p.timestamp
            modelContext.insert(item)
        }
        if !pending.isEmpty {
            try? modelContext.save()
        }
    }
}

// MARK: - Row

struct ItemRowView: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.preview)
                .lineLimit(2)

            if let note = item.userNote {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                if let tag = item.tagLabel {
                    Text(tag)
                }
                Text(item.timestamp, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

struct ItemDetailView: View {
    let item: Item

    var body: some View {
        Form {
            if let urlString = item.contentURL {
                Section("Link") {
                    if let url = URL(string: urlString) {
                        Link(urlString, destination: url)
                    } else {
                        Text(urlString)
                    }
                }
            }
            if let text = item.contentText {
                Section("Text") {
                    Text(text).textSelection(.enabled)
                }
            }
            if let note = item.userNote {
                Section("Note") {
                    Text(note).textSelection(.enabled)
                }
            }
            Section {
                LabeledContent("Tag", value: item.tagLabel ?? "None")
                LabeledContent("Status", value: item.status.capitalized)
                LabeledContent("Shared", value: item.timestamp.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle("Item")
        .navigationBarTitleDisplayMode(.inline)
    }
}
