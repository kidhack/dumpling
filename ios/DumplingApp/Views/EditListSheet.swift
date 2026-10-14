import CloudKit
import CoreData
import SwiftUI

/// List Details: name, color, icon and who it's shared with, like Reminders' List Info.
/// Pass nil to create a new list.
struct EditListSheet: View {
    let list: ItemList?
    /// Called after leaving a shared list, so the screen showing it can close.
    var onLeave: () -> Void = {}

    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: ListColor = .teal
    @State private var symbol = ListSymbols.defaultSymbol
    @FocusState private var nameFocused: Bool
    @State private var search = ""

    /// Matches icon tags, section names and the symbol's own name, so "coffee" or "hotel" work.
    private var searchResults: [ListSymbols.Symbol] {
        let terms = search.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        return ListSymbols.sections.flatMap { section in
            section.symbols.filter { symbol in
                // Match word starts, so "rain" finds rain and rainbow but not train or brain.
                let words = "\(symbol.keywords) \(section.title) \(symbol.name.replacingOccurrences(of: ".", with: " "))"
                    .lowercased().split(separator: " ")
                return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// People invited without edit access can look but not change anything.
    private var canEdit: Bool { list.map(Sharing.canEdit) ?? true }
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
                        .disabled(!canEdit)

                    if let list {
                        membersSection(list)
                    }

                    Group {
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

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search icons", text: $search)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            if !search.isEmpty {
                                Button { search = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("Clear Search")
                            }
                        }
                        .padding(10)
                        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))

                        if search.isEmpty {
                            ForEach(ListSymbols.sections) { section in
                                Text(section.title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                symbolGrid(section.symbols)
                            }
                        } else if searchResults.isEmpty {
                            Text("No icons match “\(search)”")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else {
                            symbolGrid(searchResults)
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                    }
                    .disabled(!canEdit)
                    .opacity(canEdit ? 1 : 0.5)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(list == nil ? "New List" : "List Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if canEdit { Button("Cancel") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if canEdit {
                        Button("Done", action: save).disabled(trimmedName.isEmpty)
                    } else {
                        Button("Close") { dismiss() }
                    }
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

    // MARK: - Members

    private func membersSection(_ list: ItemList) -> some View {
        let people = Sharing.participants(of: list)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Shared With")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            if people.isEmpty {
                Text("Only you. Share this list to plan it with others.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(people, id: \.self) { person in
                    MemberRow(person: person, isYou: Sharing.isCurrentUser(person, in: list))
                }
            }

            if Sharing.isOwner(of: list) {
                Button {
                    Task { await ShareController.shared.present(list) }
                } label: {
                    Label(people.isEmpty ? "Share List…" : "Manage Sharing…", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button(role: .destructive) {
                    dismiss()
                    onLeave()
                    Task { await Sharing.leave(list) }
                } label: {
                    Label("Leave List", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func symbolGrid(_ symbols: [ListSymbols.Symbol]) -> some View {
        LazyVGrid(columns: symbolColumns, spacing: 10) {
            ForEach(symbols, id: \.name) { option in
                Button { symbol = option.name } label: {
                    Image(systemName: option.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(option.name == symbol ? .white : .primary)
                        .frame(width: 40, height: 40)
                        .background(option.name == symbol ? color.color : Color(.tertiarySystemFill), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.keywords.components(separatedBy: " ").first ?? option.name)
                .accessibilityAddTraits(option.name == symbol ? .isSelected : [])
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

/// One person on a shared list: initials, name, and their role or invite status.
private struct MemberRow: View {
    let person: CKShare.Participant
    let isYou: Bool

    private var name: String { Sharing.displayName(person) }

    private var initials: String {
        if let components = person.userIdentity.nameComponents {
            let short = PersonNameComponentsFormatter.localizedString(from: components, style: .abbreviated)
            if !short.isEmpty { return short }
        }
        return String(name.prefix(1)).uppercased()
    }

    private var role: String {
        if person.role == .owner { return "Owner" }
        if person.acceptanceStatus == .pending { return "Invited" }
        return person.permission == .readWrite ? "Can edit" : "View only"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(initials)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(isYou ? "\(name) (You)" : name)
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}
