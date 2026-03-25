import UIKit
import SwiftUI
import Social
import UniformTypeIdentifiers

/// NSExtensionViewController that hosts the SwiftUI share sheet UI.
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.91, green: 0.96, blue: 0.91, alpha: 1) // --bg-grid

        let vm = ShareViewModel()
        let swiftUIView = ShareSheetView(viewModel: vm, extensionContext: extensionContext)
        let hostingController = UIHostingController(rootView: swiftUIView)

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)

        // Extract content from the share context and kick off upload
        Task {
            await extractAndUpload(vm: vm)
        }
    }

    // MARK: - Content extraction

    private func extractAndUpload(vm: ShareViewModel) async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        var extractedURL: String? = nil
        var extractedText: String? = nil
        var extractedImageData: Data? = nil
        var sourceApp: String? = nil

        // Try to get source app bundle from extensionContext
        if let hostBundleID = extensionContext?.value(forKeyPath: "_hostBundleIdentifier") as? String {
            // Map bundle IDs to friendly names
            let appNames: [String: String] = [
                "com.apple.mobilesafari": "Safari",
                "com.google.chrome.ios": "Chrome",
                "com.burbn.instagram": "Instagram",
                "com.spotify.client": "Spotify",
                "com.apple.mobilemail": "Mail",
                "com.linkedin.LinkedIn": "LinkedIn",
                "com.atebits.Tweetie2": "Twitter/X",
                "com.zhiliaoapp.musically": "TikTok",
            ]
            sourceApp = appNames[hostBundleID] ?? hostBundleID.components(separatedBy: ".").last
        }

        for item in items {
            for provider in (item.attachments ?? []) {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        extractedURL = url.absoluteString
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                        extractedText = text
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let image = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? UIImage {
                        extractedImageData = image.jpegData(compressionQuality: 0.8)
                    }
                }
            }
        }

        await vm.upload(
            text: extractedText,
            url: extractedURL,
            imageData: extractedImageData,
            sourceApp: sourceApp,
            userNote: nil,   // will be set from the UI
            quickTag: nil
        )
    }
}


// MARK: - SwiftUI Share Sheet UI

struct ShareSheetView: View {
    @ObservedObject var viewModel: ShareViewModel
    let extensionContext: NSExtensionContext?

    @State private var userNote: String = ""
    @State private var selectedTag: String? = nil

    let tags: [(emoji: String, label: String, value: String)] = [
        ("🔔", "Remind", "reminder"),
        ("📅", "Event",  "event"),
        ("🎵", "Music",  "music"),
        ("💡", "Idea",   "software_idea"),
        ("🔗", "Save",   "link_save"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title bar (Y2K pixel style)
            titleBar

            // Content
            VStack(spacing: 12) {
                // Status / loading / result
                if viewModel.isLoading {
                    loadingView
                } else if let result = viewModel.result {
                    resultView(result)
                } else {
                    noteField
                    quickTagRow
                    dumplingButton
                }
            }
            .padding(16)
        }
        .background(Color(hex: "FAFAF0"))
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color(hex: "1A1A1A"), lineWidth: 3)
        )
        .shadow(color: Color(hex: "1A1A1A"), radius: 0, x: 5, y: 5)
        .padding(20)
    }

    // MARK: - Sub-views

    private var titleBar: some View {
        HStack {
            Text("📥 DUMPLING")
                .font(.custom("Courier New", size: 10).bold())
                .foregroundColor(Color(hex: "1A1A1A"))
            Spacer()
            // Window chrome buttons
            ForEach(["□", "—", "×"], id: \.self) { symbol in
                Button(action: {
                    if symbol == "×" { extensionContext?.completeRequest(returningItems: [], completionHandler: nil) }
                }) {
                    Text(symbol)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .frame(width: 16, height: 16)
                        .background(Color(hex: "FAFAF0"))
                        .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 2))
                        .shadow(color: Color(hex: "1A1A1A"), radius: 0, x: 2, y: 2)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: "B3D9FF"))
        .overlay(Rectangle().frame(height: 3).foregroundColor(Color(hex: "1A1A1A")), alignment: .bottom)
    }

    private var noteField: some View {
        TextField("Add a note... (optional)", text: $userNote)
            .font(.custom("Courier New", size: 12))
            .padding(8)
            .background(Color.white)
            .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 2))
    }

    private var quickTagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.value) { tag in
                    Button(action: { selectedTag = selectedTag == tag.value ? nil : tag.value }) {
                        HStack(spacing: 4) {
                            Text(tag.emoji).font(.system(size: 12))
                            Text(tag.label).font(.custom("Courier New", size: 9).bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selectedTag == tag.value ? Color(hex: "FFB3C6") : Color(hex: "FAFAF0"))
                        .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 2))
                        .shadow(color: Color(hex: "1A1A1A"), radius: 0,
                                x: selectedTag == tag.value ? 0 : 2,
                                y: selectedTag == tag.value ? 0 : 2)
                    }
                }
            }
        }
    }

    private var dumplingButton: some View {
        Button(action: { Task { await sendWithNote() } }) {
            Text("🥟  DUMPLING IT")
                .font(.custom("Courier New", size: 11).bold())
                .foregroundColor(Color(hex: "1A1A1A"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(hex: "FFB3C6"))
                .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 3))
                .shadow(color: Color(hex: "1A1A1A"), radius: 0, x: 4, y: 4)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            Text("PROCESSING...")
                .font(.custom("Courier New", size: 10).bold())
            // Pixel progress bar
            HStack(spacing: 2) {
                ForEach(0..<8) { i in
                    Rectangle()
                        .fill(Color(hex: "B3D9FF"))
                        .frame(width: 20, height: 12)
                        .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 1))
                }
            }
        }
        .padding(.vertical, 20)
    }

    private func resultView(_ result: ShareViewModel.UploadResult) -> some View {
        VStack(spacing: 12) {
            switch result {
            case .success(let msg):
                Text("✓ \(msg)")
                    .font(.custom("Courier New", size: 12).bold())
                    .foregroundColor(Color(hex: "1A1A1A"))
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color(hex: "B3FFD9"))
                    .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 2))
            case .failure(let err):
                Text("✗ \(err)")
                    .font(.custom("Courier New", size: 10))
                    .foregroundColor(Color(hex: "1A1A1A"))
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color(hex: "FFB3C6"))
                    .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 2))
            }

            Button("Close") {
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
            .font(.custom("Courier New", size: 10).bold())
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(hex: "FAFAF0"))
            .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 2))
            .shadow(color: Color(hex: "1A1A1A"), radius: 0, x: 2, y: 2)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func sendWithNote() async {
        await viewModel.upload(
            text: nil,
            url: nil,
            imageData: nil,
            sourceApp: nil,
            userNote: userNote.isEmpty ? nil : userNote,
            quickTag: selectedTag
        )
        // Auto-close on success after a short delay
        if case .success = viewModel.result {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}


// MARK: - Color helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
