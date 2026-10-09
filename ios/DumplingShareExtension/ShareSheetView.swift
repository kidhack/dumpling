import SwiftUI

struct ShareSheetView: View {
    @ObservedObject var viewModel: ShareViewModel
    let extensionContext: NSExtensionContext?

    @State private var userNote = ""
    @State private var selectedTag: String? = nil

    private let tags: [(label: String, value: String)] = [
        ("Reminder", "reminder"),
        ("Event", "event"),
        ("Music", "music"),
        ("Idea", "software_idea"),
        ("Save Link", "link_save"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Sharing") {
                    if viewModel.isExtracting {
                        ProgressView()
                    } else {
                        Text(viewModel.previewText)
                            .lineLimit(3)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Note") {
                    TextField("Optional", text: $userNote, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Picker("Tag", selection: $selectedTag) {
                        Text("None").tag(String?.none)
                        ForEach(tags, id: \.value) { tag in
                            Text(tag.label).tag(Optional(tag.value))
                        }
                    }
                }

                if let message = viewModel.errorMessage {
                    Section {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Dumpling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(viewModel.isExtracting)
                    }
                }
            }
        }
    }

    private func save() async {
        let trimmed = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if await viewModel.save(userNote: trimmed.isEmpty ? nil : trimmed, quickTag: selectedTag) {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
