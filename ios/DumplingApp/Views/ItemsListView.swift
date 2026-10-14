import SwiftUI
import CoreData
import CoreLocation
import FoundationModels

/// The built-in lists: tiles at the top of the Lists screen. Inbox is where the app opens.
enum ItemsSection: String, CaseIterable, Identifiable, Hashable {
    case inbox = "Inbox", favorites = "Favorites", saved = "Saved", archived = "Archive"
    var id: Self { self }

    var systemImage: String {
        switch self {
        case .inbox: return "tray.fill"
        case .favorites: return "heart.fill"
        case .saved: return "bookmark.fill"
        case .archived: return "archivebox.fill"
        }
    }

    var tint: Color {
        switch self {
        case .inbox: return Color(light: 0x0062CC, dark: 0x0A84FF)
        case .favorites: return Color(light: 0xD70015, dark: 0xFF453A)
        case .saved: return Color(light: 0x5856D6, dark: 0x7D7AFF)
        case .archived: return Color(light: 0x6C6C70, dark: 0x98989D)
        }
    }

    func contains(_ item: Item) -> Bool {
        switch self {
        // Items from lists others shared only appear inside those lists, and in Favorites and Archive.
        case .inbox: return !item.isFromSharedList && item.isInInbox
        case .favorites: return item.heartedByMe && !item.isInArchive
        case .saved: return !item.isFromSharedList && item.isSavedForLater && !item.isArchived
        // Archive also holds what was sent to Calendar or Reminders: those live there now.
        case .archived: return item.isInArchive
        }
    }

    var emptyTitle: String {
        switch self {
        case .inbox: return "Inbox Zero"
        case .favorites: return "No Favorites"
        case .saved: return "Nothing Saved"
        case .archived: return "Nothing Archived"
        }
    }

    var emptyMessage: String {
        switch self {
        case .inbox: return "Share something from any app, or pull down to add one. Events and tasks go to Calendar and Reminders; everything else lands here."
        case .favorites: return "Heart an item to keep it here, from any list."
        case .saved: return "Swipe right on an Inbox item to save it for later."
        case .archived: return "Archived items, and anything sent to Calendar or Reminders."
        }
    }
}

struct ItemsListView: View {
    let section: ItemsSection
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ItemPipeline.self) private var pipeline
    /// Newest first.
    @FetchRequest(sortDescriptors: [SortDescriptor(\Item.timestamp, order: .reverse)]) private var items: FetchedResults<Item>

    @State private var filter: CategoryKind?
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    /// The items being moved. The sheet opens from this value itself: with a separate show flag, it could
    /// open before the items were set and show every list checked.
    @State private var listPicker: ListPickerRequest?
    @State private var confirmingDelete = false
    @State private var showingMap = false
    @State private var selectedPin: UUID?
    @State private var showsMapHint = false
    @State private var userLocation: CLLocation?

    private var isSelecting: Bool { editMode.isEditing }
    private var inSection: [Item] { items.filter(section.contains) }

    private var visible: [Item] {
        guard let filter else { return inSection }
        return inSection.filter { $0.itemCategory?.rawValue == filter.rawValue }
    }

    private var selectedItems: [Item] { visible.filter { selection.contains($0.id) } }

    /// Categories present in this tab, plus the selected one so it doesn't vanish while chosen.
    private var availableFilters: [CategoryKind] {
        ItemsBottomControls.filters(for: inSection, keeping: filter)
    }

    var body: some View {
        List(selection: $selection) {
            // One group of plain rows with faint dividers, not a card per item.
            Section {
                ForEach(visible) { item in
                    NavigationLink(value: item) {
                        ItemRowView(item: item, section: section)
                    }
                    .tag(item.id)
                    .id(item.id)
                    .plainRow()
                    .swipeActions(edge: .trailing) { ItemTrailingSwipeActions(item: item) }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        ItemLeadingSwipeActions(item: item, filer: pipeline.filer) {
                            listPicker = ListPickerRequest(items: [item])
                        }
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .cardList()
        // Pull down past the newest item to add one (Inbox only).
        .pullToAdd(enabled: section == .inbox && !isSelecting)
        .sheet(item: $listPicker) { request in
            ListPickerSheet(items: request.items) { endSelecting() }
        }
        // On the map, the header and bottom controls are plain insets on the map rather than the list's
        // bars: system bars draw an edge layer behind themselves, which showed as a band over the map.
        .overlay {
            if showingMap {
                ItemsMapView(items: visible, selection: $selectedPin, userLocation: $userLocation)
                    .safeAreaInset(edge: .top, spacing: 0) { headerStack.padding(.bottom, ScreenHeaderSpacing.bottom) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
                    .transition(.opacity)
            }
        }
        .scrollEdgeEffectHidden(showingMap, for: .all)
        .screenHeader(hidden: showingMap) { headerStack }
        .navigationTitle(section.rawValue)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if visible.isEmpty {
                if let filter, !inSection.isEmpty {
                    ContentUnavailableView("No \(filter.label) Items", systemImage: filter.systemImage)
                } else {
                    ContentUnavailableView(section.emptyTitle, systemImage: section.systemImage,
                                           description: Text(section.emptyMessage))
                }
            }
        }
        // A bar, not an inset, so cards scrolling under it get the system's soft edge effect.
        .safeAreaBar(edge: .bottom) {
            if isSelecting {
                selectionBar
            } else if !inSection.isEmpty && !showingMap {
                bottomControls
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingMap)
        // The map is only for places: any other filter goes back to the list.
        .onChange(of: ItemsBottomControls.showsMap(filter: filter, available: availableFilters)) { _, shows in
            if !shows { showingMap = false }
        }
        .onChange(of: showingMap) { _, shown in
            if !shown { selectedPin = nil }
        }
        .onAppear { Task { await pipeline.refresh(modelContext) } }
    }

    // MARK: - Header

    private var header: some View {
        ScreenHeader {
            if isSelecting {
                // Like Mail: select everything showing (the current filter), or clear it.
                Button(allSelected ? "Deselect All" : "Select All") {
                    selection = allSelected ? [] : Set(visible.map(\.id))
                }
                .buttonStyle(.plain)
                .headerGlass()
            } else {
                HStack(spacing: 8) {
                    // Back to the Lists screen, like Mail's mailboxes.
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .headerGlassCircle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Lists")
                    // A title, not a button, so no glass.
                    Text(section.rawValue)
                        .font(.title2.bold())
                }
            }
        } trailing: {
            if !inSection.isEmpty && !showingMap {
                Button(isSelecting ? "Done" : "Select") {
                    if isSelecting { endSelecting() } else { editMode = .active }
                }
                .fontWeight(isSelecting ? .semibold : .regular)
                .buttonStyle(.plain)
                .headerGlass()
            }
        }
    }

    private var headerStack: some View {
        VStack(spacing: 8) {
            header
            if section == .inbox, let reason = pipeline.modelUnavailable {
                ModelUnavailableBanner(reason: reason)
            }
        }
    }

    private var bottomControls: some View {
        ItemsBottomControls(visible: visible, filter: $filter, available: availableFilters,
                            showingMap: $showingMap, showsMapHint: $showsMapHint,
                            selectedPin: selectedPin, userLocation: userLocation)
    }

    // MARK: - Selection

    private var allSelected: Bool { !visible.isEmpty && selection.isSuperset(of: visible.map(\.id)) }

    private var selectionBar: some View {
        HStack {
            if section == .archived {
                // Archived is where things get cleared out for good.
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            } else {
                Button {
                    listPicker = ListPickerRequest(items: selectedItems)
                } label: {
                    Label("Move to List", systemImage: "list.bullet")
                }
            }
            Spacer()
            Text(selection.isEmpty ? "Select Items" : "\(selection.count) Selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                let archiving = section != .archived
                for item in selectedItems {
                    if archiving { item.archivedAt = .now } else { item.unarchive() }
                }
                try? modelContext.save()
                endSelecting()
            } label: {
                Label(section == .archived ? "Unarchive" : "Archive",
                      systemImage: section == .archived ? "tray.and.arrow.up" : "archivebox")
            }
        }
        .disabled(selection.isEmpty)
        .confirmationDialog(selection.count == 1 ? "Delete 1 Item?" : "Delete \(selection.count) Items?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                for item in selectedItems { modelContext.delete(item) }
                try? modelContext.save()
                endSelecting()
            }
        } message: {
            Text("This can't be undone.")
        }
        // Same footprint as the filter row it replaces, so entering Select moves nothing.
        .frame(height: CategoryFilterBar.chipHeight)
        .padding(.horizontal, 20)
        .padding(.top, CategoryFilterBar.topPadding)
        .padding(.bottom, CategoryFilterBar.bottomPadding)
    }

    private func endSelecting() {
        selection.removeAll()
        editMode = .inactive
    }
}

// MARK: - Row

struct ItemRowView: View {
    @ObservedObject var item: Item
    let section: ItemsSection

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(item: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .lineLimit(1)

                // "Kept" is the normal state for unfiled items, so only show where filed items went and problems.
                // Processing shows as the hourglass in place of the category icon.
                if item.status == "failed" {
                    Label(item.statusLabel, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.warning)
                } else if section == .archived, let list = item.list {
                    // Unarchiving puts it back in this list.
                    Label(list.name, systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if item.status != "kept" && item.status != "pending" {
                    Text(item.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
            NearbyBadge(item: item)
            if item.heartCount > 0 {
                HeartGlyph(mine: item.heartedByMe, others: item.otherHeartCount)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Below a section's or list's items: the selected place's card (on the map), the Map / List pill (with the
/// Location filter on) and the filter row.
struct ItemsBottomControls: View {
    let visible: [Item]
    @Binding var filter: CategoryKind?
    let available: [CategoryKind]
    @Binding var showingMap: Bool
    @Binding var showsMapHint: Bool
    let selectedPin: UUID?
    let userLocation: CLLocation?

    /// Categories present in `items`, plus the current filter so it never disappears from under the user.
    static func filters(for items: [Item], keeping filter: CategoryKind?) -> [CategoryKind] {
        let present = Set(items.compactMap { $0.itemCategory?.rawValue })
        return CategoryKind.allCases.filter { present.contains($0.rawValue) || $0 == filter }
    }

    /// The map is for places: with the Location filter on, or with nothing but places to show.
    static func showsMap(filter: CategoryKind?, available: [CategoryKind]) -> Bool {
        filter == .location || (filter == nil && available == [.location])
    }

    var body: some View {
        // With a single category, All and that category show the same items, so the row is left out, except
        // for places: a lone Location chip stays, as the way to the map.
        let placesOnly = available == [.location]
        VStack(spacing: 12) {
            if showingMap, let pin = ItemsMapView.pins(for: visible).first(where: { $0.id == selectedPin }) {
                PlaceCard(item: pin.item, coordinate: pin.coordinate, userLocation: userLocation)
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
            if placesOnly {
                // Always shown selected; tapping it switches between list and map.
                CategoryFilterBar(selection: .constant(.location), available: available,
                                  showingMap: $showingMap, showsAll: false, showsMapHint: $showsMapHint)
            } else if available.count > 1 {
                CategoryFilterBar(selection: $filter, available: available,
                                  showingMap: Self.showsMap(filter: filter, available: available) ? $showingMap : nil,
                                  showsMapHint: $showsMapHint)
            }
        }
        .animation(.easeOut(duration: 0.2), value: selectedPin)
        .animation(.snappy(duration: 0.2), value: filter)
    }
}

/// On places with Notify when nearby on, while the user is within range: a green arrow and the distance.
struct NearbyBadge: View {
    let item: Item

    var body: some View {
        let alerts = NearbyAlerts.shared
        if alerts.isClose(to: item), let meters = alerts.distance(to: item) {
            HStack(spacing: 3) {
                Image(systemName: "location.fill")
                Text(NearbyAlerts.format(meters))
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(CategoryKind.location.tint)
            .accessibilityElement()
            .accessibilityLabel("Nearby, \(NearbyAlerts.format(meters))")
        }
    }
}

/// Hearts on an item. A red heart peeks out behind when someone else hearted it; in front is the user's own
/// heart, solid red or an empty outline. A ring in the background color separates the two.
struct HeartGlyph: View {
    let mine: Bool
    let others: Int
    /// The color behind the glyph, used for the separating ring and to hide the back heart inside an outline.
    var background: Color = Color(.secondarySystemGroupedBackground)

    var body: some View {
        ZStack {
            if others > 0 {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .offset(x: -5, y: -4)
            }
            Image(systemName: mine ? "heart.fill" : "heart")
                .foregroundStyle(mine ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                .background {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(background)
                        .scaleEffect(others > 0 ? 1.3 : 1)
                }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private var label: String {
        switch (mine, others) {
        case (true, 0): return "Hearted by you"
        case (true, let n): return "Hearted by you and \(n) other\(n == 1 ? "" : "s")"
        case (false, 0): return "Not hearted"
        case (false, let n): return "Hearted by \(n) other\(n == 1 ? "" : "s")"
        }
    }
}

struct ModelUnavailableBanner: View {
    let reason: SystemLanguageModel.Availability.UnavailableReason

    var body: some View {
        Label(message, systemImage: "sparkles")
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.yellow.opacity(0.2), in: .rect(cornerRadius: 10))
            .padding(.horizontal)
    }

    private var message: String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to sort items. They'll be sorted next time you open Dumpling."
        case .modelNotReady:
            return "Apple Intelligence is still downloading. Items will be sorted once it's ready."
        case .deviceNotEligible:
            return "This device can't run Apple Intelligence, so items won't be sorted."
        @unknown default:
            return "On-device sorting isn't available right now."
        }
    }
}

/// Two-line menu icon (after Hugeicons "menu-two-line"); SF Symbols only has a three-line one.
struct MenuTwoLineIcon: View {
    var body: some View {
        VStack(spacing: 6) {
            Capsule().frame(width: 20, height: 2.5)
            Capsule().frame(width: 20, height: 2.5)
        }
        .foregroundStyle(.primary)
    }
}
