import Foundation
#if canImport(WebKit)
    import WebKit
    #if canImport(OSLog)
        import OSLog
    #endif

    /// scheme + host + port of a URL or a WebKit security origin, compared the way a browser does
    /// (port 0, or an absent one, is the scheme's default).
    struct FormOrigin: Equatable {
        let scheme: String
        let host: String
        let port: Int

        init?(url: URL) {
            guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else {
                return nil
            }
            self.init(scheme: scheme, host: host, port: url.port ?? 0)
        }

        init(scheme: String, host: String, port: Int) {
            self.scheme = scheme.lowercased()
            self.host = host.lowercased()
            switch (port, self.scheme) {
            case (0, "https"): self.port = 443
            case (0, "http"): self.port = 80
            default: self.port = port
            }
        }

        init(_ origin: WKSecurityOrigin) {
            self.init(scheme: origin.protocol, host: origin.host, port: origin.port)
        }
    }

    /// The secure surface of a Lead Generation form: a WKWebView with no persistent storage that
    /// accepts one page, the launch URL's origin, in its main frame, and talks to it only through
    /// the `AdmoaiBridge` object.
    @MainActor
    final class SecureFormWebView: NSObject, LeadFormTransport {
        static let handlerName = "AdmoaiBridge"

        let webView: WKWebView
        var onMessage: ((String) -> Void)?
        var onLoadFailed: ((LeadFormLoadFailure) -> Void)?
        /// Counts, for tests and for support: how many page messages / navigations were refused.
        private(set) var refusedMessageCount = 0
        private(set) var cancelledNavigationCount = 0

        private let origin: FormOrigin?
        private let logger: Logger
        private var isTornDown = false
        /// The one navigation the surface lets through: the load the SDK itself just asked for.
        private var expectedLoad: URL?
        /// Whether a page has committed in the main frame since the last load the SDK started.
        private var hasCommitted = false

        init(launchURL: URL, logger: Logger) {
            origin = FormOrigin(url: launchURL)
            self.logger = logger

            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            let controller = WKUserContentController()
            controller.addUserScript(WKUserScript(
                source: Self.bridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
            configuration.userContentController = controller
            webView = WKWebView(frame: .zero, configuration: configuration)
            if #available(iOS 16.4, macOS 13.3, *) {
                webView.isInspectable = false
            }
            super.init()
            // The content controller retains its handler; a weak proxy keeps that from retaining us.
            controller.add(WeakScriptMessageHandler(self), contentWorld: .page, name: Self.handlerName)
            webView.navigationDelegate = self
            webView.uiDelegate = self
        }

        // MARK: LeadFormTransport

        func load(_ url: URL) {
            guard !isTornDown else { return }
            expectLoad(of: url)
            hasCommitted = false
            webView.load(URLRequest(url: url))
        }

        /// Arms the navigation lock for one main-frame GET of exactly `url`.
        func expectLoad(of url: URL) {
            expectedLoad = url
        }

        /// Delivers one JSON string to the page as the `data` of a `message` event. The text travels
        /// as a call argument, never inside script source.
        func send(_ message: String) {
            guard !isTornDown else { return }
            webView.callAsyncJavaScript(
                "window.AdmoaiBridge.__deliver(data)",
                arguments: ["data": message],
                in: nil,
                in: .page,
                completionHandler: nil
            )
        }

        func teardown() {
            guard !isTornDown else { return }
            isTornDown = true
            onMessage = nil
            onLoadFailed = nil
            let controller = webView.configuration.userContentController
            controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: .page)
            controller.removeAllUserScripts()
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }

        // MARK: Filter

        /// A page message reaches the bridge only from the main frame, from the launch origin, as text.
        nonisolated static func accepts(isMainFrame: Bool, origin: FormOrigin, expected: FormOrigin?,
                                        body: Any) -> String?
        {
            guard isMainFrame, origin == expected, let text = body as? String else { return nil }
            return text
        }

        /// The navigation rule: only the load the SDK asked for, once: a main-frame GET over https of
        /// exactly that address. Everything else is cancelled, including a reload, a second load of
        /// the launch address, a form POST to it, another path on the same origin and a redirect.
        nonisolated static func allowsNavigation(
            to url: URL?,
            method: String?,
            inMainFrame: Bool,
            expected: URL?
        ) -> Bool {
            guard inMainFrame, let url, let expected, url.scheme == "https",
                  (method ?? "GET").uppercased() == "GET" else { return false }
            return withoutFragment(url) == withoutFragment(expected)
        }

        /// WebKit may or may not keep the fragment on the request it reports; the launch address's
        /// fragment carries no server-visible data, so the comparison leaves it out.
        private nonisolated static func withoutFragment(_ url: URL) -> String {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            return components?.string ?? url.absoluteString
        }

        fileprivate func receive(_ message: WKScriptMessage) {
            guard !isTornDown else { return }
            let frame = message.frameInfo
            guard let text = Self.accepts(
                isMainFrame: frame.isMainFrame,
                origin: FormOrigin(frame.securityOrigin),
                expected: origin,
                body: message.body
            ) else {
                refusedMessageCount += 1
                logger.warning("Lead form surface refused a page message from an unexpected frame or origin")
                return
            }
            onMessage?(text)
        }

        // MARK: Page-side object

        /// Defines `window.AdmoaiBridge`: `postMessage(text)` to the app, and a `message` event
        /// target (`onmessage`, `addEventListener`) the app delivers to through `__deliver`.
        private static let bridgeScript = """
        (function () {
          if (window.AdmoaiBridge) { return; }
          var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.AdmoaiBridge;
          var listeners = [];
          var bridge = {
            onmessage: null,
            postMessage: function (text) {
              if (typeof text === 'string' && handler) { handler.postMessage(text); }
            },
            addEventListener: function (type, listener) {
              if (type === 'message' && typeof listener === 'function' && listeners.indexOf(listener) < 0) {
                listeners.push(listener);
              }
            },
            removeEventListener: function (type, listener) {
              var index = listeners.indexOf(listener);
              if (type === 'message' && index >= 0) { listeners.splice(index, 1); }
            },
            __deliver: function (data) {
              var event = new MessageEvent('message', { data: data });
              if (typeof bridge.onmessage === 'function') {
                try { bridge.onmessage(event); } catch (e) {}
              }
              listeners.slice().forEach(function (listener) {
                try { listener.call(bridge, event); } catch (e) {}
              });
            }
          };
          Object.defineProperty(window, 'AdmoaiBridge', { value: bridge, writable: false, configurable: false });
        })();
        """
    }

    // MARK: - Delegates

    extension SecureFormWebView: WKNavigationDelegate, WKUIDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let allowed = Self.allowsNavigation(
                to: navigationAction.request.url,
                method: navigationAction.request.httpMethod,
                inMainFrame: navigationAction.targetFrame?.isMainFrame == true,
                expected: expectedLoad
            )
            let isMainFrame = navigationAction.targetFrame?.isMainFrame == true
            if allowed {
                expectedLoad = nil
            } else {
                cancelledNavigationCount += 1
                logger.warning("Lead form surface cancelled a navigation it did not start")
            }
            decisionHandler(allowed ? .allow : .cancel)
            // Refused before any page committed (the launch address redirected): no form will ever
            // answer. After a commit, the form stays and the navigation is simply cancelled.
            if !allowed, isMainFrame, !hasCommitted {
                onLoadFailed?(.blocked)
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            hasCommitted = true
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            reportLoadFailure(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportLoadFailure(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            logger.warning("Lead form surface lost its web content process")
            onLoadFailed?(.rendererLost)
        }

        /// A navigation the surface itself cancelled is not a failure of the form.
        private func reportLoadFailure(_ error: Error) {
            let nsError = error as NSError
            let cancelled = nsError.code == NSURLErrorCancelled
                || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102)
            guard !cancelled else { return }
            logger.warning("Lead form surface could not load the form page")
            onLoadFailed?(.transient)
        }

        /// The form page's own HTTP status. WebKit renders an error page as a page, so a 404 or
        /// 5xx would otherwise wait forever for a bridge_ready that never comes.
        nonisolated static func loadFailure(forStatus status: Int) -> LeadFormLoadFailure? {
            switch status {
            case ..<400: nil
            case 404: .unavailable
            default: .transient
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            guard navigationResponse.isForMainFrame,
                  let status = (navigationResponse.response as? HTTPURLResponse)?.statusCode,
                  let failure = Self.loadFailure(forStatus: status)
            else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            logger.warning("Lead form surface got HTTP \(status, privacy: .public) for the form page")
            onLoadFailed?(failure)
        }

        /// No popups: the form never opens another window.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }
    }

    /// Forwards to its target without retaining it.
    @MainActor
    private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        private weak var target: SecureFormWebView?

        init(_ target: SecureFormWebView) {
            self.target = target
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            target?.receive(message)
        }
    }
#endif
