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

    @State private var pull: CGFloat = 0
    @State private var isDragging = false
    @State private var addArmed = false
    @State private var showingNewItem = false
    @State private var showingAbout = false
    @State private var showingSettings = false
    private let addThreshold: CGFloat = 100

    @State private var filter: CategoryKind?
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var listPickerItems: [Item] = []
    @State private var showingListPicker = false
    @State private var showingMap = false
    @State private var selectedPin: UUID?
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
        let present = Set(inSection.compactMap(\.category))
        return CategoryKind.allCases.filter { present.contains($0.rawValue) || $0 == filter }
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
                        .swipeActions(edge: .trailing) { trailingActions(for: item) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingActions(for: item) }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .listSectionSpacing(10)
            // Pull down past the newest item to add one (Inbox only). Only real drags count: layout changes
            // (launch, a sheet closing) can briefly read as overscroll.
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                -(geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, overscroll in
                guard section == .inbox, !isSelecting else { return }
                pull = max(0, overscroll)
                if isDragging { addArmed = pull >= addThreshold }
            }
            .background {
                if section == .inbox {
                    ScrollTouchReader { dragging in
                        isDragging = dragging
                        if !dragging {
                            if addArmed { showingNewItem = true }
                            addArmed = false
                        }
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: addArmed) { _, armed in armed }
            .overlay(alignment: .top) {
                if section == .inbox && isDragging && pull > 4 && !isSelecting {
                    NewCardHint(progress: min(pull / addThreshold, 1), armed: addArmed,
                                reveal: max(0, min(pull - 16, 80)))
                        .padding(.top, 8)
                }
            }
            .accessibilityActions {
                if section == .inbox {
                    Button("Add Item") { showingNewItem = true }
                }
            }
            .sheet(isPresented: $showingNewItem) { NewItemView() }
            .sheet(isPresented: $showingListPicker) {
                ListPickerSheet(items: listPickerItems) { endSelecting() }
            }
            .overlay {
                if showingMap {
                    ItemsMapView(items: visible, selection: $selectedPin, userLocation: $userLocation)
                        .transition(.opacity)
                }
            }
            .screenHeader(overMap: showingMap) {
                VStack(spacing: 8) {
                    header
                    if section == .inbox, let reason = pipeline.modelUnavailable {
                        ModelUnavailableBanner(reason: reason)
                    }
                }
            }
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
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    selectionBar
                } else if !inSection.isEmpty {
                    VStack(spacing: 12) {
                        if showingMap, let pin = ItemsMapView.pins(for: visible).first(where: { $0.id == selectedPin }) {
                            PlaceCard(item: pin.item, coordinate: pin.coordinate, userLocation: userLocation)
                                .padding(.horizontal, 16)
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                                // The filter row's fade reaches up behind these; keep them in front of it.
                                .zIndex(1)
                        }
                        if filter == .location {
                            MapListToggle(showingMap: $showingMap)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                .zIndex(1)
                        }
                        CategoryFilterBar(selection: $filter, available: availableFilters)
                    }
                    .animation(.easeOut(duration: 0.2), value: selectedPin)
                    .animation(.snappy(duration: 0.2), value: filter)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showingMap)
            // The map is only for places: any other filter, or leaving the tab, goes back to the list.
            .onChange(of: filter) { _, new in
                if new != .location { showingMap = false }
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
                Text("Dumpling")
                    .font(.title2.bold())
            }
        } trailing: {
            if !inSection.isEmpty && !showingMap {
                Button(isSelecting ? "Done" : "Select") {
                    if isSelecting { endSelecting() } else { editMode = .active }
                }
                .fontWeight(isSelecting ? .semibold : .regular)
                .frame(minHeight: 44)
                .padding(.horizontal, 8)
            }
            if section == .inbox {
                Menu {
                    Button("About", systemImage: "info.circle") { showingAbout = true }
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                } label: {
                    MenuTwoLineIcon()
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Menu")
            }
        }
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
        .bottomBarFade()
    }

    private func endSelecting() {
        selection.removeAll()
        editMode = .inactive
    }

    // MARK: - Swipes

    /// Swipe right: keep it, send it to Reminders or Calendar, or move it to a list. Icons only.
    @ViewBuilder
    private func leadingActions(for item: Item) -> some View {
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
                    await Processor.fileNow(item, as: .task, filer: pipeline.filer)
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
                        await Processor.fileNow(item, as: .event, filer: pipeline.filer)
                        try? modelContext.save()
                    }
                } label: {
                    Image(systemName: CategoryKind.event.systemImage)
                }
                .tint(CategoryKind.event.tint)
                .accessibilityLabel("Add to Calendar")
            }
        }
        Button {
            listPickerItems = [item]
            showingListPicker = true
        } label: {
            Image(systemName: "list.bullet")
        }
        .tint(.teal)
        .accessibilityLabel("Move to List")
    }

    @ViewBuilder
    private func trailingActions(for item: Item) -> some View {
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

// MARK: - Row

struct ItemRowView: View {
    let item: Item
    let section: ItemsSection

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
                } else if item.status != "kept" {
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

/// Floating Map / List switch, centered above the filter row while Location is selected.
struct MapListToggle: View {
    @Binding var showingMap: Bool

    var body: some View {
        Button {
            showingMap.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(showingMap ? "List" : "Map")
                Image(systemName: showingMap ? "list.bullet" : "map.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(.systemBackground))
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(Color(.label), in: .capsule)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: showingMap)
        .accessibilityLabel(showingMap ? "Show as List" : "Show on Map")
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

/// A new card edging down from behind the header while the user pulls down.
/// Only its bottom shows at first; it turns solid once releasing will add.
private struct NewCardHint: View {
    let progress: CGFloat
    let armed: Bool
    /// How much of the card has emerged, in points.
    let reveal: CGFloat

    private let cardHeight: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(armed ? Color(.secondarySystemGroupedBackground) : .clear)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.secondary.opacity(armed ? 0 : 0.6 * progress),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(armed ? .primary : .secondary)
                .opacity(progress)
                .scaleEffect(0.6 + 0.4 * progress)
        }
        .frame(height: cardHeight)
        .padding(.horizontal, 16)
        // Show only the emerged bottom of the card, fading out toward the header.
        .frame(height: reveal, alignment: .bottom)
        .clipped()
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.45),
                                   .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(.snappy(duration: 0.15), value: armed)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
