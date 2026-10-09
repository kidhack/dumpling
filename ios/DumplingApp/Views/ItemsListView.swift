import SwiftUI
import SwiftData
import FoundationModels
import OSLog

private let logger = Logger(subsystem: "com.kidhack.dumpling", category: "Sync")

enum ItemsSection: String, CaseIterable, Identifiable {
    case inbox = "Inbox", filed = "Filed", archived = "Archived"
    var id: Self { self }

    func contains(_ item: Item) -> Bool {
        switch self {
        case .inbox: return item.isInInbox
        case .filed: return item.isFiled
        case .archived: return item.isArchived && !item.isFiled
        }
    }

    var emptyTitle: String {
        switch self {
        case .inbox: return "Inbox Zero"
        case .filed: return "Nothing Filed Yet"
        case .archived: return "No Archived Items"
        }
    }

    var emptyMessage: String {
        switch self {
        case .inbox: return "Share something from any app. Events and tasks are filed automatically; everything else lands here."
        case .filed: return "Items added to Calendar or Reminders show up here."
        case .archived: return "Swipe an inbox item to archive it."
        }
    }
}

struct ItemsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @State private var section: ItemsSection = .inbox
    @State private var isSyncing = false
    @State private var isSorting = false
    @State private var modelUnavailable: SystemLanguageModel.Availability.UnavailableReason?
    @State private var filer = Filer()

    private var visible: [Item] { items.filter(section.contains) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visible) { item in
                    NavigationLink(value: item) {
                        ItemRowView(item: item)
                    }
                    .swipeActions(edge: .trailing) { swipeActions(for: item) }
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    Picker("Section", selection: $section) {
                        ForEach(ItemsSection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    if let reason = modelUnavailable {
                        ModelUnavailableBanner(reason: reason)
                    }
                }
                .padding(.bottom, 4)
                .background(.bar)
            }
            .navigationTitle("Dumpling")
            .navigationDestination(for: Item.self) { ItemDetailView(item: $0, filer: filer) }
            .overlay {
                if visible.isEmpty {
                    ContentUnavailableView(section.emptyTitle, systemImage: "tray",
                                           description: Text(section.emptyMessage))
                }
            }
        }
        .onAppear { Task { await refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    @ViewBuilder
    private func swipeActions(for item: Item) -> some View {
        Button(role: .destructive) {
            modelContext.delete(item)
            try? modelContext.save()
        } label: {
            Label(item.isFiled ? "Remove" : "Delete", systemImage: "trash")
        }
        if item.isInInbox {
            Button {
                item.archivedAt = .now
                try? modelContext.save()
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.indigo)
        } else if item.isArchived && !item.isFiled {
            Button {
                item.archivedAt = nil
                try? modelContext.save()
            } label: {
                Label("Inbox", systemImage: "tray.and.arrow.up")
            }
            .tint(.blue)
        }
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

