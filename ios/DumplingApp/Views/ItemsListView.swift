import SwiftUI
import SwiftData
import FoundationModels
import OSLog

private let logger = Logger(subsystem: "com.kidhack.dumpling", category: "Sync")

struct ItemsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @State private var isSyncing = false
    @State private var isSorting = false
    @State private var modelUnavailable: SystemLanguageModel.Availability.UnavailableReason?
    @State private var filer = Filer()

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
            .safeAreaInset(edge: .top) {
                if let reason = modelUnavailable {
                    ModelUnavailableBanner(reason: reason)
                }
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
        .onAppear { Task { await refresh() } }
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
        await sortPendingItems()
        await uploadUnsyncedItems()
    }

    private func sortPendingItems() async {
        guard !isSorting else { return }
        isSorting = true
        defer { isSorting = false }
        modelUnavailable = await Processor.processPending(items.reversed(), filer: filer)
        try? modelContext.save()
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
            Text(item.displayTitle)
                .lineLimit(2)

            if item.title != nil {
                Text(item.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let note = item.userNote {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Label(item.statusLabel, systemImage: statusIcon)
                Text(item.timestamp, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: String {
        switch item.status {
        case "filed": return item.category == "event" ? "calendar" : "checklist"
        case "kept": return "tray"
        case "failed": return "exclamationmark.triangle"
        default: return "hourglass"
        }
    }
}

struct ModelUnavailableBanner: View {
    let reason: SystemLanguageModel.Availability.UnavailableReason

    var body: some View {
        Label(message, systemImage: "sparkles")
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.yellow.opacity(0.2), in: .rect(cornerRadius: 10))
            .padding(.horizontal)
    }

    private var message: String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to sort items. They'll be sorted next time you open Dumpling."
        case .modelNotReady:
            return "Apple Intelligence is still downloading. Items will be sorted once it's ready."
        case .deviceNotEligible:
            return "This device can't run Apple Intelligence, so items won't be sorted."
        @unknown default:
            return "On-device sorting isn't available right now."
        }
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
            Section("Sorting") {
                LabeledContent("Status", value: item.statusLabel)
                if let category = item.categoryLabel {
                    LabeledContent("Category", value: category)
                }
                if let date = item.relevantDate {
                    LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Tag", value: item.tagLabel ?? "None")
                if let error = item.sortError {
                    Text(error).foregroundStyle(.secondary)
                }
                if item.status != "filed" {
                    Button("Sort Again") {
                        item.status = "pending"
                        item.sortError = nil
                    }
                }
            }
            Section {
                LabeledContent("Shared", value: item.timestamp.formatted(date: .abbreviated, time: .shortened))
                if RelayClient.isConfigured {
                    LabeledContent("Relay", value: item.syncLabel)
                }
            }
        }
        .navigationTitle(item.title ?? "Item")
        .navigationBarTitleDisplayMode(.inline)
    }
}
