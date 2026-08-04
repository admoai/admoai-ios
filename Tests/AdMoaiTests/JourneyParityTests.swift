import Foundation
import Testing

@testable import AdMoai

// Journey Ads — cross-SDK parity guards
//
// Feature: Behave identically to the Android reference implementation
//   As a publisher SDK
//   I want the Journey contract enforced at exactly the points Android enforces it
//   So that the same integration behaves the same way on every platform
//
// Every group here corresponds to a line of the platform-agnostic Journey contract and to a
// divergence found while diffing this SDK against `admoai-android`. These are **guards**:
// each one was verified to FAIL when its fix is reverted. A guard that cannot fail is not a
// guard — which is the whole lesson of the Android rounds, where the two real bugs both
// survived a fully green suite because nothing ever claimed the surface they broke.
//
// Verified to bite (2026-07-30), by reverting each fix individually:
//   • `isJourneyAd` back to `journey != nil`               → 3 failures
//   • `fireTracking`'s http(s)+host check removed          → 1 failure
//   • firing routed through a lossy URLComponents rebuild  → 2 failures
//   • `X-Decision-Version` no longer set on a decision     → 2 failures

private let baseURL = "https://api.mock.admoai.com"
private let journeyVersion = "2025-11-01"

private func decodeCreative(_ json: String) throws -> Creative {
    try JSONDecoder().decode(Creative.self, from: json.data(using: .utf8)!)
}

/// A creative whose `journey` block is supplied by the caller, so a group can vary only the
/// Journey block while everything around it stays a well-formed normal ad.
private func creativeJSON(journey: String) -> String {
    """
    {
        "contents": [{"key": "title", "value": "Hi", "type": "string"}],
        "advertiser": {"id": "adv1"},
        "template": {"key": "standard"},
        "tracking": {"impressions": [{"key": "default", "url": "https://track/imp"}]},
        "metadata": {"adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p", "priority": "standard"}\(journey.isEmpty ? "" : ",\n        \"journey\": \(journey)")
    }
    """
}

// MARK: - D1: journey metadata on a normal ad must never look like a Journey serve

// Contract P2. `isJourneyAd` cannot key off `journey != nil`: the Tolerant Reader decodes
// `"journey": {}` — and a block with every field retyped — into a NON-nil `CreativeJourney`
// whose every field is nil, because an empty keyed container decodes fine and each field is
// `try?`. A normal ad would then report `isJourneyAd == true` while all thirteen accessors
// returned nil, and a publisher branching on it would render Journey UI for a normal ad.
struct JourneyIsJourneyAdGuardTests {

    // Scenario: an empty journey block is NOT a Journey ad
    @Test
    func testEmptyJourneyBlockIsNotAJourneyAd() throws {
        let creative = try decodeCreative(creativeJSON(journey: "{}"))
        // The block itself decodes (tolerantly) — that is precisely why the accessor cannot
        // rely on nil-ness.
        #expect(creative.journey != nil)
        #expect(creative.isJourneyAd == false)
    }

    // Scenario: a journey block with every field retyped is NOT a Journey ad
    @Test
    func testFullyRetypedJourneyBlockIsNotAJourneyAd() throws {
        let json = creativeJSON(
            journey: """
            {
                "dealId": 12345,
                "instanceId": ["not", "a", "string"],
                "definitionKey": false,
                "stageKey": {"nested": true},
                "isCompletion": "yes",
                "optStatus": true
            }
            """)
        let creative = try decodeCreative(json)
        #expect(creative.journey != nil)
        #expect(creative.isJourneyAd == false)
        #expect(creative.journeyDealId == nil)
        #expect(creative.journeyInstanceId == nil)
    }

    // Scenario: blank / whitespace-only identifiers are NOT a Journey ad
    @Test
    func testBlankIdentifiersAreNotAJourneyAd() throws {
        let json = creativeJSON(journey: #"{"dealId": "", "instanceId": "   "}"#)
        let creative = try decodeCreative(json)
        #expect(creative.isJourneyAd == false)
    }

    // Scenario: either identifier alone is enough
    @Test
    func testEitherIdentifierAloneIsAJourneyAd() throws {
        let dealOnly = try decodeCreative(creativeJSON(journey: #"{"dealId": "deal_1"}"#))
        #expect(dealOnly.isJourneyAd == true)

        let instanceOnly = try decodeCreative(creativeJSON(journey: #"{"instanceId": "inst_1"}"#))
        #expect(instanceOnly.isJourneyAd == true)
    }

    // Scenario: a real Journey serve is a Journey ad with its metadata intact
    @Test
    func testRealJourneyServeIsAJourneyAdWithMetadata() throws {
        let json = creativeJSON(
            journey: """
            {
                "dealId": "deal_123",
                "instanceId": "inst_456",
                "definitionKey": "scooter_journey",
                "stageKey": "pre_ride",
                "optStatus": "in",
                "isCompletion": false,
                "pricingModel": "cpt",
                "fallbackBillingMode": "bill_per_stage"
            }
            """)
        let creative = try decodeCreative(json)
        #expect(creative.isJourneyAd == true)
        #expect(creative.journeyDealId == "deal_123")
        #expect(creative.journeyInstanceId == "inst_456")
        #expect(creative.journeyDefinitionKey == "scooter_journey")
        #expect(creative.journeyStageKey == "pre_ride")
        #expect(creative.journeyOptStatus == .optIn)
        #expect(creative.isJourneyCompletion == false)
        #expect(creative.journeyPricingModel == "cpt")
        #expect(creative.journeyFallbackBillingMode == "bill_per_stage")
    }

    // Scenario: a normal ad with no journey block at all, and a non-object journey value
    @Test
    func testAbsentAndNonObjectJourneyAreNotJourneyAds() throws {
        let absent = try decodeCreative(creativeJSON(journey: ""))
        #expect(absent.journey == nil)
        #expect(absent.isJourneyAd == false)

        let nonObject = try decodeCreative(creativeJSON(journey: "42"))
        #expect(nonObject.journey == nil)
        #expect(nonObject.isJourneyAd == false)
    }

    // Scenario: every Journey accessor reads safely on a normal ad (P2 — no crash, no default
    //   object). Exercised as a block because a publisher reading five of them must not have
    //   to know which are safe.
    @Test
    func testAllAccessorsAreNullOrFalseOnANormalAd() throws {
        let creative = try decodeCreative(creativeJSON(journey: ""))
        #expect(creative.isJourneyAd == false)
        #expect(creative.journeyDealId == nil)
        #expect(creative.journeyInstanceId == nil)
        #expect(creative.journeyDefinitionKey == nil)
        #expect(creative.journeyStageId == nil)
        #expect(creative.journeyStageKey == nil)
        #expect(creative.journeyStageNodeId == nil)
        #expect(creative.journeySessionId == nil)
        #expect(creative.journeyOptStatus == nil)
        #expect(creative.journeyPricingModel == nil)
        #expect(creative.journeyFallbackBillingMode == nil)
        #expect(creative.isJourneyCompletion == false)
        #expect(creative.hasCompletionUrl == false)
    }
}

// The suites below drive `MockURLProtocol`, so they are nested under `MockNetworkTests`
// to be serialized against every other MockURLProtocol consumer — see that file for why.
extension MockNetworkTests {
    // MARK: - D5: tracking URLs are fired byte-for-byte verbatim

    // Contract T1/T2. Identity lives inside the opaque `?e=` token, so any normalization — a
    // re-encoded query, uppercased percent-escape hex, a stripped `+` — can invalidate it. This
    // SDK passes the server's string straight to `URL(string:)`, which preserves it exactly; the
    // guard exists so a future refactor to `URLComponents` (which re-encodes) is caught here
    // rather than by a publisher losing attribution.
    struct JourneyVerbatimFiringGuardTests {

        // Scenario: a percent-escape-hostile URL is fired byte-identical
        @Test
        func testEscapeHostileUrlFiredByteIdentical() async throws {
            MockURLProtocol.reset()
            // Lowercase escape hex, a literal `+`, an unencoded `=` and `/` inside the query:
            // every one of these is something a re-encoding layer would "fix".
            let url = "https://api.mock.admoai.com/v1/tracking?e=ab%2fcd%3def+gh/ij=kl"
            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: journeyVersion))

            sdk.fireTracking(url: url)

            #expect(await MockURLProtocol.waitForRequests(1))
            #expect(MockURLProtocol.lastRequest?.url?.absoluteString == url)
        }

        // Scenario: a retry re-fires the identical string
        @Test
        func testRetryRefiresTheIdenticalString() async throws {
            MockURLProtocol.reset()
            let url = "https://api.mock.admoai.com/v1/tracking?e=ab%2fcd%3def+gh/ij=kl"
            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: journeyVersion))

            sdk.fireTracking(url: url)
            #expect(await MockURLProtocol.waitForRequests(1))
            sdk.fireTracking(url: url)
            #expect(await MockURLProtocol.waitForRequests(2))

            let fired = MockURLProtocol.capturedRequests.compactMap { $0.url?.absoluteString }
            #expect(fired.count == 2)
            #expect(fired[0] == fired[1])
            #expect(fired[0] == url)
        }

        // Scenario: engine tokens use the base64url alphabet, so there is nothing to normalize
        //   even in principle. Documents the assumption that makes the above safe — verified
        //   against a live serve, whose tokens contain only [A-Za-z0-9_-] (no %, +, or =).
        @Test
        func testEngineTokenAlphabetNeedsNoEscaping() throws {
            let liveToken =
                "ps8R7joRSte37VUR_tQ5ZokgIFG_9s4rMiUQcBQrkLRm7SC_AvkwsYF--Ix4l74TKLUNq_jTB2MS01U7Q"
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
                .union(CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz"))
                .union(CharacterSet(charactersIn: "0123456789-_"))
            #expect(liveToken.unicodeScalars.allSatisfy { allowed.contains($0) })

            let url = "https://api.mock.admoai.com/v1/tracking?e=\(liveToken)"
            #expect(URL(string: url)?.absoluteString == url)
        }

        // Scenario: T1 — non-http(s) schemes and hostless URLs are refused, not fired
        @Test
        func testNonHttpSchemesAndHostlessUrlsAreRefused() async throws {
            MockURLProtocol.reset()
            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: journeyVersion))

            for bad in [
                "mailto:ops@example.com",
                "file:///etc/passwd",
                "ftp://example.com/x",
                "https://",             // scheme but no host
                "/v1/tracking?e=abc",   // relative
                "not a url at all",
            ] {
                sdk.fireTracking(url: bad)
            }

            _ = await MockURLProtocol.waitForRequests(1, timeout: 0.4)
            #expect(MockURLProtocol.capturedRequests.isEmpty)
        }
    }

    // MARK: - R1: a Journey decision request carries the version header

    // Without `X-Decision-Version: 2025-11-01` the engine SILENTLY ignores `sessionId` and
    // `journeyOpt` and serves normal ads — no error, no warning from the server. The header was
    // previously asserted only in the live suite (gated off by default) and only on a plain
    // request, so nothing hermetic tied it to a request that actually carries Journey context.
    struct JourneyVersionHeaderGuardTests {

        // Scenario: the header and the Journey fields reach the wire together
        @Test
        func testJourneyRequestCarriesVersionHeaderOnTheWire() async throws {
            MockURLProtocol.reset(
                stub: .init(statusCode: 200, body: Data(#"{"success":true,"data":[]}"#.utf8)))
            let sdk = AdMoai(
                config: MockURLProtocol.config(apiVersion: journeyVersion),
                sessionId: "trip-header-1"
            )
            let request = sdk.createRequestBuilder()
                .addPlacement(key: "home")
                .setJourneyOpt(.optIn)
                .build()

            _ = try await sdk.requestAds(request)

            let sent = try #require(MockURLProtocol.lastRequest)
            #expect(sent.value(forHTTPHeaderField: "X-Decision-Version") == journeyVersion)

            // The body is asserted through `getHttpRequest` because `URLProtocol` does not expose
            // a streamed `httpBody`; it is the same encoder the client uses.
            let http = try sdk.getHttpRequest(request)
            let body = String(data: try #require(http.body), encoding: .utf8) ?? ""
            #expect(body.contains("\"sessionId\":\"trip-header-1\""))
            #expect(body.contains("\"journeyOpt\":\"in\""))
            #expect(http.headers?["X-Decision-Version"] == journeyVersion)
        }

        // Scenario: no apiVersion means no header — the state in which Journey silently degrades.
        //   Pinned so the degradation is a known, tested condition rather than a surprise.
        @Test
        func testWithoutApiVersionNoHeaderIsSent() throws {
            let sdk = AdMoai(config: MockURLProtocol.config(), sessionId: "trip-header-2")
            let request = sdk.createRequestBuilder().addPlacement(key: "home").build()

            let http = try sdk.getHttpRequest(request)
            #expect(http.headers?["X-Decision-Version"] == nil)
            // The Journey context is still forwarded — the engine, not the SDK, decides to ignore it.
            let body = String(data: try #require(http.body), encoding: .utf8) ?? ""
            #expect(body.contains("\"sessionId\":\"trip-header-2\""))
        }
    }

    // MARK: - fireCustomEvent / fireCustom parity

    // Android exposes `fireCustomEvent`; iOS and Flutter shipped `fireCustom`. Flutter made
    // `fireCustomEvent` canonical with a deprecated alias; this does the same so all three SDKs
    // converge without breaking an existing integration on upgrade.
    struct FireCustomEventParityTests {

        // Scenario: both names fire the same URL
        // Calls the deprecated alias deliberately; the attribute keeps that from warning.
        @available(*, deprecated)
        @Test
        func testBothNamesFireTheSameUrl() async throws {
            MockURLProtocol.reset()
            let tracking = Tracking(
                impressions: nil,
                clicks: nil,
                custom: [TrackingItem(key: "companionOpened", url: "https://h/v1/tracking?e=custom1")],
                videoEvents: nil,
                completions: nil
            )
            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: journeyVersion))

            sdk.fireCustomEvent(tracking: tracking, key: "companionOpened")
            #expect(await MockURLProtocol.waitForRequests(1))
            sdk.fireCustom(tracking: tracking, key: "companionOpened")
            #expect(await MockURLProtocol.waitForRequests(2))

            let fired = MockURLProtocol.capturedRequests.compactMap { $0.url?.absoluteString }
            #expect(fired == ["https://h/v1/tracking?e=custom1", "https://h/v1/tracking?e=custom1"])
        }

        // Scenario: an unknown custom key fires nothing (T6-shaped: a key miss is a no-op)
        @Test
        func testUnknownCustomKeyFiresNothing() async throws {
            MockURLProtocol.reset()
            let tracking = Tracking(
                impressions: nil,
                clicks: nil,
                custom: [TrackingItem(key: "companionOpened", url: "https://h/v1/tracking?e=custom1")],
                videoEvents: nil,
                completions: nil
            )
            let sdk = AdMoai(config: MockURLProtocol.config(apiVersion: journeyVersion))

            sdk.fireCustomEvent(tracking: tracking, key: "neverConfigured")

            _ = await MockURLProtocol.waitForRequests(1, timeout: 0.4)
            #expect(MockURLProtocol.capturedRequests.isEmpty)
        }
    }
}
