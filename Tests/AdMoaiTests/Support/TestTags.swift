import Foundation
import Testing

extension Tag {
    /// Marks tests that make **real network calls** to a live decision-engine.
    ///
    /// These are diagnostic, not part of the deterministic gate: they are disabled by
    /// default and only run when `ADMOAI_LIVE_TESTS=1` is set. This toolchain's `swift test`
    /// exposes only `--filter`/`--skip` (name regex), so execution is gated via
    /// `.enabled(if: LiveTestGate.enabled)`; the tag is for discoverability and future
    /// tag-aware runners.
    @Tag static var live: Self
}

/// Gate for live (real-network) tests. Set `ADMOAI_LIVE_TESTS=1` to enable them:
///
///     ADMOAI_LIVE_TESTS=1 swift test          # full diagnostic run (hits the real engine)
///     swift test                              # deterministic gate (live tests skipped)
enum LiveTestGate {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["ADMOAI_LIVE_TESTS"] == "1"
    }
}
