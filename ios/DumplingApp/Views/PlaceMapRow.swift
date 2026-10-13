import MapKit
import SwiftUI

/// A small map of an item's place. Tapping it, or the link below, opens the place in Apple Maps.
struct PlaceMapRow: View {
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700)),
                interactionModes: []) {
                Marker(name, coordinate: coordinate)
            }
            .frame(height: 170)
            .clipShape(.rect(cornerRadius: 12))
            .onTapGesture(perform: openInMaps)
            .accessibilityHidden(true)

            Button(action: openInMaps) {
                Label("Open in Apple Maps", systemImage: "map")
            }
        }
        .padding(.vertical, 4)
    }

    private func openInMaps() {
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                             address: address.flatMap { MKAddress(fullAddress: $0, shortAddress: nil) })
        item.name = name
        item.openInMaps(launchOptions: nil)
    }
}
