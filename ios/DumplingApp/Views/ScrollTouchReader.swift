import SwiftUI
import UIKit

/// Reports when the user starts and stops dragging the enclosing List.
/// SwiftUI's onScrollPhaseChange never fires for a List's overscroll bounce (verified on device),
/// so this reads the underlying UIScrollView's pan gesture instead.
struct ScrollTouchReader: UIViewRepresentable {
    var onDragChanged: (Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onDragChanged = onDragChanged
        DispatchQueue.main.async { context.coordinator.attach(near: view) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onDragChanged: onDragChanged) }

    @MainActor
    final class Coordinator: NSObject {
        var onDragChanged: (Bool) -> Void
        private weak var scrollView: UIScrollView?

        init(onDragChanged: @escaping (Bool) -> Void) {
            self.onDragChanged = onDragChanged
        }

        /// Walks up from the background view to the nearest ancestor that contains a scroll view.
        func attach(near view: UIView) {
            guard scrollView == nil else { return }
            var ancestor = view.superview
            while let current = ancestor {
                if let found = Self.firstScrollView(in: current, excluding: view) {
                    scrollView = found
                    found.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
                    return
                }
                ancestor = current.superview
            }
        }

        private static func firstScrollView(in root: UIView, excluding: UIView) -> UIScrollView? {
            var queue: [UIView] = [root]
            while !queue.isEmpty {
                let next = queue.removeFirst()
                if next !== excluding, let scroll = next as? UIScrollView { return scroll }
                queue.append(contentsOf: next.subviews)
            }
            return nil
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began: onDragChanged(true)
            case .ended, .cancelled, .failed: onDragChanged(false)
            default: break
            }
        }
    }
}
