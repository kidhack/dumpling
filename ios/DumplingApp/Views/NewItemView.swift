import SwiftUI
import SwiftData

/// Adds an item without the share sheet. It's sorted like a shared item.
struct NewItemView: View {
    @Environment(\.modelContext) private var modelContext
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
                    TextField("Link or text", text: $content, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($contentFocused)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    CategoryButtons(selection: $category)
                }
            }
            .navigationTitle("New Item")
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
        }
    }

    private func add() {
        let link = Self.singleLink(in: trimmedContent)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = Item(
            contentURL: link?.absoluteString,
            contentText: link == nil ? trimmedContent : nil,
            userNote: trimmedNote.isEmpty ? nil : trimmedNote,
            quickTag: category?.quickTag
        )
        modelContext.insert(item)
        try? modelContext.save()
        dismiss()
        Task { await pipeline.refresh(modelContext) }
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
