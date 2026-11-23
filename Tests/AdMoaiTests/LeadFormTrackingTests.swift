@_spi(InteractiveExperience) @testable import AdMoai
import Foundation
import Testing
#if canImport(OSLog)
    import OSLog
#endif

/// The scenarios of `Sources/AdMoai/LeadFormTracking.feature` that belong to the unit itself, one
/// test per scenario. The ones that need a whole form (hide and show, refused events) are in
/// `LeadFormControllerTests`.
@MainActor
struct LeadFormTrackingTests {
    private final class Attempts: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        private var outcomes: [Bool]
        private let delayMs: Int

        init(outcomes: [Bool], delayMs: Int = 0) {
            self.outcomes = outcomes
            self.delayMs = delayMs
        }

        var all: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return urls
        }

        func send(_ url: URL, _ done: @escaping @Sendable (Bool) -> Void) {
            lock.lock()
            urls.append(url)
            let outcome = outcomes.isEmpty ? true : outcomes.removeFirst()
            lock.unlock()
            if delayMs > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delayMs)) { done(outcome) }
            } else {
                done(outcome)
            }
        }
    }

    private static let open = URL(string: "https://api.example.invalid/track?t=open")!
    private static let start = URL(string: "https://api.example.invalid/track?t=start")!

    private func makeTracking(_ attempts: Attempts, delays: [Int] = [5, 5]) -> LeadFormTracking {
        let tracking = LeadFormTracking(
            send: { attempts.send($0, $1) },
            retryDelaysMs: delays,
            logger: Logger(subsystem: "test", category: "LeadFormTrackingTests")
        )
        tracking.activated(events: [.formOpen: Self.open, .formStart: Self.start])
        return tracking
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 400 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // Scenario 1
    @Test func anEventFiresTheAddressTheFormListedForIt() async {
        let attempts = Attempts(outcomes: [])
        let tracking = makeTracking(attempts)
        tracking.event(.formOpen)
        await waitUntil { attempts.all.count == 1 }
        #expect(attempts.all == [Self.open])
    }

    // Scenario 2
    @Test func anEventFiresOncePerForm() async {
        let attempts = Attempts(outcomes: [])
        let tracking = makeTracking(attempts)
        tracking.event(.formOpen)
        tracking.event(.formOpen)
        tracking.event(.formStart)
        tracking.event(.formStart)
        await waitUntil { attempts.all.count == 2 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        // Each address once; the two events are sent independently, so their order is not fixed.
        #expect(attempts.all.count == 2)
        #expect(Set(attempts.all) == [Self.open, Self.start])
    }

    // Scenario 3
    @Test func anEventThatWasNotListedFiresNothing() async {
        let attempts = Attempts(outcomes: [])
        let tracking = makeTracking(attempts)
        tracking.event(.websiteCtaClick)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(attempts.all.isEmpty)
    }

    // Scenario 4
    @Test func nothingFiresBeforeAnEventIsReported() async {
        let attempts = Attempts(outcomes: [])
        _ = makeTracking(attempts)
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(attempts.all.isEmpty)
    }

    // Scenario 5
    @Test func aFailedReportIsRetriedTwiceThenGivenUp() async {
        let recovers = Attempts(outcomes: [false, false, true])
        makeTracking(recovers).event(.formOpen)
        await waitUntil { recovers.all.count == 3 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(recovers.all == [Self.open, Self.open, Self.open])

        let gaveUp = Attempts(outcomes: [false, false, false, false])
        makeTracking(gaveUp).event(.formOpen)
        await waitUntil { gaveUp.all.count == 3 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(gaveUp.all.count == 3)
        #expect(LeadFormTracking.defaultRetryDelaysMs == [1000, 2000])
    }

    // Scenario 6
    @Test func aSlowReportNeverHoldsTheForm() async {
        let attempts = Attempts(outcomes: [true], delayMs: 300)
        let tracking = makeTracking(attempts)
        let start = Date()
        tracking.event(.formOpen)
        #expect(Date().timeIntervalSince(start) < 0.15)
        await waitUntil { attempts.all.count == 1 }
        #expect(attempts.all.count == 1)
    }

    // Scenario 7
    @Test func aLaterActivationNeverReplacesTheAddressesOfTheFirst() async {
        let attempts = Attempts(outcomes: [])
        let tracking = makeTracking(attempts)
        let other = URL(string: "https://api.example.invalid/track?t=other")!
        tracking.activated(events: [.formOpen: other, .formStart: other])
        tracking.event(.formOpen)
        tracking.event(.formStart)
        await waitUntil { attempts.all.count == 2 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(Set(attempts.all) == [Self.open, Self.start])
        #expect(!attempts.all.contains(other))
    }
}
