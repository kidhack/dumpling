import CoreData
import MapKit
import SwiftUI

/// Every place in the current view on one map. Tapping a pin shows the place with links to its details
/// and to Apple Maps. Places saved with only an address are looked up when the map opens.
struct ItemsMapView: View {
    let items: [Item]
    let filer: Filer

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedID: UUID?
    /// Coordinates looked up for this session, for items that can't be saved to (lists shared view-only).
    @State private var lookedUp: [UUID: CLLocationCoordinate2D] = [:]
    @State private var isLookingUp = false
    @State private var detailItem: Item?

    private struct Pin: Identifiable {
        let item: Item
        let coordinate: CLLocationCoordinate2D
        var id: UUID { item.id }
    }

    private var pins: [Pin] {
        items.compactMap { item in
            if let latitude = item.latitude, let longitude = item.longitude {
                return Pin(item: item, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            }
            return lookedUp[item.id].map { Pin(item: item, coordinate: $0) }
        }
    }

    private var selected: Pin? { pins.first { $0.id == selectedID } }

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selectedID) {
                ForEach(pins) { pin in
                    Marker(pin.item.displayTitle, systemImage: CategoryKind.location.systemImage,
                           coordinate: pin.coordinate)
                        .tint(CategoryKind.location.tint)
                        .tag(pin.id)
                }
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .overlay {
                if pins.isEmpty && !isLookingUp {
                    ContentUnavailableView("No Places on the Map", systemImage: "map",
                                           description: Text("These items don't have an address yet."))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let selected {
                    PlaceCard(item: selected.item, coordinate: selected.coordinate) {
                        detailItem = selected.item
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: selectedID)
            .navigationTitle(pins.count == 1 ? "1 Place" : "\(pins.count) Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isLookingUp { ProgressView() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(item: $detailItem) { ItemDetailView(item: $0, filer: filer) }
        }
        .task { await lookUpMissing() }
    }

    /// Finds coordinates for items with an address but no map position, saving them where the user can.
    private func lookUpMissing() async {
        let missing = items.filter { $0.latitude == nil && $0.location != nil }
        guard !missing.isEmpty else { return }
        isLookingUp = true
        defer { isLookingUp = false }
        for item in missing {
            guard let address = item.location, let coordinate = await Places.geocode(address) else { continue }
            lookedUp[item.id] = coordinate
            let editable = item.list.map(Sharing.canEdit) ?? true
            if editable {
                item.latitude = coordinate.latitude
                item.longitude = coordinate.longitude
            }
        }
        if context.hasChanges { try? context.save() }
        // Refit now that more pins are on the map.
        position = .automatic
    }
}

/// The selected pin: name, address, and what you can do with it.
private struct PlaceCard: View {
    let item: Item
    let coordinate: CLLocationCoordinate2D
    let showDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                if let address = item.location, address != item.displayTitle {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            HStack(spacing: 10) {
                Button(action: showDetails) {
                    Label("Details", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(action: openInMaps) {
                    Label("Apple Maps", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }

    private func openInMaps() {
        let mapItem = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                address: item.location.flatMap { MKAddress(fullAddress: $0, shortAddress: nil) })
        mapItem.name = item.displayTitle
        mapItem.openInMaps(launchOptions: nil)
    }
}
