import SwiftUI
import CoreData

/// Name, color and icon for a list, like Reminders' List Info. Pass nil to create a new list.
struct EditListSheet: View {
    let list: ItemList?

    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: ListColor = .teal
    @State private var symbol = ListSymbols.defaultSymbol
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private let symbolColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
    private let colorColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ListIcon(symbol: symbol, color: color.color, size: 88)
                        .shadow(color: color.color.opacity(0.4), radius: 10, y: 4)
                        .padding(.top, 8)

                    TextField("List Name", text: $name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12)
                        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                        .focused($nameFocused)
                        .submitLabel(.done)

                    LazyVGrid(columns: colorColumns, spacing: 10) {
                        ForEach(ListColor.allCases) { option in
                            Button { color = option } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        if option == color {
                                            Circle().strokeBorder(Color(.systemBackground), lineWidth: 3)
                                                .padding(3)
                                        }
                                    }
                                    .overlay {
                                        if option == color { Circle().strokeBorder(option.color, lineWidth: 2) }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.rawValue.capitalized)
                            .accessibilityAddTraits(option == color ? .isSelected : [])
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))

                    LazyVGrid(columns: symbolColumns, spacing: 10) {
                        ForEach(ListSymbols.all, id: \.self) { option in
                            Button { symbol = option } label: {
                                Image(systemName: option)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(option == symbol ? .white : .primary)
                                    .frame(width: 40, height: 40)
                                    .background(option == symbol ? color.color : Color(.tertiarySystemFill), in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(option == symbol ? .isSelected : [])
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(list == nil ? "New List" : "Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save).disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                if let list {
                    name = list.name
                    color = list.listColor
                    symbol = list.symbol
                } else {
                    nameFocused = true
                }
            }
        }
    }

    private func save() {
        let target: ItemList
        if let list {
            target = list
        } else {
            target = ItemList(context: modelContext, name: trimmedName)
            Persistence.shared.assignToPrivateStore(target)
        }
        target.name = trimmedName
        target.colorName = color.rawValue
        target.symbolName = symbol
        try? modelContext.save()
        dismiss()
    }
}
