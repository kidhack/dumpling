import UIKit
import SwiftUI
import UniformTypeIdentifiers
import OSLog

private let logger = Logger(subsystem: "com.kidhack.dumpling.ShareExtension", category: "ShareViewController")

class ShareViewController: UIViewController {

    private let viewModel = ShareViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("ShareViewController viewDidLoad fired")

        view.backgroundColor = .clear

        let hostingController = UIHostingController(
            rootView: ShareSheetView(viewModel: viewModel, extensionContext: extensionContext)
        )
        hostingController.view.backgroundColor = .clear
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

        Task { await extractContent() }
    }

    // MARK: - Content extraction

    private func extractContent() async {
        defer { viewModel.isExtracting = false }

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        logger.info("Extraction start: \(items.count) input item(s), \(providers.count) attachment(s)")

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                logger.info("Attachment type found: url")
                if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    viewModel.extractedURL = url.absoluteString
                    logger.info("Extracted URL: \(url.absoluteString, privacy: .public)")
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                logger.info("Attachment type found: plainText")
                if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    viewModel.extractedText = text
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                logger.info("Attachment type found: image")
                viewModel.hasImage = true
            }
        }

        if viewModel.extractedURL == nil, viewModel.extractedText == nil, !viewModel.hasImage {
            logger.error("Extraction finished with no usable content")
        }
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
            titleBar

            VStack(spacing: 12) {
                if viewModel.isLoading {
                    loadingView
                } else if let result = viewModel.result {
                    resultView(result)
                } else {
                    contentPreview
                    noteField
                    quickTagRow
                    dumplingButton
                }
            }
            .padding(16)
        }
        .background(Color(hex: "FAFAF0"))
        .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 3))
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
            ForEach(["□", "—", "×"], id: \.self) { symbol in
                Button(action: {
                    if symbol == "×" { extensionContext?.completeRequest(returningItems: [], completionHandler: nil) }
                }) {
                    Text(symbol)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "1A1A1A"))
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

    private var contentPreview: some View {
        Text(viewModel.isExtracting ? "Reading…" : viewModel.previewText)
            .font(.custom("Courier New", size: 10))
            .foregroundColor(Color(hex: "1A1A1A"))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(hex: "FFF3B3"))
            .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 2))
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
                        .foregroundColor(Color(hex: "1A1A1A"))
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
            .padding(.bottom, 2)
            .padding(.trailing, 2)
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
        .disabled(viewModel.isExtracting)
        .opacity(viewModel.isExtracting ? 0.5 : 1)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            Text("PROCESSING...")
                .font(.custom("Courier New", size: 10).bold())
            HStack(spacing: 2) {
                ForEach(0..<8, id: \.self) { _ in
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
            .foregroundColor(Color(hex: "1A1A1A"))
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
        let trimmed = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.submit(userNote: trimmed.isEmpty ? nil : trimmed, quickTag: selectedTag)
        if case .success = viewModel.result {
            try? await Task.sleep(for: .seconds(1.2))
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
