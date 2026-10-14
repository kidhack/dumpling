import CoreLocation
import SwiftUI
import CoreData

/// The Lists tab: user-made groups of items, like everything for a trip.
struct ListsView: View {
    /// Bumped when the user taps the Lists tab while on it; scrolls back to the top.
    var resetToken = 0
    var isActiveTab = true
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(ItemPipeline.self) private var pipeline
    @FetchRequest(sortDescriptors: [SortDescriptor(\ItemList.createdAt)]) private var lists: FetchedResults<ItemList>

    /// The list being edited; .some(nil) creates a new one.
    @State private var editing: EditTarget?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                // One group of plain rows with faint dividers, not a card per list.
                Section {
                    ForEach(lists) { list in
                        NavigationLink(value: list) {
                            ListRow(list: list)
                        }
                        .id(list.id)
                        .plainRow()
                        .contextMenu { listActions(for: list) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(list) } label: {
                                Label(Sharing.isOwner(of: list) ? "Delete" : "Leave",
                                      systemImage: Sharing.isOwner(of: list) ? "trash" : "rectangle.portrait.and.arrow.right")
                            }
                            Button { editing = EditTarget(list: list) } label: {
                                Label("Details", systemImage: "info.circle")
                            }
                            .tint(.gray)
                        }
                    }
                }
            }
            .cardList()
            .screenHeader {
                ScreenHeader {
                    EmptyView()
                } trailing: {
                    Button {
                        editing = EditTarget(list: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .headerGlassCircle()
                    }
                    .accessibilityLabel("New List")
                }
            }
            .overlay {
                if lists.isEmpty {
                    ContentUnavailableView {
                        Label("No Lists", systemImage: "list.bullet")
                    } description: {
                        Text("Group items into lists, like everything for an upcoming trip.")
                    } actions: {
                        Button("New List") { editing = EditTarget(list: nil) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Lists")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ItemList.self) { ListDetailView(list: $0, isActiveTab: isActiveTab) }
            .navigationDestination(for: Item.self) { ItemDetailView(item: $0, filer: pipeline.filer) }
            .sheet(item: $editing) { target in EditListSheet(list: target.list) }
            .onChange(of: resetToken) { _, _ in
                guard let first = lists.first?.id else { return }
                withAnimation(.snappy) { proxy.scrollTo(first, anchor: .top) }
            }
            }
        }
    }

    @ViewBuilder
    private func listActions(for list: ItemList) -> some View {
        if Sharing.isOwner(of: list) {
            Button(Sharing.isShared(list) ? "Manage Sharing…" : "Share List…", systemImage: "person.2") {
                Task { await ShareController.shared.present(list) }
            }
            Button("List Details…", systemImage: "info.circle") { editing = EditTarget(list: list) }
            Button("Delete", systemImage: "trash", role: .destructive) { delete(list) }
        } else {
            Button("List Details…", systemImage: "info.circle") { editing = EditTarget(list: list) }
            Button("Leave List", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { delete(list) }
        }
    }


    private func delete(_ list: ItemList) {
        // Shared lists: the owner's items come back unlisted; someone invited leaves instead.
        Task { await Sharing.delete(list, in: modelContext) }
    }
}

private struct ListRow: View {
    /// Observed so edits (name, icon, color) show without the Lists tab having to reload.
    @ObservedObject var list: ItemList

    var body: some View {
        HStack(spacing: 12) {
            ListIcon(list: list, size: 28)
                .frame(width: 28, height: 22)
            Text(list.name)
                .lineLimit(1)
            if Sharing.isShared(list) {
                Image(systemName: "person.2.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Shared")
            }
            Spacer()
            Text("\(list.itemCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

/// One list's items, newest first like the other tabs.
struct ListDetailView: View {
    @ObservedObject var list: ItemList
    /// False while another tab is showing; leaving the tab puts the map back to the list.
    var isActiveTab = true
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ItemPipeline.self) private var pipeline
    @State private var listPickerItem: Item?
    @State private var showingEdit = false
    @State private var filter: CategoryKind?
    @State private var showingMap = false
    @State private var selectedPin: UUID?
    @State private var showsMapHint = false
    @State private var userLocation: CLLocation?
    /// The big title has scrolled under the header, so the small centered one shows instead.
    @State private var titleScrolledAway = false

    private var canEdit: Bool { Sharing.canEdit(list) }

    /// Newest first; archived items are in Archived, not here.
    private var items: [Item] { list.activeItems.sorted { $0.timestamp > $1.timestamp } }

    private var availableFilters: [CategoryKind] { ItemsBottomControls.filters(for: items, keeping: filter) }

    private var visible: [Item] {
        guard let filter else { return items }
        return items.filter { $0.itemCategory?.rawValue == filter.rawValue }
    }

    var body: some View {
        List {
            // Like a Notes folder: a big title and count at the top that scroll with the items, and give way
            // to the small centered title in the header. Tapping either opens List Details.
            Section {
                Button {
                    showingEdit = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(list.name)
                            .font(.largeTitle.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(list.name), \(subtitle), List Details")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }
            Section {
                ForEach(visible) { item in
                    NavigationLink(value: item) {
                        ItemRowView(item: item, section: item.isArchived ? .archived : item.isFiled ? .filed : .inbox)
                    }
                    .plainRow()
                    // The same swipes as in the sections; not on lists shared view-only.
                    .swipeActions(edge: .trailing) {
                        if canEdit { ItemTrailingSwipeActions(item: item) }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if canEdit {
                            ItemLeadingSwipeActions(item: item, filer: pipeline.filer) { listPickerItem = item }
                        }
                    }
                }
            }
        }
        .cardList()
        // Pull down past the top to add an item to this list, as in the Inbox (not on lists shared view-only).
        .pullToAdd(enabled: !showingMap && canEdit, list: list)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > 48
        } action: { _, away in
            titleScrolledAway = away
        }
        // As in the sections: on the map, the header and bottom controls are plain insets on the map.
        .overlay {
            if showingMap {
                ItemsMapView(items: visible, selection: $selectedPin, userLocation: $userLocation)
                    .safeAreaInset(edge: .top, spacing: 0) { header.padding(.bottom, ScreenHeaderSpacing.bottom) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
                    .transition(.opacity)
            }
        }
        .scrollEdgeEffectHidden(showingMap, for: .all)
        .screenHeader(hidden: showingMap) { header }
        .safeAreaBar(edge: .bottom) {
            if !items.isEmpty && !showingMap { bottomControls }
        }
        .animation(.easeInOut(duration: 0.25), value: showingMap)
        // The map is only for places: any other filter, or leaving the tab, goes back to the list.
        .onChange(of: ItemsBottomControls.showsMap(filter: filter, available: availableFilters)) { _, shows in
            if !shows { showingMap = false }
        }
        .onChange(of: isActiveTab) { _, active in
            if !active { showingMap = false }
        }
        .onChange(of: showingMap) { _, shown in
            if !shown { selectedPin = nil }
        }
        .overlay {
            if visible.isEmpty {
                if let filter, !items.isEmpty {
                    ContentUnavailableView("No \(filter.label) Items", systemImage: filter.systemImage)
                } else {
                    ContentUnavailableView("Empty List", systemImage: "list.bullet",
                                           description: Text("Pull down to add an item, or swipe right on an Inbox item to move it here. Items removed from a list go back to the Inbox."))
                }
            }
        }
        .navigationTitle(list.name)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingEdit) { EditListSheet(list: list, onLeave: { dismiss() }) }
        .sheet(item: $listPickerItem) { ListPickerSheet(items: [$0]) }
    }

    private var bottomControls: some View {
        ItemsBottomControls(visible: visible, filter: $filter, available: availableFilters,
                            showingMap: $showingMap, showsMapHint: $showsMapHint,
                            selectedPin: selectedPin, userLocation: userLocation)
    }

    /// "20 items", plus who it's shared with when it is.
    private var subtitle: String {
        let count = items.count == 1 ? "1 item" : "\(items.count) items"
        return Sharing.isShared(list) ? "Shared · \(count)" : count
    }

    private var header: some View {
        ScreenHeader {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .headerGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Lists")
        } trailing: {
            Menu {
                if Sharing.isOwner(of: list) {
                    Button(Sharing.isShared(list) ? "Manage Sharing…" : "Share List…",
                           systemImage: Sharing.isShared(list) ? "person.2" : "person.crop.circle.badge.plus") {
                        Task { await ShareController.shared.present(list) }
                    }
                    Button("List Details…", systemImage: "info.circle") { showingEdit = true }
                    Button("Delete List", systemImage: "trash", role: .destructive) {
                        dismiss()
                        Task { await Sharing.delete(list, in: modelContext) }
                    }
                } else {
                    Button("List Details…", systemImage: "info.circle") { showingEdit = true }
                    Button("Leave List", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        dismiss()
                        Task { await Sharing.leave(list) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .headerGlassCircle()
            }
            .accessibilityLabel("List Options")
        }
        // Like a Notes folder: the name centered, plain, with a count under it. Tapping it opens List Details.
        .overlay {
            Button {
                showingEdit = true
            } label: {
                VStack(spacing: 1) {
                    Text(list.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: 220)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .opacity(titleScrolledAway || showingMap ? 1 : 0)
            .allowsHitTesting(titleScrolledAway || showingMap)
            .animation(.easeOut(duration: 0.15), value: titleScrolledAway)
            .accessibilityLabel("\(list.name), \(subtitle), List Details")
        }
    }
}

/// Which list the Edit List sheet is for; `list == nil` creates one.
struct EditTarget: Identifiable {
    let list: ItemList?
    var id: String { list?.objectID.uriRepresentation().absoluteString ?? "new" }
}
