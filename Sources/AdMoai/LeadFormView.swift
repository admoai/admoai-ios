import Foundation
#if canImport(UIKit)
    import UIKit
    #if canImport(WebKit)
        import WebKit
    #endif

    /// The container the app puts on screen for one form. It reports when the form is actually
    /// visible (in a window, not hidden, not transparent, app in the foreground) so the controller
    /// can tell the page.
    @MainActor
    final class LeadFormView: UIView {
        private weak var controller: LeadFormController?
        private var appInBackground = false
        private var reportedVisible = false

        init(content: UIView?, presentation: LeadFormPresentation, controller: LeadFormController) {
            self.controller = controller
            super.init(frame: .zero)
            backgroundColor = .clear
            guard let content else { return }
            content.translatesAutoresizingMaskIntoConstraints = false
            addSubview(content)
            // Full screen keeps the form inside the safe area; inline fills whatever room the app gave it.
            let guide = presentation == .fullScreen ? safeAreaLayoutGuide : nil
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: guide?.leadingAnchor ?? leadingAnchor),
                content.trailingAnchor.constraint(equalTo: guide?.trailingAnchor ?? trailingAnchor),
                content.topAnchor.constraint(equalTo: guide?.topAnchor ?? topAnchor),
                content.bottomAnchor.constraint(equalTo: guide?.bottomAnchor ?? bottomAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("LeadFormView is created by its controller")
        }

        override var isHidden: Bool {
            didSet { refreshVisibility() }
        }

        override var alpha: CGFloat {
            didSet { refreshVisibility() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self)
            if window != nil {
                appInBackground = UIApplication.shared.applicationState == .background
                center.addObserver(
                    self, selector: #selector(appDidEnterBackground),
                    name: UIApplication.didEnterBackgroundNotification, object: nil
                )
                center.addObserver(
                    self, selector: #selector(appWillEnterForeground),
                    name: UIApplication.willEnterForegroundNotification, object: nil
                )
            }
            refreshVisibility()
        }

        @objc private func appDidEnterBackground() {
            appInBackground = true
            refreshVisibility()
        }

        @objc private func appWillEnterForeground() {
            appInBackground = false
            refreshVisibility()
        }

        /// In a window, and neither this view nor an ancestor hidden or fully transparent.
        private var isOnScreen: Bool {
            guard window != nil, !appInBackground else { return false }
            var view: UIView? = self
            while let current = view {
                if current.isHidden || current.alpha <= 0.01 {
                    return false
                }
                view = current.superview
            }
            return true
        }

        private func refreshVisibility() {
            let visible = isOnScreen
            guard visible != reportedVisible else { return }
            reportedVisible = visible
            if visible {
                controller?.surfaceDidBecomeVisible()
            } else {
                controller?.surfaceDidBecomeHidden()
            }
        }
    }

    /// Hosts the form view for an app that presents it modally.
    @MainActor
    final class LeadFormViewController: UIViewController {
        private let formView: UIView

        init(formView: UIView, presentation: LeadFormPresentation) {
            self.formView = formView
            super.init(nibName: nil, bundle: nil)
            if presentation == .fullScreen {
                modalPresentationStyle = .fullScreen
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("LeadFormViewController is created by its controller")
        }

        override func loadView() {
            view = formView
        }
    }

    public extension LeadFormController {
        /// The view that shows the form: add it to your hierarchy for an inline form. One instance
        /// per controller. The form is told it is visible only while this view is in a window,
        /// not hidden, not transparent, and the app is in the foreground.
        var formView: UIView {
            if let existing = surfaceHost as? LeadFormView {
                return existing
            }
            var content: UIView?
            #if canImport(WebKit)
                content = (transport as? SecureFormWebView)?.webView
            #endif
            let view = LeadFormView(content: content, presentation: presentation, controller: self)
            surfaceHost = view
            return view
        }

        /// A view controller hosting ``formView``, for a form the app presents modally. Full screen
        /// forms use `.fullScreen` modal presentation. Create it once per controller.
        var formViewController: UIViewController {
            LeadFormViewController(formView: formView, presentation: presentation)
        }
    }
#endif
