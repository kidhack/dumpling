import SwiftUI

struct ShareSheetView: View {
    @ObservedObject var viewModel: ShareViewModel
    let extensionContext: NSExtensionContext?

    @State private var userNote = ""
    @State private var selectedTag: CategoryKind? = nil
    @FocusState private var noteFocused: Bool

    /// The note with return as Done. (Extensions can't reach UIApplication, so this drops focus instead.)
    private var noteDoneOnReturn: Binding<String> {
        Binding(
            get: { userNote },
            set: { newValue in
                guard newValue.contains("\n") else {
                    userNote = newValue
                    return
                }
                userNote = newValue.replacingOccurrences(of: "\n", with: "")
                noteFocused = false
            }
        )
    }

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
                    // Return is Done: it closes the keyboard rather than adding a line break.
                    TextField("Optional", text: noteDoneOnReturn, axis: .vertical)
                        .lineLimit(2...6)
                        .submitLabel(.done)
                        .focused($noteFocused)
                }

                Section {
                    // Picking a category saves right away; Save is for sharing without one.
                    CategoryButtons(selection: $selectedTag)
                        .disabled(viewModel.isSaving)
                }

                if let message = viewModel.errorMessage {
                    Section {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .onAppear { noteFocused = true }
            .onChange(of: selectedTag) { _, tag in
                guard tag != nil else { return }
                Task {
                    while viewModel.isExtracting { try? await Task.sleep(for: .milliseconds(100)) }
                    await save()
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
        if await viewModel.save(userNote: trimmed.isEmpty ? nil : trimmed, quickTag: selectedTag?.quickTag) {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
