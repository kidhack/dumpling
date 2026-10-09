import SwiftUI

struct ShareSheetView: View {
    @ObservedObject var viewModel: ShareViewModel
    let extensionContext: NSExtensionContext?

    @State private var userNote = ""
    @State private var selectedTag: CategoryKind? = nil

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
                    HStack {
                        ForEach(CategoryKind.allCases) { kind in
                            TagButton(kind: kind, isSelected: selectedTag == kind) {
                                selectedTag = selectedTag == kind ? nil : kind
                            }
                            if kind != CategoryKind.allCases.last { Spacer(minLength: 0) }
                        }
                    }
                    .padding(.vertical, 4)
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
        if await viewModel.save(userNote: trimmed.isEmpty ? nil : trimmed, quickTag: selectedTag?.quickTag) {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}

/// A one-tap category choice. Tapping the selected one again clears it so Dumpling decides.
private struct TagButton: View {
    let kind: CategoryKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: kind.systemImage)
                .font(.title3)
                .foregroundStyle(isSelected ? .white : kind.tint)
                .frame(width: 40, height: 40)
                .background(isSelected ? kind.tint : kind.tint.opacity(0.15), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
