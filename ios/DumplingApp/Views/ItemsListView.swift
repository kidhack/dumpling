import SwiftUI
import CoreData
import CoreLocation
import FoundationModels

enum ItemsSection: String, CaseIterable, Identifiable {
    case inbox = "Inbox", filed = "Filed", archived = "Archived"
    var id: Self { self }

    var systemImage: String {
        switch self {
        case .inbox: return "tray"
        case .filed: return "calendar.badge.checkmark"
        case .archived: return "archivebox"
        }
    }

    func contains(_ item: Item) -> Bool {
        // Items from lists others shared only appear inside those lists.
        if item.isFromSharedList { return false }
        switch self {
        case .inbox: return item.isInInbox
        case .filed: return item.isInFiled
        case .archived: return item.isArchived
        }
    }

    var emptyTitle: String {
        switch self {
        case .inbox: return "Inbox Zero"
        case .filed: return "Nothing Filed Yet"
        case .archived: return "No Archived Items"
        }
    }

    var emptyMessage: String {
        switch self {
        case .inbox: return "Share something from any app. Events and tasks are filed automatically; everything else lands here."
        case .filed: return "Items added to Calendar or Reminders show up here."
        case .archived: return "Swipe an inbox item to archive it."
        }
    }
}

struct ItemsListView: View {
    let section: ItemsSection
    /// Bumped when the user taps this tab while already on it; resets the filter to All.
    var filterResetToken = 0
    /// False while another tab is showing; leaving a tab puts its map back to the list.
    var isActiveTab = true
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(ItemPipeline.self) private var pipeline
    /// Newest first.
    @FetchRequest(sortDescriptors: [SortDescriptor(\Item.timestamp, order: .reverse)]) private var items: FetchedResults<Item>

    @State private var showingAbout = false
    @State private var showingSettings = false

    @State private var filter: CategoryKind?
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var listPickerItems: [Item] = []
    @State private var showingListPicker = false
    @State private var showingMap = false
    @State private var selectedPin: UUID?
    @State private var showsMapHint = false
    @State private var userLocation: CLLocation?

    private var isSelecting: Bool { editMode.isEditing }
    private var inSection: [Item] { items.filter(section.contains) }

    private var visible: [Item] {
        guard let filter else { return inSection }
        return inSection.filter { $0.category == filter.rawValue }
    }

    private var selectedItems: [Item] { visible.filter { selection.contains($0.id) } }

    /// Categories present in this tab, plus the selected one so it doesn't vanish while chosen.
    private var availableFilters: [CategoryKind] {
        ItemsBottomControls.filters(for: inSection, keeping: filter)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List(selection: $selection) {
                // One section per item so each is its own card.
                ForEach(visible) { item in
                    Section {
                        NavigationLink(value: item) {
                            ItemRowView(item: item, section: section)
                        }
                        .tag(item.id)
                        .id(item.id)
                        .swipeActions(edge: .trailing) { ItemTrailingSwipeActions(item: item) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            ItemLeadingSwipeActions(item: item, filer: pipeline.filer) {
                                listPickerItems = [item]
                                showingListPicker = true
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .cardList()
            // Pull down past the newest item to add one (Inbox only).
            .pullToAdd(enabled: section == .inbox && !isSelecting)
            .sheet(isPresented: $showingListPicker) {
                ListPickerSheet(items: listPickerItems) { endSelecting() }
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
            .sheet(isPresented: $showingAbout) { AboutView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .navigationTitle(section.rawValue)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Item.self) { ItemDetailView(item: $0, filer: pipeline.filer) }
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
            // The map is only for places: any other filter, or leaving the tab, goes back to the list.
            .onChange(of: ItemsBottomControls.showsMap(filter: filter, available: availableFilters)) { _, shows in
                if !shows { showingMap = false }
            }
            .onChange(of: isActiveTab) { _, active in
                if !active { showingMap = false }
            }
            .onChange(of: showingMap) { _, shown in
                if !shown { selectedPin = nil }
            }
            // Tapping this tab while on it: back to All, back to the top.
            .onChange(of: filterResetToken) { _, _ in
                filter = nil
                DispatchQueue.main.async {
                    guard let first = inSection.first?.id else { return }
                    withAnimation(.snappy) { proxy.scrollTo(first, anchor: .top) }
                }
            }
            }
        }
        .onAppear { Task { await pipeline.refresh(modelContext) } }
    }

    // MARK: - Header

    private var header: some View {
        ScreenHeader {
            if section == .inbox {
                // A title, not a button, so no glass.
                Text("Dumpling")
                    .font(.title2.bold())
                    .padding(.leading, 4)
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
            if section == .inbox {
                Menu {
                    Button("About", systemImage: "info.circle") { showingAbout = true }
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                } label: {
                    MenuTwoLineIcon()
                        .headerGlassCircle()
                }
                .accessibilityLabel("Menu")
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

    private var selectionBar: some View {
        HStack {
            Button {
                listPickerItems = selectedItems
                showingListPicker = true
            } label: {
                Label("Move to List", systemImage: "list.bullet")
            }
            Spacer()
            Text(selection.isEmpty ? "Select Items" : "\(selection.count) Selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                let archiving = section != .archived
                for item in selectedItems { item.archivedAt = archiving ? .now : nil }
                try? modelContext.save()
                endSelecting()
            } label: {
                Label(section == .archived ? "Unarchive" : "Archive",
                      systemImage: section == .archived ? "tray.and.arrow.up" : "archivebox")
            }
        }
        .disabled(selection.isEmpty)
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
    /// Watched here, on the always-present row: the dot itself isn't there to notice when processing ends.
    @State private var processing: ProcessingDot.Phase

    init(item: Item, section: ItemsSection) {
        self.item = item
        self.section = section
        _processing = State(initialValue: item.status == "pending" ? .processing : .hidden)
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(item: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .lineLimit(1)

                // "Kept" is the normal state for unfiled items, so only show where filed items went and problems.
                if item.status == "failed" {
                    Label(item.statusLabel, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if item.status != "kept" && item.status != "pending" {
                    Text(item.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
            ProcessingDot(phase: processing)
            NearbyBadge(item: item)
            if item.heartCount > 0 {
                HeartGlyph(mine: item.heartedByMe, others: item.otherHeartCount)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
        .onChange(of: item.status) { old, new in
            if new == "pending" {
                processing = .processing
            } else if old == "pending" {
                withAnimation(.easeInOut(duration: 0.3)) { processing = .done }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard processing == .done else { return }
                    withAnimation(.easeOut(duration: 0.4)) { processing = .hidden }
                }
            }
        }
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
        let present = Set(items.compactMap(\.category))
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

/// A pulsing orange dot while an item is being read and organized; green once it's done, before fading out.
struct ProcessingDot: View {
    enum Phase { case hidden, processing, done }
    let phase: Phase

    var body: some View {
        switch phase {
        case .hidden:
            EmptyView()
        case .processing:
            Circle()
                .fill(.orange)
                .frame(width: 8, height: 8)
                .phaseAnimator([1.0, 0.3]) { dot, opacity in
                    dot.opacity(opacity)
                } animation: { _ in .easeInOut(duration: 0.8) }
                .transition(.opacity)
                .accessibilityLabel("Processing")
        case .done:
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .transition(.opacity)
                .accessibilityLabel("Done")
        }
    }
}

/// On places with Notify Me Nearby on, while the user is within range: a green arrow and the distance.
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
            .foregroundStyle(.green)
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
private struct MenuTwoLineIcon: View {
    var body: some View {
        VStack(spacing: 6) {
            Capsule().frame(width: 20, height: 2.5)
            Capsule().frame(width: 20, height: 2.5)
        }
        .foregroundStyle(.primary)
    }
}
