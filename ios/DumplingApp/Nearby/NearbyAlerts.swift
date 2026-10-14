import CoreData
import CoreLocation
import Observation
import OSLog
import UserNotifications

private let logger = Logger(subsystem: "com.kidhack.dumpling", category: "Nearby")

/// "Notify Me Nearby": watches places the user picked and sends a notification on arriving close by, when
/// the place is open (if its hours are known). The setting lives on this device, not on the item, so turning
/// it on for a place in a shared list doesn't ping anyone else.
@MainActor @Observable
final class NearbyAlerts: NSObject {
    static let shared = NearbyAlerts()

    struct Watch: Codable {
        var name: String
        var latitude: Double
        var longitude: Double
        var hours: OpeningHours?
        var lastAlert: Date?

        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    }

    /// About two city blocks.
    static let radius: CLLocationDistance = 200
    /// iOS watches at most 20 conditions per app; one of them is the reframe circle.
    private static let maxPlaces = 19
    private static let reframeID = "reframe"
    private static let storeKey = "nearbyWatches.v1"
    /// At most one notification per place a day.
    private static let quietPeriod: TimeInterval = 20 * 60 * 60

    private(set) var watches: [UUID: Watch] = [:]
    private(set) var authorization: CLAuthorizationStatus
    /// The item a tapped notification asks to show.
    var openItemID: UUID?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var monitor: CLMonitor?

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let saved = try? JSONDecoder().decode([UUID: Watch].self, from: data) {
            watches = saved
        }
    }

    func isWatching(_ item: Item) -> Bool { watches[item.id] != nil }

    // MARK: - Turning it on and off

    enum WatchResult { case watching, notificationsOff, noCoordinates }

    func watch(_ item: Item) async -> WatchResult {
        guard let latitude = item.latitude, let longitude = item.longitude else { return .noCoordinates }
        let allowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        guard allowed else { return .notificationsOff }

        var watch = Watch(name: item.displayTitle, latitude: latitude, longitude: longitude)
        // Already there: don't ping for the place the user is standing in.
        if let here = manager.location, here.distance(from: watch.location) < Self.radius { watch.lastAlert = .now }
        watches[item.id] = watch
        save()
        // Notifications with Dumpling closed need Always. iOS asks once; after that it's in Settings.
        if authorization != .authorizedAlways { manager.requestAlwaysAuthorization() }
        await sync()
        return .watching
    }

    /// Reads the place's page for its hours. Separate from `watch` so the switch responds right away.
    func loadHours(for item: Item) async {
        guard watches[item.id]?.hours == nil,
              let url = item.contentURL.flatMap(URL.init(string:)),
              let hours = await PageReader.fetch(url)?.hours,
              watches[item.id] != nil else { return }
        watches[item.id]?.hours = hours
        save()
    }

    func unwatch(_ item: Item) async {
        watches[item.id] = nil
        save()
        await sync()
    }

    // MARK: - Monitoring

    /// Called at launch, including when iOS relaunches Dumpling in the background for an arrival.
    func start() {
        guard !watches.isEmpty || monitor != nil else { return }
        Task { await sync() }
    }

    private func ensureMonitor() async -> CLMonitor {
        if let monitor { return monitor }
        let monitor = await CLMonitor("DumplingNearby")
        self.monitor = monitor
        Task {
            do {
                for try await event in await monitor.events {
                    await handle(identifier: event.identifier, state: event.state)
                }
            } catch {
                logger.error("Nearby monitoring stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
        return monitor
    }

    /// Watches the closest places (iOS allows 20), and with more than that, a wide circle around the user
    /// so leaving it re-picks the closest ones.
    func sync() async {
        let monitor = await ensureMonitor()
        let here = manager.location
        let ranked = watches.sorted { a, b in
            guard let here else { return a.key.uuidString < b.key.uuidString }
            return here.distance(from: a.value.location) < here.distance(from: b.value.location)
        }
        let wanted = Dictionary(uniqueKeysWithValues: ranked.prefix(Self.maxPlaces).map { ($0.key.uuidString, $0.value) })
        let existing = await monitor.identifiers
        for id in existing where wanted[id] == nil { await monitor.remove(id) }
        for (id, watch) in wanted where !existing.contains(id) {
            let circle = CLMonitor.CircularGeographicCondition(center: watch.location.coordinate, radius: Self.radius)
            await monitor.add(circle, identifier: id, assuming: .unsatisfied)
        }
        if watches.count > Self.maxPlaces, let here {
            let circle = CLMonitor.CircularGeographicCondition(center: here.coordinate, radius: 2_000)
            await monitor.add(circle, identifier: Self.reframeID, assuming: .satisfied)
        }
    }

    private func handle(identifier: String, state: CLMonitor.Event.State) async {
        if identifier == Self.reframeID {
            if state == .unsatisfied { await sync() }
            return
        }
        guard state == .satisfied, let id = UUID(uuidString: identifier), var watch = watches[id] else { return }
        guard let item = Item.with(id: id, in: Persistence.shared.viewContext) else {
            // The item was deleted.
            watches[id] = nil
            save()
            await sync()
            return
        }
        if item.isArchived { return }
        if let last = watch.lastAlert, Date.now.timeIntervalSince(last) < Self.quietPeriod { return }
        if watch.hours?.isOpen(at: .now) == false { return }
        watch.lastAlert = .now
        watches[id] = watch
        save()
        await notify(item: item, watch: watch)
    }

    private func notify(item: Item, watch: Watch) async {
        let content = UNMutableNotificationContent()
        content.title = item.displayTitle
        var body = "You're about two blocks away."
        if let closes = watch.hours?.closing(after: .now) {
            body += " Open until \(OpeningHours.clock(closes))."
        } else if watch.hours == nil {
            body += " Check the hours before you go."
        }
        content.body = body
        content.sound = .default
        content.userInfo = ["itemID": item.id.uuidString]
        let request = UNNotificationRequest(identifier: "nearby-\(item.id.uuidString)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("Nearby notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(watches) { UserDefaults.standard.set(data, forKey: Self.storeKey) }
    }
}

extension NearbyAlerts: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }
}
