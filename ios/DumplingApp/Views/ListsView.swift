import CoreLocation
import SwiftUI
import CoreData

/// The Lists tab: user-made groups of items, like everything for a trip.
/// The Lists screen, like Mail's mailboxes: the built-in lists as tiles (Inbox, Favorites, Saved, Archive), then
/// the user's lists. The app opens on the Inbox, one step in; its back arrow comes here.
struct ListsView: View {
    /// The app's navigation path, for the tiles (links in a list row get a stray disclosure arrow each).
    @Binding var path: NavigationPath
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(ItemPipeline.self) private var pipeline
    @FetchRequest(sortDescriptors: [SortDescriptor(\ItemList.createdAt)]) private var lists: FetchedResults<ItemList>
    /// For the tiles' counts.
    @FetchRequest(sortDescriptors: []) private var allItems: FetchedResults<Item>

    /// The list being edited; .some(nil) creates a new one.
    @State private var editing: EditTarget?
    @State private var showingAbout = false
    @State private var showingSettings = false

    private let tileColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: tileColumns, spacing: 10) {
                    ForEach(ItemsSection.allCases) { section in
                        Button {
                            path.append(section)
                        } label: {
                            SectionTile(section: section, count: allItems.filter(section.contains).count)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }
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
                if lists.isEmpty {
                    Button("New List", systemImage: "plus") { editing = EditTarget(list: nil) }
                        .plainRow()
                }
            } header: {
                Text("My Lists")
                    .font(.title3.bold())
                    .foregroundStyle(Color(.label))
                    .textCase(nil)
                    .padding(.leading, -16)
            }
        }
        .cardList()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("New List", systemImage: "plus") { editing = EditTarget(list: nil) }
                Menu {
                    Button("About", systemImage: "info.circle") { showingAbout = true }
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                } label: {
                    Label("Menu", systemImage: "ellipsis")
                }
            }
        }
        .navigationTitle("Dumpling")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editing) { target in EditListSheet(list: target.list) }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
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
    /// Fetched so the count drops as soon as an item is archived (the list itself doesn't change then).
    @FetchRequest private var activeItems: FetchedResults<Item>

    init(list: ItemList) {
        self.list = list
        _activeItems = FetchRequest(sortDescriptors: [],
                                    predicate: NSPredicate(format: "list == %@ AND archivedAt == nil", list))
    }

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
            Text("\(activeItems.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

/// One list's items, newest first like the other tabs.
struct ListDetailView: View {
    @ObservedObject var list: ItemList
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

    private var canEdit: Bool { Sharing.canEdit(list) }

    /// The list's items that aren't archived, newest first. Fetched rather than read from `list`: the list only
    /// changes when items join or leave it, so archiving an item didn't take it off the screen.
    @FetchRequest private var fetchedItems: FetchedResults<Item>

    init(list: ItemList) {
        self.list = list
        _fetchedItems = FetchRequest(sortDescriptors: [SortDescriptor(\Item.timestamp, order: .reverse)],
                                     predicate: NSPredicate(format: "list == %@ AND archivedAt == nil", list))
    }

    private var items: [Item] { Array(fetchedItems) }

    private var availableFilters: [CategoryKind] { ItemsBottomControls.filters(for: items, keeping: filter) }

    private var visible: [Item] {
        guard let filter else { return items }
        return items.filter { $0.itemCategory?.rawValue == filter.rawValue }
    }

    var body: some View {
        List {
            Section {
                ForEach(visible) { item in
                    NavigationLink(value: item) {
                        ItemRowView(item: item, section: item.isInArchive ? .archived : item.isSavedForLater ? .saved : .inbox)
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
        // As in the sections: on the map, the bottom controls are a plain inset on the map.
        .overlay {
            if showingMap {
                ItemsMapView(items: visible, selection: $selectedPin, userLocation: $userLocation)
                    .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
                    .transition(.opacity)
            }
        }
        .scrollEdgeEffectHidden(showingMap, for: .all)
        .safeAreaBar(edge: .bottom) {
            if !items.isEmpty && !showingMap { bottomControls }
        }
        .animation(.easeInOut(duration: 0.25), value: showingMap)
        // The map is only for places: any other filter goes back to the list.
        .onChange(of: ItemsBottomControls.showsMap(filter: filter, available: availableFilters)) { _, shows in
            if !shows { showingMap = false }
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
        // Like a Reminders list: a large title (small over the map) with its count, and a title menu.
        .navigationTitle(list.name)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(showingMap ? .inline : .large)
        .toolbarTitleMenu {
            Button("List Details…", systemImage: "info.circle") { showingEdit = true }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { listMenu }
        }
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

    private var listMenu: some View {
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
            Label("List Options", systemImage: "ellipsis")
        }
    }
}

/// A built-in list's tile, like Reminders' smart lists: icon, count and name.
private struct SectionTile: View {
    let section: ItemsSection
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CenteredSymbol(name: section.systemImage, side: 16)
                    .foregroundStyle(.readable(on: section.tint))
                    .frame(width: 32, height: 32)
                    .background(section.tint, in: .circle)
                Spacer()
                Text("\(count)")
                    .font(.title2.bold())
                    .monospacedDigit()
            }
            Text(section.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.rawValue), \(count)")
    }
}

/// Which list the Edit List sheet is for; `list == nil` creates one.
struct EditTarget: Identifiable {
    let list: ItemList?
    var id: String { list?.objectID.uriRepresentation().absoluteString ?? "new" }
}
