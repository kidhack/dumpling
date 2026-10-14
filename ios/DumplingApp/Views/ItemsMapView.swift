import CoreData
import MapKit
import SwiftUI

/// The places in a tab, shown in place of its list. Places saved with only an address are looked up
/// when the map appears.
struct ItemsMapView: View {
    let items: [Item]
    @Binding var selection: UUID?
    /// Where the user is, once they've allowed it; for distances on the place card.
    @Binding var userLocation: CLLocation?

    @Environment(\.managedObjectContext) private var context
    @State private var position: MapCameraPosition = .automatic
    /// Coordinates looked up for this session, for items that can't be saved to (lists shared view-only).
    @State private var lookedUp: [UUID: CLLocationCoordinate2D] = [:]
    @State private var isLookingUp = true

    struct Pin: Identifiable {
        let item: Item
        let coordinate: CLLocationCoordinate2D
        var id: UUID { item.id }
    }

    static func pins(for items: [Item], lookedUp: [UUID: CLLocationCoordinate2D] = [:]) -> [Pin] {
        items.compactMap { item in
            if let latitude = item.latitude, let longitude = item.longitude {
                return Pin(item: item, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            }
            return lookedUp[item.id].map { Pin(item: item, coordinate: $0) }
        }
    }

    private var pins: [Pin] { Self.pins(for: items, lookedUp: lookedUp) }

    var body: some View {
        Map(position: $position, selection: $selection) {
            ForEach(pins) { pin in
                Marker(pin.item.displayTitle, systemImage: CategoryKind.location.systemImage,
                       coordinate: pin.coordinate)
                    .tint(CategoryKind.location.tint)
                    .tag(pin.id)
            }
            UserAnnotation()
        }
        // Tapping the location button asks for permission the first time.
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        // Runs under the header and filter row, which fade it out at the edges.
        .ignoresSafeArea()
        .overlay {
            if pins.isEmpty && !isLookingUp {
                ContentUnavailableView("No Places on the Map", systemImage: "map",
                                       description: Text("These items don't have an address yet."))
                    .background(Color(.systemGroupedBackground))
            }
        }
        .task { await lookUpMissing() }
        .task { await followUser() }
    }

    /// Updates only after real movement, so the card's distance doesn't re-render on every GPS tick.
    private func followUser() async {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard let location = update.location else { continue }
                if let current = userLocation, current.distance(from: location) < 20 { continue }
                userLocation = location
            }
        } catch {}
    }

    /// Finds coordinates for items with an address but no map position, saving them where the user can.
    private func lookUpMissing() async {
        defer { isLookingUp = false }
        let missing = items.filter { $0.latitude == nil && $0.location != nil }
        guard !missing.isEmpty else { return }
        for item in missing {
            guard let address = item.location, let coordinate = await Places.geocode(address) else { continue }
            lookedUp[item.id] = coordinate
            if item.list.map(Sharing.canEdit) ?? true {
                item.latitude = coordinate.latitude
                item.longitude = coordinate.longitude
            }
        }
        if context.hasChanges { try? context.save() }
        // Refit now that more pins are on the map.
        position = .automatic
    }
}

/// The selected pin, above the filter row: name, address, and what you can do with it.
struct PlaceCard: View {
    let item: Item
    let coordinate: CLLocationCoordinate2D
    var userLocation: CLLocation?

    private var distance: String? {
        guard let userLocation else { return nil }
        let meters = userLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        return NearbyAlerts.format(meters) + " away"
    }

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
                if let distance {
                    Text(distance)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                NavigationLink(value: item) {
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
        .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
    }

    private func openInMaps() {
        let mapItem = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                address: item.location.flatMap { MKAddress(fullAddress: $0, shortAddress: nil) })
        mapItem.name = item.displayTitle
        mapItem.openInMaps(launchOptions: nil)
    }
}
