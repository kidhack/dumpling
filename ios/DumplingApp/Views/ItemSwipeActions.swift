import SwiftUI

/// Swipe right on an item, in a section or a list: keep it, send it to Reminders or Calendar, or move it to a
/// list (which can also take it out of one). Icons only.
struct ItemLeadingSwipeActions: View {
    let item: Item
    let filer: Filer
    let moveToList: () -> Void
    @Environment(\.managedObjectContext) private var modelContext

    var body: some View {
        if !item.isFiled {
            Button {
                item.saveForLater()
                try? modelContext.save()
            } label: {
                Image(systemName: "bookmark")
            }
            .tint(.indigo)
            .accessibilityLabel("Save for Later")
            Button {
                Task {
                    await Processor.fileNow(item, as: .task, filer: filer)
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: CategoryKind.task.systemImage)
            }
            .tint(CategoryKind.task.tint)
            .accessibilityLabel("Add to Reminders")
            if item.relevantDate != nil {
                Button {
                    Task {
                        await Processor.fileNow(item, as: .event, filer: filer)
                        try? modelContext.save()
                    }
                } label: {
                    Image(systemName: CategoryKind.event.systemImage)
                }
                .tint(CategoryKind.event.tint)
                .accessibilityLabel("Add to Calendar")
            }
        }
        Button(action: moveToList) {
            Image(systemName: "list.bullet")
        }
        .tint(.teal)
        .accessibilityLabel("Move to List")
    }
}

/// Swipe left on an item: delete, and archive or unarchive.
struct ItemTrailingSwipeActions: View {
    let item: Item
    @Environment(\.managedObjectContext) private var modelContext

    var body: some View {
        Button(role: .destructive) {
            modelContext.delete(item)
            try? modelContext.save()
        } label: {
            Label(item.isFiled ? "Remove" : "Delete", systemImage: "trash")
        }
        if item.isArchived {
            Button {
                item.archivedAt = nil
                try? modelContext.save()
            } label: {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            }
            .tint(.blue)
        } else {
            Button {
                item.archivedAt = .now
                try? modelContext.save()
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.indigo)
        }
    }
}
