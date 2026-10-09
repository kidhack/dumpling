import EventKit
import EventKitUI
import SwiftUI

struct ItemDetailView: View {
    @Bindable var item: Item
    let filer: Filer
    @Environment(\.modelContext) private var modelContext
    @State private var isFiling = false
    @State private var accessRefresh = 0
    @Environment(\.dismiss) private var dismiss

    private var category: ItemCategory {
        item.category.flatMap(ItemCategory.init(rawValue:)) ?? .other
    }

    var body: some View {
        Form {
            Section {
                if !item.isFiled {
                    TextField("Title", text: optional(\.title))
                }
                sharedRows
                if item.isFiled {
                    filedRows
                } else {
                    detailRows
                }
                Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            } footer: {
                if let error = item.sortError, !item.isFiled {
                    Text(error)
                }
            }
            .id(accessRefresh)

            buttons
        }
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? modelContext.save() }
    }

    // MARK: - Rows

    @ViewBuilder
    private var sharedRows: some View {
        if let urlString = item.contentURL {
            if let url = URL(string: urlString) {
                Link(urlString, destination: url).lineLimit(2)
            } else {
                Text(urlString)
            }
        }
        if let text = item.contentText {
            Text(text).textSelection(.enabled)
        }
        TextField("Note", text: optional(\.userNote), axis: .vertical)
            .lineLimit(1...5)
            .disabled(item.isFiled)
    }

    @ViewBuilder
    private var detailRows: some View {
        // A Menu with a custom label, because a label-hidden Picker indents its menu button.
        Menu {
            Picker("Category", selection: categoryBinding) {
                ForEach(ItemCategory.allCases, id: \.self) {
                    Label($0.label, systemImage: $0.systemImage).tag($0)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.systemImage)
                    .foregroundStyle(category.tint)
                    .frame(width: 22)
                Text(category.label)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .accessibilityLabel("Category: \(category.label)")
        // Otherwise the divider starts at the text, leaving a gap under the icon.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        if category == .event || category == .task {
            Toggle(category == .event ? "Date" : "Due Date", isOn: hasDate)
            if item.relevantDate != nil {
                Toggle("All Day", isOn: $item.isAllDay)
                DatePicker(category == .event ? "Starts" : "Due", selection: dateBinding,
                           displayedComponents: item.isAllDay ? [.date] : [.date, .hourAndMinute])
            }
        }
        if category == .event || category == .location {
            TextField(category == .location ? "Address" : "Location", text: optional(\.location))
        }
    }

    @ViewBuilder
    private var filedRows: some View {
        let live = item.eventKitID.flatMap(filer.calendarItem(id:))
        LabeledContent("Filed", value: item.filedTo ?? "")
        if let event = live as? EKEvent {
            NavigationLink {
                EventView(event: event)
                    .navigationTitle(event.title ?? "Event")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text(event.title ?? item.displayTitle)
                        Text(event.startDate.formatted(date: .abbreviated, time: event.isAllDay ? .omitted : .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "calendar")
                }
            }
        } else if let reminder = live as? EKReminder {
            ReminderRow(reminder: reminder, store: filer.store, fallbackTitle: item.displayTitle)
        } else if !filer.canRead(entityType) {
            Button("Allow Access to Show It") {
                Task {
                    _ = await filer.requestReadAccess(entityType)
                    accessRefresh += 1
                }
            }
        } else {
            Text("It's no longer in Calendar or Reminders. It may have been deleted.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Buttons

    private var isMissingFromCalendar: Bool {
        item.isFiled && filer.canRead(entityType) && item.eventKitID.flatMap(filer.calendarItem(id:)) == nil
    }

    @ViewBuilder
    private var buttons: some View {
        let showFile = !item.isFiled && (category == .event || category == .task)
        let showArchive = !item.isFiled || isMissingFromCalendar
        if showFile || showArchive {
            Section {
                VStack(spacing: 10) {
                    if showFile {
                        Button {
                            Task { await fileNow() }
                        } label: {
                            HStack {
                                Text(category == .event ? "Add to Calendar" : "Add to Reminders")
                                if isFiling { ProgressView() }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isFiling || (category == .event && item.relevantDate == nil))
                    }
                    if isMissingFromCalendar {
                        Button {
                            item.status = "kept"
                            item.eventKitID = nil
                            item.filedTo = nil
                        } label: {
                            Text("Move to Inbox").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else if item.isArchived {
                        Button {
                            item.archivedAt = nil
                            dismiss()
                        } label: {
                            Text("Move to Inbox").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            item.archivedAt = .now
                            dismiss()
                        } label: {
                            Label("Archive", systemImage: "archivebox").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .controlSize(.large)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func fileNow() async {
        isFiling = true
        defer { isFiling = false }
        await Processor.fileNow(item, filer: filer)
        try? modelContext.save()
    }

    private var entityType: EKEntityType {
        category == .event ? .event : .reminder
    }

    // MARK: - Bindings

    private func optional(_ keyPath: ReferenceWritableKeyPath<Item, String?>) -> Binding<String> {
        Binding(
            get: { item[keyPath: keyPath] ?? "" },
            set: { item[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private var categoryBinding: Binding<ItemCategory> {
        Binding(get: { category }, set: { item.category = $0.rawValue })
    }

    private var hasDate: Binding<Bool> {
        Binding(
            get: { item.relevantDate != nil },
            set: { on in
                item.relevantDate = on ? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now.addingTimeInterval(86_400)) : nil
            }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { item.relevantDate ?? .now }, set: { item.relevantDate = $0 })
    }
}

// MARK: - Calendar & Reminders views

/// Apple's own event screen, with its Edit button.
struct EventView: UIViewControllerRepresentable {
    let event: EKEvent

    func makeUIViewController(context: Context) -> EKEventViewController {
        let controller = EKEventViewController()
        controller.event = event
        controller.allowsEditing = true
        controller.allowsCalendarPreview = true
        return controller
    }

    func updateUIViewController(_ controller: EKEventViewController, context: Context) {}
}

/// EventKitUI has no reminder screen, so show the essentials and let it be completed here.
struct ReminderRow: View {
    let reminder: EKReminder
    let store: EKEventStore
    let fallbackTitle: String
    @State private var isCompleted = false

    var body: some View {
        Toggle(isOn: $isCompleted) {
            VStack(alignment: .leading) {
                Text(reminder.title ?? fallbackTitle)
                Group {
                    if let due = reminder.dueDateComponents?.date ?? reminder.dueDateComponents.flatMap(Calendar.current.date(from:)) {
                        Text("Due \(due.formatted(date: .abbreviated, time: reminder.dueDateComponents?.hour == nil ? .omitted : .shortened)) · \(reminder.calendar.title)")
                    } else {
                        Text(reminder.calendar.title)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { isCompleted = reminder.isCompleted }
        .onChange(of: isCompleted) { _, done in
            guard done != reminder.isCompleted else { return }
            reminder.isCompleted = done
            try? store.save(reminder, commit: true)
        }
    }
}
