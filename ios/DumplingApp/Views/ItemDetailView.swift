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
    /// The title field has scrolled under the header, so the header shows the title instead.
    @State private var titleScrolledAway = false
    /// Shared as a link: keeps the link row while its text is being edited, even if briefly empty.
    @State private var hasLink = false
    @Environment(\.dismiss) private var dismiss

    private var category: ItemCategory {
        item.category.flatMap(ItemCategory.init(rawValue:)) ?? .other
    }

    var body: some View {
        Form {
            Section {
                if !item.isFiled {
                    TextField("Title", text: optional(\.title), axis: .vertical)
                        .font(.title2.weight(.semibold))
                }
                sharedRows
                if item.isFiled {
                    filedRows
                } else {
                    detailRows
                }
                listRow
                // Only for places: other items can keep a position from an earlier category.
                if category == .location, let latitude = item.latitude, let longitude = item.longitude {
                    PlaceMapRow(name: item.displayTitle, address: item.location,
                                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                    NearbyRow(item: item)
                }
                attribution
            } footer: {
                if let error = item.sortError, !item.isFiled {
                    Text(error)
                }
            }
            // The details sit on the background rather than in a card: it's the only group on the screen.
            .listRowBackground(Color.clear)
            .id(accessRefresh)

            buttons
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > 40
        } action: { _, away in
            titleScrolledAway = away
        }
        // The same custom header as the lists: swapping the system bar in and out changed the top inset,
        // which made the list jump when coming back from an item.
        .screenHeader {
            ScreenHeader {
                HStack(spacing: 8) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .headerGlassCircle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    // The title field already shows it at the top, so the header only does once that scrolls away
                    // (filed items have no title field).
                    Text(item.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(item.isFiled || titleScrolledAway ? 1 : 0)
                        .animation(.easeOut(duration: 0.15), value: titleScrolledAway)
                }
            } trailing: {
                Button(action: toggleHeart) {
                    HeartGlyph(mine: shownHeart, others: item.otherHeartCount,
                               background: Color(.systemGroupedBackground))
                        .font(.title3)
                        .symbolEffect(.bounce, value: shownHeart)
                        .scaleEffect(isSavingHeart ? 1.12 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: shownHeart)
                        .headerGlassCircle()
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: shownHeart)
                .accessibilityLabel(shownHeart ? "Remove Heart" : "Heart")
            }
        }
        .navigationTitle(item.displayTitle)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { hasLink = item.contentURL != nil }
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
                    // Not in a list: where it is instead. Tapping moves it to a list.
                    Image(systemName: homeSection.systemImage).foregroundStyle(.secondary)
                        .frame(width: 22)
                    Text(homeSection.rawValue)
                        .foregroundStyle(Color(.label))
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.list.map { "List: \($0.name)" } ?? "In \(homeSection.rawValue)")
        .accessibilityHint("Moves it to a list")
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private var homeSection: ItemsSection { item.isArchived ? .archived : item.isFiled ? .filed : .inbox }

    /// When the item was added and last edited, and by whom on a shared list.
    private var attribution: some View {
        let shared = item.list.map(Sharing.isShared) ?? false
        let by: (String?) -> String = { id in
            guard shared, let name = Sharing.name(for: id, in: item.list) else { return "" }
            return " by \(name)"
        }
        // No extra spacing: separate lines sit as close as the wrapped lines of the shared text.
        return VStack(alignment: .leading, spacing: 0) {
            // The original shared text, as a record of what came in. It usually became the title, so only when
            // it says more.
            if let text = item.contentText, Filer.normalized(text) != Filer.normalized(item.title ?? "") {
                Text("“\(text)”")
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
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
                                           filer: filer, sortingNow: item.id)
        try? modelContext.save()
    }

    /// The user edited the address: find the place again.
    private func relocate() async {
        guard category == .location || category == .event else { return }
        item.latitude = nil
        item.longitude = nil
        let near = Processor.recentCoordinate(in: Item.all(in: modelContext), excluding: item)
        if let place = await Processor.findPlace(for: item, near: near), let coordinate = place.coordinate {
            item.latitude = coordinate.latitude
            item.longitude = coordinate.longitude
            // The user typed a street without a city: fill in the full address that was found.
            if let full = place.address, !(item.location.map(Places.hasCity) ?? false) { item.location = full }
        }
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
        if hasLink {
            iconRow("link") {
                TextField("Link", text: optional(\.contentURL))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1)
                if let url = item.contentURL.flatMap(URL.init(string:)) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open Link")
                }
            }
        }
        iconRow("note.text") {
            TextField("Note", text: optional(\.userNote), axis: .vertical)
                .lineLimit(1...5)
                .disabled(item.isFiled)
        }
    }

    /// A row with a leading icon, lined up with the category and list rows.
    private func iconRow<Content: View>(_ systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            content()
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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
                    .foregroundStyle(Color(.label))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        // Menus tint their label with the accent color; keep the text plain like the other rows.
        .tint(Color(.label))
        .accessibilityLabel("Category: \(category.label)")
        // Otherwise the divider starts at the text, leaving a gap under the icon.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        if category == .event || category == .task {
            iconRow("calendar") {
                Toggle(category == .event ? "Date" : "Due Date", isOn: hasDate)
            }
            if item.relevantDate != nil {
                // Indented to the text above: they belong to the date.
                Toggle("All Day", isOn: $item.isAllDay)
                    .padding(.leading, 34)
                DatePicker(category == .event ? "Starts" : "Due", selection: dateBinding,
                           displayedComponents: item.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .padding(.leading, 34)
            }
        }
        if category == .event || category == .location {
            iconRow("mappin") {
                TextField(category == .location ? "Address" : "Location", text: optional(\.location))
                    .onSubmit { Task { await relocate() } }
            }
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
                    .buttonStyle(OutlinedButtonStyle(prominent: true))
                    .disabled(isFiling || (category == .event && item.relevantDate == nil))
                }
                if !item.isFiled {
                    Button {
                        item.saveForLater()
                        dismiss()
                    } label: {
                        Label("Save for Later", systemImage: "bookmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlinedButtonStyle())
                }
                shareButton
                if item.isArchived {
                    Button {
                        item.archivedAt = nil
                        dismiss()
                    } label: {
                        Label("Unarchive", systemImage: "tray.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlinedButtonStyle())
                } else if item.isSavedForLater || isMissingFromCalendar {
                    Button {
                        item.moveToInbox()
                        dismiss()
                    } label: {
                        Label("Move to Inbox", systemImage: "tray.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlinedButtonStyle())
                } else if !item.isFiled {
                    Button {
                        item.archivedAt = .now
                        dismiss()
                    } label: {
                        Label("Archive", systemImage: "archivebox").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlinedButtonStyle())
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
        .buttonStyle(OutlinedButtonStyle())
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

/// Outlined buttons for item details. On the plain background (no card), filled buttons felt too heavy.
/// `prominent` is the main action: tinted outline and text.
struct OutlinedButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? Color.accentColor : Color(.label))
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(.capsule)
            .overlay {
                Capsule()
                    .strokeBorder(prominent ? Color.accentColor : Color(.systemGray3), lineWidth: prominent ? 1.5 : 1)
            }
            .opacity(configuration.isPressed ? 0.55 : isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
