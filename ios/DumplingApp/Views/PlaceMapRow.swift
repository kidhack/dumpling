import MapKit
import SwiftUI

/// A small map of an item's place. Tapping it, or the link below, opens the place in Apple Maps.
struct PlaceMapRow: View {
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        // Tapping the map opens the place in Apple Maps.
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700)),
            interactionModes: []) {
            Marker(name, coordinate: coordinate)
        }
        .frame(height: 170)
        .clipShape(.rect(cornerRadius: 12))
        .onTapGesture(perform: openInMaps)
        .accessibilityElement()
        .accessibilityLabel("Map of \(name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens in Apple Maps")
        .accessibilityAction { openInMaps() }
        .padding(.vertical, 4)
    }

    private func openInMaps() {
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                             address: address.flatMap { MKAddress(fullAddress: $0, shortAddress: nil) })
        item.name = name
        item.openInMaps(launchOptions: nil)
    }
}
