import CoreLocation
import SwiftUI
import UIKit

/// "Notify Me Nearby" in a place's details, with the hours it goes by and anything stopping it from working.
struct NearbyRow: View {
    let item: Item

    @State private var isWorking = false
    @State private var isCheckingHours = false
    @State private var notificationsOff = false

    private var alerts: NearbyAlerts { .shared }
    private var isOn: Bool { alerts.isWatching(item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { isOn }, set: change)) {
                Label("Notify Me Nearby", systemImage: "bell.badge")
            }
            .disabled(isWorking)

            if notificationsOff {
                note("Notifications are off for Dumpling.", settings: true)
            } else if isOn {
                hours
                switch alerts.authorization {
                case .authorizedAlways:
                    EmptyView()
                case .denied, .restricted:
                    note("Location access is off for Dumpling.", settings: true)
                default:
                    note("Works only while Dumpling is open. To be notified any time, allow location access Always.",
                         settings: alerts.authorization == .authorizedWhenInUse)
                }
            }
        }
        .task(id: isOn) {
            guard isOn, alerts.watches[item.id]?.hours == nil, item.contentURL != nil else { return }
            isCheckingHours = true
            await alerts.loadHours(for: item)
            isCheckingHours = false
        }
    }

    @ViewBuilder
    private var hours: some View {
        if let hours = alerts.watches[item.id]?.hours {
            VStack(alignment: .leading, spacing: 2) {
                Text("Only while open")
                ForEach(hours.summary, id: \.self) { Text($0).foregroundStyle(.secondary) }
            }
            .font(.footnote)
        } else if isCheckingHours {
            Text("Checking hours…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("Hours unknown, so you'll be notified any time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func note(_ text: String, settings: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if settings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.footnote)
            }
        }
    }

    private func change(_ on: Bool) {
        isWorking = true
        Task {
            if on {
                notificationsOff = await alerts.watch(item) == .notificationsOff
            } else {
                notificationsOff = false
                await alerts.unwatch(item)
            }
            isWorking = false
        }
    }
}
