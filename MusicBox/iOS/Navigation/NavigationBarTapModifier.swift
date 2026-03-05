#if os(iOS)
import SwiftUI
import UIKit

private struct NavigationBarTapModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.background {
            NavigationBarTapHelper(action: action)
                .frame(width: 0, height: 0)
        }
    }
}

private struct NavigationBarTapHelper: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.action = action
        DispatchQueue.main.async {
            context.coordinator.setupIfNeeded(from: uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void
        private weak var installedNavBar: UINavigationBar?
        private var tapGesture: UITapGestureRecognizer?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func setupIfNeeded(from view: UIView) {
            guard installedNavBar == nil else { return }
            guard let navBar = findNavBar(from: view) else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.delegate = self
            navBar.addGestureRecognizer(tap)
            tapGesture = tap
            installedNavBar = navBar
        }

        private func findNavBar(from view: UIView) -> UINavigationBar? {
            var responder: UIResponder? = view
            while let next = responder?.next {
                if let vc = next as? UIViewController,
                   let navBar = vc.navigationController?.navigationBar {
                    return navBar
                }
                responder = next
            }
            return nil
        }

        @objc private func handleTap() {
            action()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navBar = gestureRecognizer.view as? UINavigationBar else { return false }
            let location = gestureRecognizer.location(in: navBar)
            // Don't intercept taps on bar button items or other controls
            if let hitView = navBar.hitTest(location, with: nil), hitView is UIControl {
                return false
            }
            return true
        }

        deinit {
            if let tap = tapGesture {
                tap.view?.removeGestureRecognizer(tap)
            }
        }
    }
}

extension View {
    func onNavigationBarTap(perform action: @escaping () -> Void) -> some View {
        modifier(NavigationBarTapModifier(action: action))
    }
}
#endif
