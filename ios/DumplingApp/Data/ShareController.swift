import CloudKit
import CoreData
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.kidhack.dumpling", category: "Sharing")

/// Shows Apple's sharing sheet (invite people, set permissions, stop sharing) for a list.
@MainActor
final class ShareController: NSObject, UICloudSharingControllerDelegate {
    static let shared = ShareController()
    private var list: ItemList?

    func present(_ list: ItemList) async {
        do {
            let share = try await Sharing.shareList(list)
            self.list = list
            let controller = UICloudSharingController(share: share,
                                                      container: CKContainer(identifier: Persistence.cloudKitContainer))
            controller.delegate = self
            controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
            Self.topViewController()?.present(controller, animated: true)
        } catch {
            logger.error("Couldn't prepare share: \(error.localizedDescription, privacy: .public)")
        }
    }

    func itemTitle(for csc: UICloudSharingController) -> String? { list?.name }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        logger.error("Sharing sheet failed to save: \(error.localizedDescription, privacy: .public)")
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        guard let share = csc.share, let list else { return }
        Sharing.persistUpdatedShare(share, for: list)
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        guard let list else { return }
        Task { await Sharing.stopSharing(list) }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Accepts list invitations, whether Dumpling is running or launched by tapping the invite.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in Sharing.accept(metadata) }
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let metadata = options.cloudKitShareMetadata else { return }
        Task { @MainActor in Sharing.accept(metadata) }
    }
}
