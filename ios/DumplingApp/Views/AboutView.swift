import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(.rect(cornerRadius: 26, style: .continuous))
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text("Dumpling")
                        .font(.title.bold())
                    Text("Version \(version)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Share anything to Dumpling. It sorts it on your iPhone and files events and tasks into Calendar and Reminders.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Link(destination: URL(string: "https://thedumpling.app")!) {
                    Label("thedumpling.app", systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()
            }
            .padding(.top, 32)
            .frame(maxWidth: .infinity)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
