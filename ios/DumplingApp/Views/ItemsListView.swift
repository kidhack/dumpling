import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.kidhack.dumpling", category: "Sync")

struct ItemsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @State private var isSyncing = false

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
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(items[index]) }
        try? modelContext.save()
    }

    private func refresh() async {
        importPendingItems()
        await uploadUnsyncedItems()
    }

    private func importPendingItems() {
        let pending = AppGroup.dequeueAll()
        for p in pending {
            let item = Item(
                id: p.id,
                contentURL: p.contentURL,
                contentText: p.contentText,
                sourceApp: p.sourceApp,
                userNote: p.userNote,
                quickTag: p.quickTag
            )
            item.timestamp = p.timestamp
            item.syncedAt = p.syncedAt
            modelContext.insert(item)
        }
        if !pending.isEmpty {
            try? modelContext.save()
        }
    }

    private func uploadUnsyncedItems() async {
        guard RelayClient.isConfigured, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let unsynced = items.filter { $0.syncedAt == nil && $0.isUploadable }
        for item in unsynced {
            do {
                try await RelayClient.upload(id: item.id, payload: item.relayPayload)
                item.syncedAt = Date()
            } catch {
                logger.error("Upload failed for \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                break
            }
        }
        try? modelContext.save()
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
                Spacer()
                if item.isUploadable {
                    Image(systemName: item.syncedAt == nil ? "icloud.slash" : "checkmark.icloud")
                        .accessibilityLabel(item.syncedAt == nil ? "Not synced" : "Synced")
                }
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
                LabeledContent("Relay", value: item.syncLabel)
                LabeledContent("Shared", value: item.timestamp.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle("Item")
        .navigationBarTitleDisplayMode(.inline)
    }
}
