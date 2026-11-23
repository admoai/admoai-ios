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
        /// The scene (or, for a window with no scene, the app) the form is in is in the background.
        private var inBackground = false
        private var reportedVisible = false
        /// `isHidden` and `alpha` of every ancestor: a change anywhere up the chain moves visibility.
        private var ancestorObservations: [NSKeyValueObservation] = []

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

        override func willMove(toSuperview newSuperview: UIView?) {
            super.willMove(toSuperview: newSuperview)
            ancestorObservations = []
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            observeAncestors()
            refreshVisibility()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self)
            if let window {
                // A window in a scene follows its scene; one without a scene follows the app.
                let scene = window.windowScene
                inBackground = Self.isInBackground(
                    sceneState: scene?.activationState,
                    applicationState: UIApplication.shared.applicationState
                )
                if scene != nil {
                    center.addObserver(
                        self, selector: #selector(didEnterBackground),
                        name: UIScene.didEnterBackgroundNotification, object: scene
                    )
                    center.addObserver(
                        self, selector: #selector(willEnterForeground),
                        name: UIScene.willEnterForegroundNotification, object: scene
                    )
                } else {
                    center.addObserver(
                        self, selector: #selector(didEnterBackground),
                        name: UIApplication.didEnterBackgroundNotification, object: nil
                    )
                    center.addObserver(
                        self, selector: #selector(willEnterForeground),
                        name: UIApplication.willEnterForegroundNotification, object: nil
                    )
                }
            }
            observeAncestors()
            refreshVisibility()
        }

        @objc private func didEnterBackground() {
            inBackground = true
            refreshVisibility()
        }

        @objc private func willEnterForeground() {
            inBackground = false
            refreshVisibility()
        }

        /// A scene is in the background when it says so (or is not attached); a window with no
        /// scene follows the application. Foreground active and inactive both count as foreground.
        nonisolated static func isInBackground(
            sceneState: UIScene.ActivationState?,
            applicationState: UIApplication.State
        ) -> Bool {
            if let sceneState {
                return sceneState == .background || sceneState == .unattached
            }
            return applicationState == .background
        }

        /// Visible: in a window, in the foreground, and no view in the chain (this one included)
        /// hidden or transparent.
        nonisolated static func isVisible(
            hasWindow: Bool,
            inBackground: Bool,
            chain: [(isHidden: Bool, alpha: CGFloat)]
        ) -> Bool {
            guard hasWindow, !inBackground else { return false }
            return !chain.contains { $0.isHidden || $0.alpha <= 0.01 }
        }

        /// Rebuilds the observers of every ancestor's `isHidden` and `alpha`. The view's own are
        /// covered by its property observers.
        private func observeAncestors() {
            ancestorObservations = []
            var view = superview
            while let ancestor = view {
                ancestorObservations.append(ancestor.observe(\.isHidden, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.refreshVisibility() }
                })
                ancestorObservations.append(ancestor.observe(\.alpha, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.refreshVisibility() }
                })
                view = ancestor.superview
            }
        }

        private var isOnScreen: Bool {
            var chain: [(isHidden: Bool, alpha: CGFloat)] = []
            var view: UIView? = self
            while let current = view {
                chain.append((current.isHidden, current.alpha))
                view = current.superview
            }
            return Self.isVisible(hasWindow: window != nil, inBackground: inBackground, chain: chain)
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
        ///
        /// Experimental: import with `@_spi(InteractiveExperience) import AdMoai`.
        @_spi(InteractiveExperience)
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
        ///
        /// Experimental: import with `@_spi(InteractiveExperience) import AdMoai`.
        @_spi(InteractiveExperience)
        var formViewController: UIViewController {
            LeadFormViewController(formView: formView, presentation: presentation)
        }
    }
#endif
