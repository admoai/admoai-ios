@_spi(InteractiveExperience) @testable import AdMoai
import Foundation
import Testing
#if canImport(WebKit)
    import WebKit
    #if canImport(OSLog)
        import OSLog
    #endif

    /// The scenarios of `Sources/AdMoai/SecureFormWebView.feature`, run against a real WKWebView on
    /// the macOS test host. Pages are loaded with `loadHTMLString(_, baseURL:)`, which gives them the
    /// origin the scenario needs without a network.
    @MainActor
    struct SecureFormWebViewTests {
        private static let launch = URL(string: "https://forms.example.invalid/launch")!
        private static let foreign = URL(string: "https://evil.example.invalid/")!

        @MainActor
        private final class Harness {
            let surface: SecureFormWebView
            var received: [String] = []
            var loadFailures = 0

            init() {
                surface = SecureFormWebView(
                    launchURL: SecureFormWebViewTests.launch,
                    logger: Logger(subsystem: "test", category: "SecureFormWebViewTests")
                )
                surface.onMessage = { [weak self] in self?.received.append($0) }
                surface.onLoadFailed = { [weak self] in self?.loadFailures += 1 }
            }

            func evaluate(_ script: String) async -> Any? {
                await withCheckedContinuation { continuation in
                    surface.webView.evaluateJavaScript(script) { result, _ in continuation.resume(returning: result) }
                }
            }

            /// Loads `html` as if served from `base`, then waits for the page to say it ran.
            func load(_ html: String, base: URL = SecureFormWebViewTests.launch) async {
                surface.webView.loadHTMLString(
                    "<html><body>\(html)<script>window.__ready = true;</script></body></html>",
                    baseURL: base
                )
                await SecureFormWebViewTests.wait { await (self.evaluate("window.__ready === true") as? Bool) == true }
            }
        }

        private static func wait(seconds: Double = 5, _ condition: @MainActor () async -> Bool) async {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if await condition() {
                    return
                }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
        }

        private static func settle(_ seconds: Double = 0.6) async {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }

        private let rawPost = "window.webkit.messageHandlers.AdmoaiBridge.postMessage"

        // Scenario 1
        @Test func aMessageFromTheFormsOwnPageIsDelivered() async {
            let h = Harness()
            await h.load("<script>window.AdmoaiBridge.postMessage('hello \"q\"');</script>")
            await Self.wait { !h.received.isEmpty }
            #expect(h.received == ["hello \"q\""])
            #expect(h.surface.refusedMessageCount == 0)
        }

        // Scenario 2
        @Test func aMessageFromAFrameInsideThePageIsRefused() async {
            let frame = "<iframe srcdoc=\"<script>window.webkit.messageHandlers.AdmoaiBridge.postMessage('x')</script>\"></iframe>"
            // With the navigation rule in place the frame never loads, so it never speaks.
            let locked = Harness()
            await locked.load(frame)
            await Self.settle()
            #expect(locked.received.isEmpty)
            #expect(locked.surface.cancelledNavigationCount >= 1)

            // Without it the frame does speak, and the message filter refuses it: main frame only.
            let open = Harness()
            open.surface.webView.navigationDelegate = nil
            await open.load(frame)
            await Self.wait { open.surface.refusedMessageCount == 1 }
            #expect(open.surface.refusedMessageCount == 1)
            #expect(open.received.isEmpty)
        }

        // Scenario 3
        @Test func aMessageFromAnotherOriginIsRefused() async {
            let h = Harness()
            h.surface.webView.navigationDelegate = nil
            await h.load("<script>\(rawPost)('x');</script>", base: Self.foreign)
            await Self.wait { h.surface.refusedMessageCount == 1 }
            #expect(h.surface.refusedMessageCount == 1)
            #expect(h.received.isEmpty)

            let sameHostOtherPort = Harness()
            sameHostOtherPort.surface.webView.navigationDelegate = nil
            await sameHostOtherPort.load(
                "<script>\(rawPost)('x');</script>",
                base: URL(string: "https://forms.example.invalid:8443/")!
            )
            await Self.wait { sameHostOtherPort.surface.refusedMessageCount == 1 }
            #expect(sameHostOtherPort.surface.refusedMessageCount == 1)
        }

        // Scenario 4
        @Test func aMessageThatIsNotTextIsRefused() async {
            let h = Harness()
            await h.load("<script>\(rawPost)({a: 1}); \(rawPost)(5);</script>")
            await Self.wait { h.surface.refusedMessageCount == 2 }
            #expect(h.surface.refusedMessageCount == 2)
            #expect(h.received.isEmpty)
        }

        // Scenario 5
        @Test func navigationAwayFromTheFormIsCancelled() async {
            let launch = FormOrigin(url: Self.launch)
            let allows = { (url: String, main: Bool) in
                SecureFormWebView.allowsNavigation(to: URL(string: url), inMainFrame: main, launchOrigin: launch)
            }
            #expect(allows("https://forms.example.invalid/launch?x=1#a=b", true))
            #expect(allows("https://FORMS.example.invalid:443/other", true))
            #expect(!allows("https://forms.example.invalid/launch", false))
            #expect(!allows("https://evil.example.invalid/", true))
            #expect(!allows("http://forms.example.invalid/launch", true))
            #expect(!allows("https://forms.example.invalid:8443/", true))
            #expect(!allows("about:blank", true))
            #expect(!allows("javascript:alert(1)", true))
            #expect(!allows("file:///etc/passwd", true))

            let h = Harness()
            await h.load("")
            _ = await h.evaluate("location.href = 'https://other.example.invalid/'")
            await Self.wait { h.surface.cancelledNavigationCount == 1 }
            _ = await h.evaluate("location.href = 'http://forms.example.invalid/insecure'")
            await Self.wait { h.surface.cancelledNavigationCount == 2 }
            #expect(h.surface.cancelledNavigationCount == 2)
            #expect(h.loadFailures == 0, "a navigation the surface cancelled is not a load failure")
        }

        // Scenario 6
        @Test func popupsNeverOpen() async {
            let h = Harness()
            await h
                .load(
                    "<script>window.AdmoaiBridge.postMessage(String(window.open('https://forms.example.invalid/x') === null));</script>"
                )
            await Self.wait { !h.received.isEmpty }
            #expect(h.received == ["true"])
        }

        // Scenario 7
        @Test func messagesFromTheSDKArriveAsTextExactly() async {
            let h = Harness()
            await h.load("""
            <script>
            window.__all = [];
            window.AdmoaiBridge.onmessage = function (e) { window.__a = e.data; window.__all.push(e instanceof MessageEvent); };
            window.AdmoaiBridge.addEventListener('message', function (e) { window.__b = e.data; });
            </script>
            """)
            let text = "{\"v\":\"He said \\\"hi\\\" </script><script>alert(1)</script>\\nline 日本語 😀 \\\\ 'x'\"}\n\u{2028}\r\n"
            h.surface.send(text)
            await Self.wait { await (h.evaluate("window.__b") as? String) != nil }
            #expect(await h.evaluate("window.__a") as? String == text)
            #expect(await h.evaluate("window.__b") as? String == text)
            #expect(await h.evaluate("window.__all.length") as? Int == 1)
            #expect(await h.evaluate("window.__all[0]") as? Bool == true)
        }

        // Scenario 9
        @Test func aPageThatCannotLoadIsReported() async {
            let h = Harness()
            h.surface.load(Self.launch) // the launch host is unreachable (.invalid)
            await Self.wait { h.loadFailures >= 1 }
            #expect(h.loadFailures >= 1)
        }

        // Scenario 8
        @Test func theWebViewKeepsNothingAndIsReleased() async {
            var surface: SecureFormWebView? = SecureFormWebView(
                launchURL: Self.launch, logger: Logger(subsystem: "test", category: "SecureFormWebViewTests")
            )
            #expect(surface?.webView.configuration.websiteDataStore.isPersistent == false)
            weak var weakView = surface?.webView
            surface?.webView.loadHTMLString("<html></html>", baseURL: Self.launch)
            await Self.settle(0.3)
            surface?.teardown()
            surface = nil
            await Self.wait { weakView == nil }
            #expect(weakView == nil)
        }
    }
#endif
