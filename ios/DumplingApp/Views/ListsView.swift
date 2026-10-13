import SwiftUI
import SwiftData

/// The Lists tab: user-made groups of items, like everything for a trip.
struct ListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ItemPipeline.self) private var pipeline
    @Query(sort: \ItemList.createdAt) private var lists: [ItemList]

    @State private var showingNewList = false
    @State private var renaming: ItemList?
    @State private var showingRename = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(lists) { list in
                    Section {
                        NavigationLink(value: list) {
                            ListRow(list: list)
                        }
                        .contextMenu { listActions(for: list) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(list) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { startRenaming(list) } label: {
                                Label("Rename", systemImage: "pencil")
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
                        showingNewList = true
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
                        Button("New List") { showingNewList = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Lists")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ItemList.self) { ListDetailView(list: $0) }
            .navigationDestination(for: Item.self) { ItemDetailView(item: $0, filer: pipeline.filer) }
            .listNameAlert("New List", isPresented: $showingNewList) { name in
                modelContext.insert(ItemList(name: name))
                try? modelContext.save()
            }
            .listNameAlert("Rename List", isPresented: $showingRename, initialName: renaming?.name ?? "") { name in
                renaming?.name = name
                try? modelContext.save()
            }
        }
    }

    @ViewBuilder
    private func listActions(for list: ItemList) -> some View {
        Button("Rename", systemImage: "pencil") { startRenaming(list) }
        Button("Delete", systemImage: "trash", role: .destructive) { delete(list) }
    }

    private func startRenaming(_ list: ItemList) {
        renaming = list
        showingRename = true
    }

    private func delete(_ list: ItemList) {
        modelContext.delete(list)
        try? modelContext.save()
    }
}

private struct ListRow: View {
    let list: ItemList

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.title3)
                .foregroundStyle(.teal)
                .frame(width: 28)
            Text(list.name)
                .lineLimit(1)
            Spacer()
            Text("\(list.items?.count ?? 0)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

/// One list's items, newest first like the other tabs.
struct ListDetailView: View {
    @Bindable var list: ItemList
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingRename = false

    private var items: [Item] { (list.items ?? []).sorted { $0.timestamp > $1.timestamp } }

    var body: some View {
        List {
            ForEach(items) { item in
                Section {
                    NavigationLink(value: item) {
                        ItemRowView(item: item, section: item.isArchived ? .archived : item.isFiled ? .filed : .inbox)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            item.list = nil
                            try? modelContext.save()
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
                    Button("Rename", systemImage: "pencil") { showingRename = true }
                    Button("Delete List", systemImage: "trash", role: .destructive) {
                        modelContext.delete(list)
                        try? modelContext.save()
                        dismiss()
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
        .listNameAlert("Rename List", isPresented: $showingRename, initialName: list.name) { name in
            list.name = name
            try? modelContext.save()
        }
    }
}
