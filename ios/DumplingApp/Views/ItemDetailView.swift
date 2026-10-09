import EventKit
import EventKitUI
import SwiftUI

struct ItemDetailView: View {
    @Bindable var item: Item
    let filer: Filer
    @Environment(\.modelContext) private var modelContext
    @State private var isFiling = false
    @State private var accessRefresh = 0

    private var category: ItemCategory {
        item.category.flatMap(ItemCategory.init(rawValue:)) ?? .other
    }

    var body: some View {
        Form {
            sharedSection
            if item.isFiled {
                filedSection
            } else {
                editSection
                actionsSection
            }
            Section {
                LabeledContent("Shared", value: item.timestamp.formatted(date: .abbreviated, time: .shortened))
                if RelayClient.isConfigured {
                    LabeledContent("Relay", value: item.syncLabel)
                }
            }
        }
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? modelContext.save() }
    }

    // MARK: - Shared content

    private var sharedSection: some View {
        Section("Shared") {
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
    }

    // MARK: - Editing (open items)

    private var editSection: some View {
        Section {
            TextField("Title", text: optional(\.title))
            Picker("Category", selection: categoryBinding) {
                ForEach([ItemCategory.event, .task, .link, .idea, .music, .other], id: \.self) {
                    Text($0.rawValue.capitalized).tag($0)
                }
            }
            if category == .event || category == .task {
                Toggle(category == .event ? "Date" : "Due Date", isOn: hasDate)
                if item.relevantDate != nil {
                    Toggle("All Day", isOn: $item.isAllDay)
                    DatePicker(category == .event ? "Starts" : "Due", selection: dateBinding,
                               displayedComponents: item.isAllDay ? [.date] : [.date, .hourAndMinute])
                }
            }
            if category == .event {
                TextField("Location", text: optional(\.location))
            }
        } header: {
            Text("Details")
        } footer: {
            if let error = item.sortError {
                Text(error)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            if category == .event || category == .task {
                Button {
                    Task { await fileNow() }
                } label: {
                    HStack {
                        Text(category == .event ? "Add to Calendar" : "Add to Reminders")
                        if isFiling { Spacer(); ProgressView() }
                    }
                }
                .disabled(isFiling || (category == .event && item.relevantDate == nil))
            }
            Button("Sort Again") {
                item.status = "pending"
                item.sortError = nil
                item.archivedAt = nil
            }
            if item.isArchived {
                Button("Move to Inbox") { item.archivedAt = nil }
            } else {
                Button("Archive") { item.archivedAt = .now }
            }
        }
    }

    private func fileNow() async {
        isFiling = true
        defer { isFiling = false }
        await Processor.fileNow(item, filer: filer)
        try? modelContext.save()
    }

    // MARK: - Filed items

    @ViewBuilder
    private var filedSection: some View {
        let live = item.eventKitID.flatMap(filer.calendarItem(id:))
        Section {
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
                Button("Move to Inbox") {
                    item.status = "kept"
                    item.eventKitID = nil
                    item.filedTo = nil
                }
            }
        } header: {
            Text("Calendar & Reminders")
        }
        .id(accessRefresh)
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
