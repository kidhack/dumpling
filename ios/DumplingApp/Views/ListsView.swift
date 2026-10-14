import SwiftUI
import CoreData

/// The Lists tab: user-made groups of items, like everything for a trip.
struct ListsView: View {
    /// Bumped when the user taps the Lists tab while on it; scrolls back to the top.
    var resetToken = 0
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
                                Label("Edit", systemImage: "pencil")
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
            .navigationDestination(for: ItemList.self) { ListDetailView(list: $0) }
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
            Button("Edit List…", systemImage: "pencil") { editing = EditTarget(list: list) }
            Button("Delete", systemImage: "trash", role: .destructive) { delete(list) }
        } else {
            Button("Leave List", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { delete(list) }
        }
    }


    private func delete(_ list: ItemList) {
        // Shared lists: the owner's items come back unlisted; someone invited leaves instead.
        Task { await Sharing.delete(list, in: modelContext) }
    }
}

private struct ListRow: View {
    let list: ItemList

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
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false

    private var items: [Item] { list.itemsArray.sorted { $0.timestamp > $1.timestamp } }

    var body: some View {
        List {
            ForEach(items) { item in
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
        .screenHeader {
            ScreenHeader {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
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
                .padding(.leading, -8)
                .accessibilityLabel("Back to Lists")
            } trailing: {
                Menu {
                    if Sharing.isOwner(of: list) {
                        Button(Sharing.isShared(list) ? "Manage Sharing…" : "Share List…",
                               systemImage: Sharing.isShared(list) ? "person.2" : "person.crop.circle.badge.plus") {
                            Task { await ShareController.shared.present(list) }
                        }
                        Button("Edit List…", systemImage: "pencil") { showingEdit = true }
                        Button("Delete List", systemImage: "trash", role: .destructive) {
                            dismiss()
                            Task { await Sharing.delete(list, in: modelContext) }
                        }
                    } else {
                        if Sharing.canEdit(list) {
                            Button("Edit List…", systemImage: "pencil") { showingEdit = true }
                        }
                        Button("Leave List", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            dismiss()
                            Task { await Sharing.leave(list) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("List Options")
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Empty List", systemImage: "list.bullet",
                                       description: Text("Swipe right on an Inbox item, or open it, to move it here. Items removed from a list go back to the Inbox."))
            }
        }
        .navigationTitle(list.name)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingEdit) { EditListSheet(list: list) }
    }
}

/// Which list the Edit List sheet is for; `list == nil` creates one.
struct EditTarget: Identifiable {
    let list: ItemList?
    var id: String { list?.objectID.uriRepresentation().absoluteString ?? "new" }
}
