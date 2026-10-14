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
                ForEach(lists) { list in
                    Section {
                        NavigationLink(value: list) {
                            ListRow(list: list)
                        }
                        .id(list.id)
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
            .listSectionSpacing(10)
            .screenHeader {
                ScreenHeader {
                    EmptyView()
                } trailing: {
                    Button {
                        editing = EditTarget(list: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
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
    @State private var showingEdit = false
    @State private var filter: CategoryKind?
    @State private var showingMap = false
    @State private var selectedPin: UUID?
    @State private var userLocation: CLLocation?

    private var items: [Item] { list.itemsArray.sorted { $0.timestamp > $1.timestamp } }

    private var visible: [Item] {
        guard let filter else { return items }
        return items.filter { $0.category == filter.rawValue }
    }

    var body: some View {
        List {
            ForEach(visible) { item in
                Section {
                    NavigationLink(value: item) {
                        ItemRowView(item: item, section: item.isArchived ? .archived : item.isFiled ? .filed : .inbox)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task {
                                await Sharing.move(item, to: nil, in: modelContext)
                                try? modelContext.save()
                            }
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                        .tint(.gray)
                    }
                }
            }
        }
        .listSectionSpacing(10)
        // As in the sections: on the map, the header and bottom controls are plain insets on the map.
        .overlay {
            if showingMap {
                ItemsMapView(items: visible, selection: $selectedPin, userLocation: $userLocation)
                    .safeAreaInset(edge: .top, spacing: 0) { header.padding(.bottom, 4) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
                    .transition(.opacity)
            }
        }
        .scrollEdgeEffectHidden(showingMap, for: .all)
        .screenHeader {
            if !showingMap { header }
        }
        .safeAreaBar(edge: .bottom) {
            if !items.isEmpty && !showingMap { bottomControls }
        }
        .animation(.easeInOut(duration: 0.25), value: showingMap)
        // The map is only for places: any other filter, or leaving the tab, goes back to the list.
        .onChange(of: filter) { _, new in
            if new != .location { showingMap = false }
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
                                           description: Text("Swipe right on an Inbox item, or open it, to move it here. Items removed from a list go back to the Inbox."))
                }
            }
        }
        .navigationTitle(list.name)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingEdit) { EditListSheet(list: list, onLeave: { dismiss() }) }
    }

    private var bottomControls: some View {
        ItemsBottomControls(visible: visible, filter: $filter,
                            available: ItemsBottomControls.filters(for: items, keeping: filter),
                            showingMap: $showingMap, selectedPin: selectedPin, userLocation: userLocation)
    }

    private var header: some View {
        ScreenHeader {
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 28, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Lists")
                // Tapping the list's name opens its details.
                Button {
                    showingEdit = true
                } label: {
                    HStack(spacing: 8) {
                        ListIcon(list: list, size: 30)
                        Text(list.name)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(list.name), List Details")
            }
            // Over the map, on glass so it reads against streets and labels.
            .padding(.trailing, showingMap ? 14 : 0)
            .padding(.leading, showingMap ? 6 : 0)
            .glassEffect(showingMap ? .regular : .identity, in: .capsule)
            .padding(.leading, showingMap ? -14 : -8)
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
                    .frame(width: 44, height: 44)
                    .glassEffect(showingMap ? .regular : .identity, in: .circle)
                    .contentShape(.rect)
            }
            .accessibilityLabel("List Options")
        }
    }
}

/// Which list the Edit List sheet is for; `list == nil` creates one.
struct EditTarget: Identifiable {
    let list: ItemList?
    var id: String { list?.objectID.uriRepresentation().absoluteString ?? "new" }
}
