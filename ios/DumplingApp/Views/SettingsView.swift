import SwiftUI

struct SettingsView: View {
    @State private var relayURL: String = AppGroup.relayURL
    @State private var authToken: String = AppGroup.authToken

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $relayURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Relay URL")
                }

                Section {
                    SecureField("Token", text: $authToken)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Auth Token")
                } footer: {
                    Text("Used in Phase 2 to send items to the relay. Shared with the share extension via the App Group.")
                }
            }
            .navigationTitle("Settings")
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: relayURL) { _, value in
                AppGroup.relayURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .onChange(of: authToken) { _, value in
                AppGroup.authToken = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}
