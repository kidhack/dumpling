import SwiftUI
import SwiftData
import FoundationModels

enum ItemsSection: String, CaseIterable, Identifiable {
    case inbox = "Inbox", filed = "Filed", archived = "Archived"
    var id: Self { self }

    var systemImage: String {
        switch self {
        case .inbox: return "tray"
        case .filed: return "calendar.badge.checkmark"
        case .archived: return "archivebox"
        }
    }

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
    let section: ItemsSection
    @Environment(\.modelContext) private var modelContext
    @Environment(ItemPipeline.self) private var pipeline
    /// Oldest first, so the newest item sits at the bottom, near your thumb.
    @Query(sort: \Item.timestamp) private var items: [Item]

    @State private var bottomPadding: CGFloat = 0
    @State private var pull: CGFloat = 0
    @State private var addTriggered = false
    @State private var showingNewItem = false
    @State private var lastSpacerChange = Date.distantPast
    private let addThreshold: CGFloat = 70

    private var visible: [Item] { items.filter(section.contains) }

    var body: some View {
        NavigationStack {
            List {
                // List ignores bottom alignment, so a clear spacer pushes short lists down onto the tab bar.
                // It gets its own section so it never touches the first card's corners.
                if !visible.isEmpty && bottomPadding > 0 {
                    Section {
                        Color.clear
                            .frame(height: bottomPadding)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                }
                // One section per item so each is its own card.
                ForEach(visible) { item in
                    Section {
                        NavigationLink(value: item) {
                            ItemRowView(item: item, section: section)
                        }
                        .swipeActions(edge: .trailing) { swipeActions(for: item) }
                    }
                }
            }
            .listSectionSpacing(10)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.containerSize.height - geo.contentInsets.top - geo.contentInsets.bottom - geo.contentSize.height
            } action: { _, free in
                // `free` is measured with the current spacer included; solve for the spacer that fills it.
                let target = max(0, bottomPadding + free)
                if abs(target - bottomPadding) > 0.5 {
                    bottomPadding = target
                    lastSpacerChange = .now
                }
            }
            // Pull up past the newest item to add one (Inbox only). List doesn't report scroll phases
            // for this bounce, so like pull-to-refresh it triggers on crossing the threshold, not on release.
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.containerSize.height - geo.contentInsets.bottom - geo.contentSize.height
            } action: { _, overscroll in
                guard section == .inbox else { return }
                // While the bottom spacer resizes, the list briefly reads as stretched; that isn't a pull.
                guard Date.now.timeIntervalSince(lastSpacerChange) > 0.3 else { pull = 0; return }
                pull = max(0, overscroll)
                if pull >= addThreshold && !addTriggered {
                    addTriggered = true
                    showingNewItem = true
                } else if pull < 10 {
                    addTriggered = false
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: addTriggered) { _, triggered in triggered }
            .overlay(alignment: .bottom) {
                if section == .inbox && pull > 4 {
                    NewCardHint(progress: min(pull / addThreshold, 1), armed: addTriggered)
                        .frame(height: max(0, min(pull - 10, 76)))
                }
            }
            .accessibilityActions {
                if section == .inbox {
                    Button("Add Item") { showingNewItem = true }
                }
            }
            .sheet(isPresented: $showingNewItem) { NewItemView() }
            // Long lists open at the newest item and stay there as items arrive.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .safeAreaInset(edge: .top) {
                if section == .inbox, let reason = pipeline.modelUnavailable {
                    ModelUnavailableBanner(reason: reason)
                        .padding(.bottom, 4)
                }
            }
            .navigationTitle(section.rawValue)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Item.self) { ItemDetailView(item: $0, filer: pipeline.filer) }
            .overlay {
                if visible.isEmpty {
                    ContentUnavailableView(section.emptyTitle, systemImage: section.systemImage,
                                           description: Text(section.emptyMessage))
                }
            }
        }
        .onAppear { Task { await pipeline.refresh(modelContext) } }
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

}

// MARK: - Row

struct ItemRowView: View {
    let item: Item
    let section: ItemsSection

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(item: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .lineLimit(2)

                if let note = item.userNote,
                   note.caseInsensitiveCompare(item.displayTitle) != .orderedSame {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // "Kept" is the normal state for unfiled items, so only show where filed items went and problems.
                if item.status == "failed" {
                    Label(item.statusLabel, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if item.status != "kept" {
                    Text(item.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
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

/// A new card edging in below the newest item while the user pulls up. Solid once releasing will add.
private struct NewCardHint: View {
    let progress: CGFloat
    let armed: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(armed ? Color(.secondarySystemGroupedBackground) : .clear)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.secondary.opacity(armed ? 0 : 0.6 * progress),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(armed ? .primary : .secondary)
                .opacity(progress)
                .scaleEffect(0.6 + 0.4 * progress)
        }
        .padding(.horizontal, 16)
        .animation(.snappy(duration: 0.15), value: armed)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
