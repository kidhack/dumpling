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
    @State private var isDragging = false
    @State private var addArmed = false
    @State private var showingNewItem = false
    @State private var showingAbout = false
    @State private var showingSettings = false
    private let addThreshold: CGFloat = 100

    @State private var filter: CategoryKind?

    private var inSection: [Item] { items.filter(section.contains) }

    private var visible: [Item] {
        guard let filter else { return inSection }
        return inSection.filter { $0.category == filter.rawValue }
    }

    /// Categories present in this tab, plus the selected one so it doesn't vanish while chosen.
    private var availableFilters: [CategoryKind] {
        let present = Set(inSection.compactMap(\.category))
        return CategoryKind.allCases.filter { present.contains($0.rawValue) || $0 == filter }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                        .id(item.id)
                        .swipeActions(edge: .trailing) { swipeActions(for: item) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) { fileActions(for: item) }
                    }
                }
            }
            .listSectionSpacing(10)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.containerSize.height - geo.contentInsets.top - geo.contentInsets.bottom - geo.contentSize.height
            } action: { _, free in
                // `free` is measured with the current spacer included; solve for the spacer that fills it.
                let target = max(0, bottomPadding + free)
                if abs(target - bottomPadding) > 0.5 { bottomPadding = target }
            }
            // Pull up past the newest item to add one (Inbox only). Only real drags count: layout changes
            // (launch, the bottom spacer settling, a sheet closing) also briefly read as overscroll.
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.containerSize.height - geo.contentInsets.bottom - geo.contentSize.height
            } action: { _, overscroll in
                guard section == .inbox else { return }
                pull = max(0, overscroll)
                if isDragging { addArmed = pull >= addThreshold }
            }
            .background {
                if section == .inbox {
                    ScrollTouchReader { dragging in
                        isDragging = dragging
                        if !dragging {
                            if addArmed { showingNewItem = true }
                            addArmed = false
                        }
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: addArmed) { _, armed in armed }
            .overlay(alignment: .bottom) {
                if section == .inbox && isDragging && pull > 4 {
                    NewCardHint(progress: min(pull / addThreshold, 1), armed: addArmed,
                                reveal: max(0, min(pull - 16, 80)))
                        .padding(.bottom, 12)
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
                if section == .inbox {
                    VStack(spacing: 8) {
                        header
                        if let reason = pipeline.modelUnavailable {
                            ModelUnavailableBanner(reason: reason)
                        }
                    }
                    .padding(.bottom, 4)
                    // Fade cards out as they scroll up beneath the header.
                    .background {
                        LinearGradient(stops: [.init(color: Color(.systemGroupedBackground), location: 0.6),
                                               .init(color: Color(.systemGroupedBackground).opacity(0), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .padding(.bottom, -16)
                            .ignoresSafeArea(edges: .top)
                    }
                }
            }
            .sheet(isPresented: $showingAbout) { AboutView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .navigationTitle(section.rawValue)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Item.self) { ItemDetailView(item: $0, filer: pipeline.filer) }
            .overlay {
                if visible.isEmpty {
                    if let filter, !inSection.isEmpty {
                        ContentUnavailableView("No \(filter.label) Items", systemImage: filter.systemImage)
                    } else {
                        ContentUnavailableView(section.emptyTitle, systemImage: section.systemImage,
                                               description: Text(section.emptyMessage))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !inSection.isEmpty {
                    CategoryFilterBar(selection: $filter, available: availableFilters)
                }
            }
            // List ignores defaultScrollAnchor for long lists, so jump to the newest card explicitly.
            .task {
                // The rows aren't laid out on the first pass, so scroll once they are.
                for delay in [50, 300] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    scrollToNewest(proxy, animated: false)
                }
            }
            .onChange(of: visible.last?.id) { _, _ in scrollToNewest(proxy, animated: true) }
            }
        }
        .onAppear { Task { await pipeline.refresh(modelContext) } }
    }

    private func scrollToNewest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = visible.last?.id else { return }
        // Let the list lay out the new rows first.
        DispatchQueue.main.async {
            if animated {
                withAnimation(.snappy) { proxy.scrollTo(last, anchor: .bottom) }
            } else {
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Dumpling")
                .font(.title2.bold())
            Spacer()
            Menu {
                Button("About", systemImage: "info.circle") { showingAbout = true }
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
            } label: {
                MenuTwoLineIcon()
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Menu")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
    }

    /// Swipe right to file: keep it, or send it to Reminders or Calendar.
    @ViewBuilder
    private func fileActions(for item: Item) -> some View {
        if !item.isFiled {
            Button {
                item.saveForLater()
                try? modelContext.save()
            } label: {
                Label("Save for Later", systemImage: "bookmark")
            }
            .tint(.indigo)
            Button {
                Task {
                    await Processor.fileNow(item, as: .task, filer: pipeline.filer)
                    try? modelContext.save()
                }
            } label: {
                Label("Reminders", systemImage: CategoryKind.task.systemImage)
            }
            .tint(CategoryKind.task.tint)
            if item.relevantDate != nil {
                Button {
                    Task {
                        await Processor.fileNow(item, as: .event, filer: pipeline.filer)
                        try? modelContext.save()
                    }
                } label: {
                    Label("Calendar", systemImage: CategoryKind.event.systemImage)
                }
                .tint(CategoryKind.event.tint)
            }
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

/// A new card edging up from behind a fade below the newest item while the user pulls.
/// Only its top shows; it turns solid once releasing will add.
private struct NewCardHint: View {
    let progress: CGFloat
    let armed: Bool
    /// How much of the card has emerged, in points.
    let reveal: CGFloat

    private let cardHeight: CGFloat = 64

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
        .frame(height: cardHeight)
        .padding(.horizontal, 16)
        // Show only the emerged top of the card, fading out toward the bottom edge.
        .frame(height: reveal, alignment: .top)
        .clipped()
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(.snappy(duration: 0.15), value: armed)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Two-line menu icon (after Hugeicons "menu-two-line"); SF Symbols only has a three-line one.
private struct MenuTwoLineIcon: View {
    var body: some View {
        VStack(spacing: 6) {
            Capsule().frame(width: 20, height: 2.5)
            Capsule().frame(width: 20, height: 2.5)
        }
        .foregroundStyle(.primary)
    }
}
