import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A `URLSession` for fire-and-forget beacons: a redirect is the final response, never a hop.
///
/// A beacon is terminal — the server records the event on the first response. `/v1/tracking`
/// answers a click with `302 Location: <destination>` so a browser can record and land in one
/// hop, but ``AdMoai/fireClick(tracking:key:)`` is not navigation: the app opens the destination
/// itself. Following the redirect downloaded the advertiser's whole landing page in the
/// background on every click, and sent an extra hit to a server we do not control. Third-party
/// trackers carry the same contract for the same reason: a redirect target runs logic outside it.
///
/// A class so ``AdMoai``'s value copies share one session, and so it can invalidate the session
/// when the last owner lets go — `URLSession` retains its delegate until invalidated, so without
/// this every discarded SDK instance (re-init, tests) would leak its session.
internal final class BeaconSession {
    /// A separate object rather than the box itself because `URLSession` retains its delegate
    /// strongly — a self-delegate would cycle (box → session → box) and neither would ever
    /// deallocate.
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

    private let session: URLSession

    init(configuration: URLSessionConfiguration) {
        self.session = URLSession(
            configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil
        )
    }

    deinit {
        // Lets in-flight beacons finish, then releases the session's delegate and threads.
        session.finishTasksAndInvalidate()
    }

    /// Sends `request` once. Nothing is retried, and no response — success, error or 3xx —
    /// reaches the caller.
    /// Dispatch order is the SDK's contract (a slide's view goes out before its click); arrival
    /// order is the network's, which no client controls. Tests observe the former here: the
    /// closure runs synchronously, in call order, before each request is handed to the session.
    private let observerLock = NSLock()
    private var dispatchObserver: ((URLRequest) -> Void)?

    func observeDispatches(_ observer: ((URLRequest) -> Void)?) {
        observerLock.lock()
        dispatchObserver = observer
        observerLock.unlock()
    }

    /// - Parameter completion: optional, for the few callers that retry (lead form events). Called
    ///   once with `true` when the server answered with anything below 500 (a redirect included: it
    ///   is the final response), `false` on a transport error or a 5xx. Without it nothing reaches
    ///   the caller, exactly as before.
    func fire(_ request: URLRequest, completion: ((Bool) -> Void)? = nil) {
        observerLock.lock()
        let observer = dispatchObserver
        observerLock.unlock()
        observer?(request)
        guard let completion else {
            session.dataTask(with: request).resume()
            return
        }
        session.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion(error == nil && status < 500)
        }.resume()
    }
}
