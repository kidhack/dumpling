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

        let hostingController = UIHostingController(
            rootView: ShareSheetView(viewModel: viewModel, extensionContext: extensionContext)
        )
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


