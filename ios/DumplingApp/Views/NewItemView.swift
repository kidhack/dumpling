import SwiftUI
import CoreData

/// Adds an item without the share sheet. It's sorted like a shared item. With `list`, it goes into that list.
struct NewItemView: View {
    var list: ItemList?

    @Environment(\.managedObjectContext) private var modelContext
    @Environment(ItemPipeline.self) private var pipeline
    @Environment(\.dismiss) private var dismiss

    @State private var content = ""
    @State private var note = ""
    @State private var category: CategoryKind?
    @FocusState private var contentFocused: Bool

    private var trimmedContent: String { content.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Return is Done: it closes the keyboard rather than adding a line break.
                    TextField("Link or text", text: $content.doneOnReturn, axis: .vertical)
                        .lineLimit(1...6)
                        .submitLabel(.done)
                        .focused($contentFocused)
                    TextField("Note", text: $note.doneOnReturn, axis: .vertical)
                        .lineLimit(1...4)
                        .submitLabel(.done)
                }
                Section {
                    CategoryButtons(selection: $category)
                }
            }
            .navigationTitle(list.map { "Add to \($0.name)" } ?? "New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(trimmedContent.isEmpty)
                }
            }
            .onAppear { contentFocused = true }
            // Like the share sheet: picking a category saves. Add still saves without one.
            .onChange(of: category) { _, picked in
                guard picked != nil else { return }
                if trimmedContent.isEmpty {
                    contentFocused = true
                } else {
                    add()
                }
            }
        }
    }

    private func add() {
        let link = Self.singleLink(in: trimmedContent)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = Item(
            context: modelContext,
            contentURL: link?.absoluteString,
            contentText: link == nil ? trimmedContent : nil,
            userNote: trimmedNote.isEmpty ? nil : trimmedNote,
            quickTag: category?.quickTag
        )
        Persistence.shared.assignToPrivateStore(item)
        try? modelContext.save()
        dismiss()
        Task {
            // Into the list's store or share zone, as when moving an item there.
            if let list {
                await Sharing.move(item, to: list, in: modelContext)
                try? modelContext.save()
            }
            await pipeline.refresh(modelContext)
        }
    }

    /// The text is treated as a link only if it's nothing but one (e.g. "example.com/page").
    static func singleLink(in text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range.length == (text as NSString).length,
              let url = match.url, url.scheme == "http" || url.scheme == "https"
        else { return nil }
        return url
    }
}
