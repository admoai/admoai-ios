import Foundation
import Testing

@testable import AdMoai

// Journey Takeover Ads — tracking (completions, fireCompletion, X-Tracking-Version)
//
// Feature: Fire Journey tracking correctly and verbatim
//   As a publisher SDK
//   I want to fire opaque tracking URLs with the X-Tracking-Version header
//   So that Journey completion (billing) is recorded and never silently routed to the
//   legacy tracking handler
//
// GET /v1/tracking version-routes on X-Tracking-Version (NOT X-Decision-Version); the URL
// is an opaque `…?e=<token>` fired verbatim. custom_event completions fire one URL once;
// final_stage completions have no URL (recorded server-side at decision time).

private func decodeTracking(_ json: String) throws -> Tracking {
    try JSONDecoder().decode(Tracking.self, from: json.data(using: .utf8)!)
}

@Suite(.serialized)
struct JourneyTrackingTests {

    // MARK: - Parsing

    // Scenario: completions parse and resolve by key
    @Test
    func testCompletionsParseAndResolve() throws {
        let tracking = try decodeTracking("""
        {
            "impressions": [{"key": "default", "url": "https://t/imp"}],
            "completions": [{"key": "purchase", "url": "https://t/complete?e=TOKEN"}]
        }
        """)
        #expect(tracking.getCompletionUrl(key: "purchase") == "https://t/complete?e=TOKEN")
        #expect(tracking.hasTrackingFor(type: .completion, key: "purchase"))
        #expect(tracking.getTrackingUrl(type: .completion, key: "purchase") == "https://t/complete?e=TOKEN")
        #expect(tracking.getCompletionUrl(key: "missing") == nil)
    }

    // Scenario: backward-compat — absent completions is nil, other categories still work
    @Test
    func testCompletionsAbsentBackwardCompat() throws {
        let tracking = try decodeTracking("""
        { "impressions": [{"key": "default", "url": "https://t/imp"}] }
        """)
        #expect(tracking.completions == nil)
        #expect(tracking.getImpressionUrl(key: "default") == "https://t/imp")
    }

    // Scenario: a malformed completion entry is dropped, the rest survive (Tolerant Reader)
    @Test
    func testMalformedCompletionEntryDropped() throws {
        let tracking = try decodeTracking("""
        {
            "completions": [
                {"key": "purchase", "url": "https://t/ok"},
                {"key": "broken"},
                42
            ]
        }
        """)
        #expect(tracking.completions?.count == 1)
        #expect(tracking.getCompletionUrl(key: "purchase") == "https://t/ok")
    }

    // MARK: - Header routing (the critical fix)

    // Scenario: a fired tracking GET carries X-Tracking-Version and NOT X-Decision-Version
    @Test
    func testTrackingSendsXTrackingVersionNotDecisionVersion() async throws {
        MockURLProtocol.reset()
        let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
        sdk.fireTracking(url: "https://api.mock.admoai.com/v1/tracking?e=OPAQUE_TOKEN")

        #expect(await MockURLProtocol.waitForRequests(1))
        let req = try #require(MockURLProtocol.lastRequest)
        #expect(req.value(forHTTPHeaderField: "X-Tracking-Version") == "2025-11-01")
        #expect(req.value(forHTTPHeaderField: "X-Decision-Version") == nil)
    }

    // Scenario: the opaque tracking URL is fired verbatim (never reconstructed)
    @Test
    func testTrackingUrlFiredVerbatim() async throws {
        MockURLProtocol.reset()
        let url = "https://api.mock.admoai.com/v1/tracking?e=ABC.DEF-123_xyz"
        let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
        sdk.fireTracking(url: url)

        #expect(await MockURLProtocol.waitForRequests(1))
        #expect(MockURLProtocol.lastRequest?.url?.absoluteString == url)
    }

    // Scenario: a scheme-less / relative tracking URL is skipped (logged), not fired, no crash
    @Test
    func testRelativeTrackingUrlIsSkippedNotCrashed() async throws {
        MockURLProtocol.reset()
        let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
        sdk.fireTracking(url: "/v1/tracking?e=abc")   // relative — URL(string:) accepts it
        sdk.fireTracking(url: "not a url at all")
        sdk.fireTracking(url: "ftp://example.com/x")  // non-http scheme

        // Give any (erroneous) task a chance to land, then assert nothing was fired.
        _ = await MockURLProtocol.waitForRequests(1, timeout: 0.4)
        #expect(MockURLProtocol.capturedRequests.isEmpty)
    }

    // MARK: - Completion modes

    // Scenario: custom_event completion fires exactly one URL, verbatim
    @Test
    func testCustomEventCompletionFiresOnce() async throws {
        MockURLProtocol.reset()
        let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
        let tracking = try decodeTracking("""
        { "completions": [{"key": "purchase", "url": "https://api.mock.admoai.com/v1/tracking?e=DONE"}] }
        """)
        sdk.fireCompletion(tracking: tracking, key: "purchase")

        #expect(await MockURLProtocol.waitForRequests(1))
        #expect(MockURLProtocol.capturedRequests.count == 1)
        #expect(MockURLProtocol.lastRequest?.url?.absoluteString == "https://api.mock.admoai.com/v1/tracking?e=DONE")
    }

    // Scenario: final_stage completion (no completions list) fires nothing extra
    @Test
    func testFinalStageFiresNothing() async throws {
        MockURLProtocol.reset()
        let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
        let tracking = try decodeTracking("""
        { "impressions": [{"key": "default", "url": "https://t/imp"}] }
        """)
        sdk.fireCompletion(tracking: tracking, key: "anything")

        _ = await MockURLProtocol.waitForRequests(1, timeout: 0.4)
        #expect(MockURLProtocol.capturedRequests.isEmpty)
    }

    // Scenario: a completion key miss with a non-empty completions list fires nothing (warns)
    @Test
    func testCompletionKeyMissFiresNothing() async throws {
        MockURLProtocol.reset()
        let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
        let tracking = try decodeTracking("""
        { "completions": [{"key": "purchase", "url": "https://t/ok"}] }
        """)
        sdk.fireCompletion(tracking: tracking, key: "wrong_key")

        _ = await MockURLProtocol.waitForRequests(1, timeout: 0.4)
        #expect(MockURLProtocol.capturedRequests.isEmpty)
    }

    // Scenario: without apiVersion, completion still fires but carries NO X-Tracking-Version
    //           (this is exactly the silent-billing-loss failure mode the SDK warns about)
    @Test
    func testCompletionWithoutApiVersionHasNoTrackingVersionHeader() async throws {
        MockURLProtocol.reset()
        let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: nil))
        let tracking = try decodeTracking("""
        { "completions": [{"key": "purchase", "url": "https://api.mock.admoai.com/v1/tracking?e=DONE"}] }
        """)
        sdk.fireCompletion(tracking: tracking, key: "purchase")

        #expect(await MockURLProtocol.waitForRequests(1))
        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Tracking-Version") == nil)
    }
}
