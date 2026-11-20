import Foundation
#if canImport(OSLog)
    import OSLog
#endif

/// Fires the tracking URL the form's activation listed for each form event, at most once per
/// event per controller.
///
/// The page only ever names an event; the URL is the one `activated` carried, so a later message
/// can never make the SDK request an address of the page's choosing. The URL is never logged.
@MainActor
final class LeadFormTracking {
    /// Sends one URL and reports whether it reached the server (see ``BeaconSession/fire(_:completion:)``).
    typealias Send = @Sendable (URL, @escaping @Sendable (Bool) -> Void) -> Void

    /// The retry schedule after a failed first attempt: three attempts in all, 1 s then 2 s apart.
    nonisolated static let defaultRetryDelaysMs = [1000, 2000]

    private let send: Send
    private let retryDelaysMs: [Int]
    private let logger: Logger
    private var urls: [LeadFormEvent: URL] = [:]
    private var fired = Set<LeadFormEvent>()

    init(
        send: @escaping Send,
        retryDelaysMs: [Int] = LeadFormTracking.defaultRetryDelaysMs,
        logger: Logger
    ) {
        self.send = send
        self.retryDelaysMs = retryDelaysMs
        self.logger = logger
    }

    /// Remembers the URLs of the activation: nothing is fired yet.
    func activated(events: [LeadFormEvent: URL]) {
        urls = events
    }

    /// The form reported `name`. Fires its URL the first time, never again.
    func event(_ name: LeadFormEvent) {
        guard let url = urls[name], fired.insert(name).inserted else { return }
        let send = send
        let delays = retryDelaysMs
        let logger = logger
        // Off the main actor and never awaited: a slow or failing beacon cannot hold the form.
        Task.detached {
            for attempt in 0 ... delays.count {
                let delivered = await withCheckedContinuation { continuation in
                    send(url) { continuation.resume(returning: $0) }
                }
                if delivered {
                    return
                }
                guard attempt < delays.count else { break }
                try? await Task.sleep(nanoseconds: UInt64(delays[attempt]) * 1_000_000)
            }
            logger.warning("Lead form event \(name.rawValue, privacy: .public) could not be reported")
        }
    }
}
