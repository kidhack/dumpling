import SwiftUI

struct SettingsView: View {
    @State private var relayURL: String = AppGroup.relayURL
    @State private var authToken: String = AppGroup.authToken
    @State private var saved = false

    var body: some View {
        ZStack {
            Color.dCream.ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar

                ScrollView {
                    VStack(spacing: 16) {
                        fieldGroup(label: "RELAY URL", hint: "https://dumpling.fly.dev") {
                            TextField("https://...", text: $relayURL)
                                .font(.custom("Courier New", size: 12))
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(10)
                                .background(Color.white)
                                .pixelBorder(width: 2)
                        }

                        fieldGroup(label: "AUTH TOKEN", hint: "Your personal relay token") {
                            SecureField("dumpling-token-...", text: $authToken)
                                .font(.custom("Courier New", size: 12))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(10)
                                .background(Color.white)
                                .pixelBorder(width: 2)
                        }

                        saveButton

                        if saved {
                            Text("✓ SAVED")
                                .font(.custom("Courier New", size: 11).bold())
                                .foregroundColor(.dBlack)
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .background(Color.dMint)
                                .pixelBorder(width: 2)
                                .transition(.opacity)
                        }

                        phaseNote
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Sub-views

    private var titleBar: some View {
        HStack {
            Text("⚙️ SETTINGS")
                .font(.custom("Courier New", size: 11).bold())
                .foregroundColor(.dBlack)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.dLavender)
        .overlay(Rectangle().frame(height: 3).foregroundColor(.dBlack), alignment: .bottom)
    }

    private func fieldGroup(label: String, hint: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.custom("Courier New", size: 9).bold())
                .foregroundColor(.dBlack.opacity(0.6))
            field()
            Text(hint)
                .font(.custom("Courier New", size: 9))
                .foregroundColor(.dBlack.opacity(0.4))
        }
    }

    private var saveButton: some View {
        Button {
            AppGroup.relayURL = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
            AppGroup.authToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
            withAnimation { saved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { saved = false }
            }
        } label: {
            Text("💾  SAVE SETTINGS")
                .font(.custom("Courier New", size: 11).bold())
                .foregroundColor(.dBlack)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.dPink)
                .pixelBorder(width: 3)
                .pixelShadow(4)
        }
    }

    private var phaseNote: some View {
        Text("Phase 2: relay + Mac agent coming soon.\nSettings are shared with the share extension via App Group.")
            .font(.custom("Courier New", size: 9))
            .foregroundColor(.dBlack.opacity(0.4))
            .multilineTextAlignment(.center)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.dButter.opacity(0.5))
            .pixelBorder(width: 1)
    }
}
