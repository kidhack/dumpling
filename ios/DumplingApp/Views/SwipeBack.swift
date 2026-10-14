import SwiftUI
import UIKit

extension View {
    /// Swiping back works even though screens hide the system bar (which turns it off): from the left edge, or
    /// (iOS 26) from anywhere on the background. Swipes that start on a row stay with the row's swipe actions.
    /// Apply once, inside the NavigationStack.
    func swipeBackEnabled() -> some View {
        background(SwipeBackEnabler().frame(width: 0, height: 0))
    }
}

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let navigation = navigationController else { return }
            for recognizer in [navigation.interactivePopGestureRecognizer,
                               navigation.interactiveContentPopGestureRecognizer].compactMap({ $0 }) {
                recognizer.delegate = self
                recognizer.isEnabled = true
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // The edge swipe always works; the anywhere swipe leaves rows to their own swipe actions.
            guard gestureRecognizer === navigationController?.interactiveContentPopGestureRecognizer else { return true }
            var view = touch.view
            while let current = view {
                if current is UICollectionViewCell || current is UITableViewCell { return false }
                view = current.superview
            }
            return true
        }
    }
}
