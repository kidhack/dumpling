import SwiftUI
import CoreData

/// Items to move, as one value, so the sheet opens with them already set.
struct ListPickerRequest: Identifiable {
    let id = UUID()
    let items: [Item]
}

/// Moves one or more items into a list, or out of their list. Can create a list on the way.
struct ListPickerSheet: View {
    let items: [Item]
    var onDone: () -> Void = {}

    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [SortDescriptor(\ItemList.createdAt)]) private var lists: FetchedResults<ItemList>
    @State private var showingNewList = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingNewList = true
                    } label: {
                        Label("New List", systemImage: "plus")
                            .foregroundStyle(Color(.label))
                    }
                }
                if !lists.isEmpty {
                    Section {
                        ForEach(lists) { list in
                            Button {
                                move(to: list)
                            } label: {
                                HStack(spacing: 12) {
                                    ListIcon(list: list, size: 26)
                                    Text(list.name)
                                        .foregroundStyle(Color(.label))
                                    Spacer()
                                    if isIn(list) {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
                if items.contains(where: { $0.list != nil }) {
                    Section {
                        Button("Remove from List", role: .destructive) { move(to: nil) }
                    }
                }
            }
            .navigationTitle(items.count == 1 ? "Move to List" : "Move \(items.count) Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .listNameAlert("New List", isPresented: $showingNewList) { name in
                let list = ItemList(context: modelContext, name: name)
                Persistence.shared.assignToPrivateStore(list)
                move(to: list)
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Checked when every item being moved is already in the list (and there is at least one).
    private func isIn(_ list: ItemList) -> Bool {
        !items.isEmpty && items.allSatisfy { $0.list?.objectID == list.objectID }
    }

    private func move(to list: ItemList?) {
        let moving = items
        onDone()
        dismiss()
        // Shared lists may need items copied into their share zone, so this goes through Sharing.
        Task {
            for item in moving { await Sharing.move(item, to: list, in: modelContext) }
            try? modelContext.save()
        }
    }
}

extension View {
    /// An alert with a name field, for creating or renaming a list.
    func listNameAlert(_ title: String, isPresented: Binding<Bool>, initialName: String = "",
                       action: @escaping (String) -> Void) -> some View {
        modifier(ListNameAlert(title: title, isPresented: isPresented, initialName: initialName, action: action))
    }
}

private struct ListNameAlert: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let initialName: String
    let action: (String) -> Void
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { action(trimmed) }
                }
            }
            .onChange(of: isPresented) { _, shown in
                if shown { name = initialName }
            }
    }
}
