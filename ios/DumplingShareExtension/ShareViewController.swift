import UIKit
import OSLog

private let logger = Logger(subsystem: "com.kidhack.dumpling.ShareExtension", category: "ShareViewController")

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("ShareViewController viewDidLoad fired")

        view.backgroundColor = UIColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 1)

        let label = UILabel()
        label.text = "🥟 Dumpling'd!"
        label.textAlignment = .center
        label.font = UIFont(name: "Courier New", size: 18) ?? .systemFont(ofSize: 18)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
