import EventKit
import EventKitUI
import MapKit
import SwiftUI
import CoreData

struct ItemDetailView: View {
    @ObservedObject var item: Item
    let filer: Filer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var isFiling = false
    @State private var accessRefresh = 0
    @State private var showingListPicker = false
    /// What the user just tapped, shown until the saved hearts catch up (iCloud can take a moment).
    @State private var pendingHeart: Bool?
    @State private var isSavingHeart = false
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
                listRow
                if let latitude = item.latitude, let longitude = item.longitude {
                    PlaceMapRow(name: item.displayTitle, address: item.location,
                                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                }
                attribution
            } footer: {
                if let error = item.sortError, !item.isFiled {
                    Text(error)
                }
            }
            .id(accessRefresh)

            buttons
        }
        // The same custom header as the lists: swapping the system bar in and out changed the top inset,
        // which made the list jump when coming back from an item.
        .screenHeader {
            ScreenHeader {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                        Text(item.displayTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.leading, -8)
                .accessibilityLabel("Back")
            } trailing: {
                Button(action: toggleHeart) {
                    HeartGlyph(mine: shownHeart, others: item.otherHeartCount,
                               background: Color(.systemGroupedBackground))
                        .font(.title3)
                        .symbolEffect(.bounce, value: shownHeart)
                        .scaleEffect(isSavingHeart ? 1.12 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: shownHeart)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: shownHeart)
                .accessibilityLabel(shownHeart ? "Remove Heart" : "Heart")
            }
        }
        .navigationTitle(item.displayTitle)
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { try? modelContext.save() }
        .task { await locateIfNeeded() }
        // Pull down to sort the item again from scratch (filed items just reload their event or reminder).
        .refreshable { await resort() }
        .sheet(isPresented: $showingListPicker) { ListPickerSheet(items: [item]) }
    }

    private var listRow: some View {
        Button {
            showingListPicker = true
        } label: {
            HStack(spacing: 12) {
                if let list = item.list {
                    ListLabel(list: list)
                } else {
                    Image(systemName: "list.bullet").foregroundStyle(.teal)
                        .frame(width: 22)
                    Text("Add to List")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.list.map { "List: \($0.name)" } ?? "Add to List")
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    /// When the item was added and last edited, and by whom on a shared list.
    private var attribution: some View {
        let shared = item.list.map(Sharing.isShared) ?? false
        let by: (String?) -> String = { id in
            guard shared, let name = Sharing.name(for: id, in: item.list) else { return "" }
            return " by \(name)"
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Added\(by(item.createdByID)) · \(item.timestamp.formatted(date: .abbreviated, time: .shortened))")
            if let edited = item.modifiedAt, edited.timeIntervalSince(item.timestamp) > 60 {
                Text("Edited\(by(item.modifiedByID)) · \(edited.formatted(.relative(presentation: .named)))")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var shownHeart: Bool { pendingHeart ?? item.heartedByMe }

    /// Flips the heart immediately and ignores taps until the save finishes, so a second tap
    /// during the iCloud round trip can't undo the first.
    private func toggleHeart() {
        guard !isSavingHeart else { return }
        pendingHeart = !item.heartedByMe
        isSavingHeart = true
        Task {
            await Hearts.toggle(item, in: modelContext)
            isSavingHeart = false
            // Keep showing the choice until the saved state agrees, then hand back to it.
            for _ in 0..<20 where item.heartedByMe != pendingHeart {
                try? await Task.sleep(for: .milliseconds(150))
            }
            pendingHeart = nil
        }
    }

    private func resort() async {
        guard !item.isFiled else {
            accessRefresh += 1
            return
        }
        if let reason = Sorter.unavailableReason {
            item.sortError = reason == .appleIntelligenceNotEnabled
                ? "Turn on Apple Intelligence in Settings to sort this again."
                : "On-device sorting isn't available right now."
            return
        }
        // Keep what the user chose (note, tag, list, heart); recompute everything sorting derives.
        item.status = "pending"
        item.category = nil
        item.title = nil
        item.relevantDate = nil
        item.isAllDay = false
        item.location = nil
        item.latitude = nil
        item.longitude = nil
        item.sortError = nil
        let all = Item.all(in: modelContext)
        _ = await Processor.processPending([item] + all.filter { $0.id != item.id && $0.status != "pending" },
                                           filer: filer)
        try? modelContext.save()
    }

    /// Items sorted before places had coordinates get them the first time they're opened.
    private func locateIfNeeded() async {
        guard item.latitude == nil, item.location != nil,
              category == .location || category == .event else { return }
        await Processor.locate(item, place: nil, near: nil)
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
        if item.isSavedForLater {
            EmptyView()
        } else if let event = live as? EKEvent {
            NavigationLink {
                EventView(event: event)
                    .navigationTitle(event.title ?? "Event")
                    .navigationBarTitleDisplayMode(.inline)
                    // Apple's event screen keeps its Edit button in the system bar.
                    .toolbar(.visible, for: .navigationBar)
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
        item.isFiled && item.eventKitID != nil && filer.canRead(entityType)
            && item.eventKitID.flatMap(filer.calendarItem(id:)) == nil
    }

    private var buttons: some View {
        Section {
            VStack(spacing: 10) {
                if !item.isFiled && (category == .event || category == .task) {
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
                if !item.isFiled {
                    Button {
                        item.saveForLater()
                        dismiss()
                    } label: {
                        Label("Save for Later", systemImage: "bookmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                shareButton
                if item.isArchived {
                    Button {
                        item.archivedAt = nil
                        dismiss()
                    } label: {
                        Label("Unarchive", systemImage: "tray.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else if item.isSavedForLater || isMissingFromCalendar {
                    Button {
                        item.moveToInbox()
                        dismiss()
                    } label: {
                        Label("Move to Inbox", systemImage: "tray.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else if !item.isFiled {
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

    /// The system share sheet: Messages, Mail, Notes, Reminders and so on.
    @ViewBuilder
    private var shareButton: some View {
        let label = Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
        let message = Text([item.userNote, item.location].compactMap { $0 }.joined(separator: "\n"))
        Group {
            if let url = item.contentURL.flatMap(URL.init(string:)) {
                ShareLink(item: url, subject: Text(item.displayTitle), message: message) { label }
            } else {
                let text = [item.title, item.contentText, item.location, item.userNote]
                    .compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                    .joined(separator: "\n")
                ShareLink(item: text, subject: Text(item.displayTitle)) { label }
            }
        }
        .buttonStyle(.bordered)
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

/// A list's icon and name, observed so renames and new icons or colors show right away.
private struct ListLabel: View {
    @ObservedObject var list: ItemList

    var body: some View {
        ListIcon(list: list, size: 22)
            .frame(width: 22)
        Text(list.name)
    }
}
