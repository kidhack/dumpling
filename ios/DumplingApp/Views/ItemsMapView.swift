import CoreData
import MapKit
import SwiftUI

/// The places in a tab, shown in place of its list. Places without a map position are looked up when the
/// map appears; any that can't be found are named at the top, linking to their details to add an address.
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
    @State private var notFound: [Item] = []
    @Namespace private var mapScope
    /// Places pinned to a city center before lookups searched by name get one more try.
    private static let recheckedKey = "recheckedCityPins.v1"

    struct Pin: Identifiable {
        let item: Item
        let coordinate: CLLocationCoordinate2D
        var id: UUID { item.id }
    }

    static func pins(for items: [Item], lookedUp: [UUID: CLLocationCoordinate2D] = [:]) -> [Pin] {
        items.compactMap { item in
            if let coordinate = lookedUp[item.id] { return Pin(item: item, coordinate: coordinate) }
            if let latitude = item.latitude, let longitude = item.longitude {
                return Pin(item: item, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            }
            return nil
        }
    }

    private var pins: [Pin] { Self.pins(for: items, lookedUp: lookedUp) }

    var body: some View {
        Map(position: $position, selection: $selection, scope: mapScope) {
            ForEach(pins) { pin in
                Marker(pin.item.displayTitle, systemImage: CategoryKind.location.systemImage,
                       coordinate: pin.coordinate)
                    .tint(CategoryKind.pinTint)
                    .tag(pin.id)
            }
            UserAnnotation()
        }
        // The map's own corner controls would land under the header; the buttons are placed below instead.
        .mapControls {}
        // Runs edge to edge, under the header and filter row.
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if isLookingUp {
                status { ProgressView().controlSize(.small); Text("Finding places…") }
            } else if let first = notFound.first {
                NavigationLink(value: first) {
                    status {
                        Image(systemName: "mappin.slash")
                        Text(notFound.count == 1 ? "\(first.displayTitle) isn't on the map"
                                                 : "\(notFound.count) places aren't on the map")
                            .lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Level with the Map / List pill. Tapping it asks for location permission the first time.
            VStack(spacing: 8) {
                MapCompass(scope: mapScope)
                MapUserLocationButton(scope: mapScope)
            }
            .buttonBorderShape(.circle)
            .padding(.trailing, 16)
            .padding(.bottom, 4)
        }
        .mapScope(mapScope)
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

    private func status<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6, content: content)
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: .capsule)
            .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
            .padding(.top, 8)
    }

    /// Finds positions for places without one, saving them where the user can edit the item.
    private func lookUpMissing() async {
        defer { isLookingUp = false }
        let recheck = !UserDefaults.standard.bool(forKey: Self.recheckedKey)
        let missing = items.filter { item in
            if item.latitude == nil { return true }
            // Positions from geocoding just a city ("Philadelphia, PA") land on the city center.
            return recheck && !(item.location.map(Processor.isStreetAddress) ?? true)
                && !(item.contentURL?.contains("google") ?? false) && !(item.contentURL?.contains("maps") ?? false)
        }
        guard !missing.isEmpty else { return }
        let near = Self.pins(for: items).first?.coordinate
        var unfound: [Item] = []
        for item in missing {
            guard let place = await Processor.findPlace(for: item, near: near), let coordinate = place.coordinate else {
                if item.latitude == nil { unfound.append(item) }
                continue
            }
            lookedUp[item.id] = coordinate
            if item.list.map(Sharing.canEdit) ?? true {
                item.latitude = coordinate.latitude
                item.longitude = coordinate.longitude
                // Fill in the city (and the rest) when the saved address didn't have one.
                if let full = place.address, !(item.location.map(Places.hasCity) ?? false) { item.location = full }
            }
        }
        notFound = unfound
        if context.hasChanges { try? context.save() }
        if recheck { UserDefaults.standard.set(true, forKey: Self.recheckedKey) }
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
        Task { await Places.openInMaps(name: item.displayTitle, address: item.location, coordinate: coordinate) }
    }
}
