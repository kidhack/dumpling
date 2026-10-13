import SwiftUI
import CoreData

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
                    }
                }
                if !lists.isEmpty {
                    Section {
                        ForEach(lists) { list in
                            Button {
                                move(to: list)
                            } label: {
                                HStack {
                                    Label(list.name, systemImage: "list.bullet")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if items.allSatisfy({ $0.list?.id == list.id }) {
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
