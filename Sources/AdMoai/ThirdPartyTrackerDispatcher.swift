import Foundation
import OSLog

/// The event a `fireImpression`/`fireClick` invocation reports, used to select which
/// third-party trackers fan out. Internal: publishers never address trackers directly.
internal enum ThirdPartyTrackerEvent {
    case impression
    case click(key: String)
}

/// Credential-isolated dispatcher for third-party event trackers (E06 of the Third-party
/// Event Trackers mission).
///
/// Agencies count these GETs on their own ad servers, so the dispatch contract is strict:
/// - **Own ephemeral session**, fully separate from the sessions used for Admoai API calls:
///   no Admoai `User-Agent`, no `X-Decision-Version`/`X-Tracking-Version`, no
///   `Accept-Language`, no auth, and cookies neither sent nor persisted.
/// - **GET only**, requesting the stored URL byte-for-byte. A URL that Foundation's `URL`
///   cannot round-trip byte-identically (e.g. a raw `%%MACRO%%` — modern Foundation would
///   re-encode it, iOS 14–16 would fail to parse it) is discarded at validation: firing
///   normalized/re-encoded bytes would corrupt what the agency counts, and OS-dependent
///   behavior would make the same campaign count differently per iOS version.
/// - **3xx terminal**: redirects are never followed (the delegate cancels them) — a redirect
///   target runs logic outside our contract.
/// - **Cache bypass**: a cached hit would be an unmeasured impression on the agency side.
/// - **Failure isolation**: every dispatch is independent fire-and-forget; a slow or failing
///   tracker never delays canonical tracking, never affects sibling trackers, and never
///   surfaces an error to the publisher. No retries — exactly one attempt per matching
///   tracker per helper invocation, so agency counts reconcile.
/// - **Sanitized logging**: outcomes reference `trackerId` only; tracker URLs never reach
///   any log sink (they can carry campaign-identifying query data).
internal final class ThirdPartyTrackerDispatcher {
    /// Mirror of the engine-side limit. More than this many valid entries can only mean a
    /// serving bug or a tampered response; firing a partial subset would make the agency's
    /// numbers quietly disagree with ours, so the whole collection is discarded instead.
    internal static let maxTrackers = 10

    /// 3xx is terminal: never follow a tracker redirect.
    ///
    /// A separate object rather than the dispatcher itself because `URLSession` retains its
    /// delegate strongly — a self-delegate would cycle (dispatcher → session → dispatcher)
    /// and neither would ever deallocate.
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private let logger: Logger
    private let session: URLSession

    /// - Parameter protocolClasses: carried over from `SDKConfig.sessionConfiguration` so
    ///   test stubs (`MockURLProtocol`) can observe the isolated session; nothing else of
    ///   the SDK's session configuration is inherited.
    internal init(protocolClasses: [AnyClass]?, logger: Logger) {
        self.logger = logger

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.protocolClasses = protocolClasses
        self.session = URLSession(
            configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    deinit {
        // Lets in-flight beacons finish, then releases the session's delegate and threads —
        // without this, every discarded dispatcher (SDK re-init, tests) leaks its session.
        session.finishTasksAndInvalidate()
    }

    // MARK: - Fan-out

    /// Dispatches every tracker matching `event`, exactly once each per invocation.
    ///
    /// Order of operations mirrors the E06 spec: semantic validation drops invalid entries
    /// individually; the defensive limit then applies to the count of VALID entries; matching
    /// and per-invocation exact-URL dedupe decide what actually fires.
    internal func dispatch(_ trackers: [ThirdPartyTracker], event: ThirdPartyTrackerEvent) {
        let valid = trackers.filter { tracker in
            guard let reason = Self.rejectionReason(tracker) else { return true }
            logger.debug(
                "Discarding third-party tracker '\(tracker.trackerId, privacy: .public)': \(reason, privacy: .public)"
            )
            return false
        }
        guard !valid.isEmpty else { return }
        guard valid.count <= Self.maxTrackers else {
            logger.warning(
                "Discarding ALL third-party trackers for this creative: \(valid.count) valid entries exceed the limit of \(Self.maxTrackers)."
            )
            return
        }

        var dispatchedURLs = Set<String>()
        for tracker in valid where Self.matches(tracker, event: event) {
            guard dispatchedURLs.insert(tracker.url).inserted else {
                logger.debug(
                    "Skipping third-party tracker '\(tracker.trackerId, privacy: .public)': duplicate URL already dispatched in this invocation."
                )
                continue
            }
            // Validation already required an absolute HTTPS URL, so this guard cannot fail;
            // it exists so a future validation change cannot introduce a force-unwrap crash.
            guard let url = URL(string: tracker.url) else { continue }
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: 10
            )
            request.httpShouldHandleCookies = false
            session.dataTask(with: request).resume()
        }
    }

    // MARK: - Semantic validation + matching (pure, internal for tests)

    /// Why an entry cannot be served, or `nil` when it is valid. Reasons are stable,
    /// URL-free strings — they go straight into logs.
    internal static func rejectionReason(_ tracker: ThirdPartyTracker) -> String? {
        if tracker.trackerId.isEmpty { return "empty trackerId" }
        switch tracker.eventType {
        case "impression":
            break
        case "click":
            switch tracker.matchType {
            case "any":
                break
            case "specific":
                if (tracker.eventKey ?? "").isEmpty {
                    return "specific click tracker without an eventKey"
                }
            default:
                return "unknown matchType"
            }
        default:
            return "unknown eventType"
        }
        guard let url = URL(string: tracker.url),
            url.scheme?.lowercased() == "https",
            url.host != nil
        else {
            return "url is not an absolute https URL"
        }
        // The wire request is built from the parsed URL, and modern Foundation's lenient
        // parser re-encodes what it cannot represent (a raw %%MACRO%% becomes %25%25…,
        // and adjacent VALID escapes get double-encoded). Never fire mutated bytes: a URL
        // that does not round-trip byte-identically is unservable.
        if url.absoluteString != tracker.url {
            return "url does not round-trip verbatim through the URL parser"
        }
        return nil
    }

    /// E06 matching: impressions fire on `fireImpression`; any-click trackers fire on every
    /// valid click; specific-click trackers fire only when the reported key equals theirs.
    internal static func matches(_ tracker: ThirdPartyTracker, event: ThirdPartyTrackerEvent)
        -> Bool
    {
        switch event {
        case .impression:
            return tracker.eventType == "impression"
        case .click(let key):
            guard tracker.eventType == "click" else { return false }
            return tracker.matchType == "any"
                || (tracker.matchType == "specific" && tracker.eventKey == key)
        }
    }
}
