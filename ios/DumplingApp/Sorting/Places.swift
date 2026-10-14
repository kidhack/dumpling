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

    #if os(iOS)
    /// Opens a saved place in Apple Maps on the business's own page (hours, photos, reviews) rather than a dropped
    /// pin: the place is searched by name around its pin, and the closest match within 300 m is opened. With no
    /// match, the pin opens as before.
    @MainActor
    static func openInMaps(name: String, address: String?, coordinate: CLLocationCoordinate2D) async {
        let pin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = Sorter.placeName(name)
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 2_000, longitudinalMeters: 2_000)
        request.regionPriority = .required
        request.resultTypes = .pointOfInterest
        let matches = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        if let business = matches.min(by: { $0.location.distance(from: pin) < $1.location.distance(from: pin) }),
           business.location.distance(from: pin) < 300 {
            business.openInMaps(launchOptions: nil)
            return
        }
        // The name as saved may not match Apple's ("Tommy Dinic's Roast Pork" vs "Tommy DiNic's"): try the
        // businesses right by the pin that share a distinctive word with it.
        if let business = await nearbyBusiness(named: name, at: pin) {
            business.openInMaps(launchOptions: nil)
            return
        }
        let dropped = MKMapItem(location: pin, address: address.flatMap { MKAddress(fullAddress: $0, shortAddress: nil) })
        dropped.name = name
        dropped.openInMaps(launchOptions: nil)
    }
    #endif

    /// The closest business within 150 m of `pin` whose name shares a word of 4+ letters with `name`.
    @MainActor
    static func nearbyBusiness(named name: String, at pin: CLLocation) async -> MKMapItem? {
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 4 })
        }
        let wanted = words(Sorter.placeName(name))
        guard !wanted.isEmpty else { return nil }
        let request = MKLocalPointsOfInterestRequest(center: pin.coordinate, radius: 150)
        let nearby = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        return nearby
            .filter { !words($0.name ?? "").isDisjoint(with: wanted) }
            .min { $0.location.distance(from: pin) < $1.location.distance(from: pin) }
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
