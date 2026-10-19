import Foundation

/// Remembers which Sponsored Pin view URLs this SDK instance has already fired, so a map
/// re-rendering the same decision response does not fire them again.
///
/// Keyed on the view URL itself, never on the point id. The engine mints every view URL with
/// its own event id, one per `(request, creative, location)`, so "this URL was fired" is
/// exactly "this pin was reported for this decision response" — the key E10 dedups `pin_view`
/// on server-side. A pin id repeats across responses; keying on it would swallow the view a
/// new response is owed.
///
/// Bounded: it holds the last ``capacity`` URLs and evicts the least recently claimed. A URL
/// that was evicted and is claimed again simply fires again, which the engine already drops
/// (`SETNX` on the event id), so forgetting is never wrong — only a wasted request.
///
/// `final class` + a lock, the way ``SessionBox`` is: ``AdMoai`` is a struct, so the ledger
/// must be a reference every copy shares, and ``claim(_:)`` runs synchronously on whatever
/// thread the publisher's map callback uses.
internal final class PointViewLedger: @unchecked Sendable {
    /// Ten full decision responses at the engine's 50-point ceiling, one view URL per point on
    /// the standard template.
    static let defaultCapacity = 500

    let capacity: Int
    private let lock = NSLock()
    /// Ordered least → most recently claimed.
    private let urls = NSMutableOrderedSet()

    init(capacity: Int = PointViewLedger.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// Records `url` as fired and returns `true` the first time it is seen. Returns `false`
    /// for a URL already fired, and refreshes it so a pin still on screen is not the one
    /// evicted next.
    func claim(_ url: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let existing = urls.index(of: url)
        if existing != NSNotFound {
            urls.moveObjects(at: IndexSet(integer: existing), to: urls.count - 1)
            return false
        }
        urls.add(url)
        if urls.count > capacity {
            urls.removeObject(at: 0)
        }
        return true
    }

    /// How many URLs are remembered right now — the observable side of the bound.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return urls.count
    }
}
