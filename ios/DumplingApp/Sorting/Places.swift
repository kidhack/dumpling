import Foundation
import MapKit

struct Place: Sendable, Equatable {
    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum Places {

    /// Map share links carry the place in their (redirected) URL; their pages have nothing useful.
    /// - Google Maps app: google.com/maps?q=Name,+Street,+City
    /// - Google app: google.com/search?q=Name&source=…/loc/… (name only)
    /// - Apple Maps: maps.apple.com/?q=Name&address=…&ll=lat,lng
    static func fromMapsLink(_ url: URL) -> Place? {
        guard let host = url.host()?.lowercased() else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value?
                .replacingOccurrences(of: "+", with: " ")
                .trimmingCharacters(in: .whitespaces)
                .nilIfEmpty
        }
        let path = url.path()

        if host == "maps.apple.com" {
            let coords = value("ll")?.split(separator: ",").compactMap { Double($0) }
            guard let name = value("q") ?? value("address") else { return nil }
            return Place(name: name, address: value("address"),
                         latitude: coords?.count == 2 ? coords?[0] : nil,
                         longitude: coords?.count == 2 ? coords?[1] : nil)
        }

        guard host == "google.com" || host.hasSuffix(".google.com") else { return nil }
        if path.hasPrefix("/maps") {
            if let q = value("q") { return split(q) }
            if let range = path.range(of: "/place/") {
                let rest = path[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
                let decoded = (rest.removingPercentEncoding ?? rest).replacingOccurrences(of: "+", with: " ")
                return decoded.isEmpty ? nil : split(decoded)
            }
            return nil
        }
        if path == "/search", value("source")?.contains("/loc/") == true, let q = value("q") {
            return Place(name: q)
        }
        return nil
    }

    /// "Name, Street, City, ST 12345" -> name + address.
    private static func split(_ text: String) -> Place {
        let parts = text.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return Place(name: parts[0], address: parts.count > 1 ? parts[1].nilIfEmpty : nil)
    }

    /// Finds the place in Apple Maps for its coordinates and full address. Name-only lookups are
    /// biased toward `near` (the user's most recent saved place) since names like "Monk's Cafe" repeat.
    @MainActor
    static func lookup(_ place: Place, near: CLLocationCoordinate2D?) async -> Place? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [place.name, place.address].compactMap { $0 }.joined(separator: ", ")
        // Without a city ("1206 Frankford Ave", or just a name), look only near the user's other places. As a mere
        // preference, a far-off weak match could still win (Post Haste in Philadelphia became a street in Indiana).
        if place.address.map(hasCity) != true, let near {
            request.region = MKCoordinateRegion(center: near, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
            request.regionPriority = .required
        }
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        return Place(
            name: item.name ?? place.name,
            address: item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)?
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression) ?? place.address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    /// Whether an address names its city. "1206 Frankford avenue" doesn't, so geocoding it alone guesses
    /// which Frankford Avenue.
    static func hasCity(_ address: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue),
              let match = detector.firstMatch(in: address, range: NSRange(address.startIndex..., in: address))
        else { return false }
        return match.addressComponents?[.city] != nil
    }

    @MainActor
    static func geocode(_ address: String) async -> CLLocationCoordinate2D? {
        guard let request = MKGeocodingRequest(addressString: address),
              let item = try? await request.mapItems.first else { return nil }
        return item.location.coordinate
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
