import Foundation
import Testing

@testable import AdMoai

// Journey Takeover Ads — no-ad & single-brand takeover safety
//
// Feature: Handle no-ad responses safely with no local substitution
//   As a publisher SDK
//   I want to treat takeover-protected empties and ordinary no-fill uniformly as "no ad"
//   So that a protected surface never renders a competing brand and the SDK never fabricates
//   a fallback ad
//
// Engine: takeover-protected = {placement, creatives: []}; ordinary no-fill = creatives: null.
// The distinction is incidental (reason in server logs only) — both are no-ad to the SDK.

private func decodeResponse(_ json: String) throws -> DecisionResponse {
    try JSONDecoder().decode(DecisionResponse.self, from: json.data(using: .utf8)!)
}

struct JourneyNoAdTests {

    // Scenario: takeover-protected empty (creatives: []) is a no-ad
    @Test
    func testEmptyCreativesIsNoAd() throws {
        let response = try decodeResponse("""
        [{ "placement": "home", "creatives": [] }]
        """)
        let decision = try #require(response.first)
        #expect(decision.isNoAd)
        #expect(decision.hasCreative == false)
    }

    // Scenario: ordinary no-fill (creatives: null) is a no-ad
    @Test
    func testNullCreativesIsNoAd() throws {
        let response = try decodeResponse("""
        [{ "placement": "home", "creatives": null }]
        """)
        let decision = try #require(response.first)
        #expect(decision.isNoAd)
        #expect(decision.hasCreative == false)
    }

    // Scenario: absent creatives is a no-ad
    @Test
    func testAbsentCreativesIsNoAd() throws {
        let response = try decodeResponse("""
        [{ "placement": "home" }]
        """)
        let decision = try #require(response.first)
        #expect(decision.isNoAd)
    }

    // Scenario: empty top-level data is handled (no decisions at all)
    @Test
    func testEmptyDataArray() throws {
        let response = try decodeResponse("[]")
        #expect(response.isEmpty)
    }

    // Scenario: a real creative is NOT a no-ad
    @Test
    func testRealCreativeIsNotNoAd() throws {
        let response = try decodeResponse("""
        [{
            "placement": "home",
            "creatives": [{
                "contents": [{"key": "title", "value": "Hi", "type": "string"}],
                "advertiser": {"id": "adv1"},
                "tracking": {},
                "metadata": {"adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p", "priority": "standard"}
            }]
        }]
        """)
        let decision = try #require(response.first)
        #expect(decision.hasCreative)
        #expect(decision.isNoAd == false)
    }

    // Scenario: a no-ad decision yields nothing to render (no substitution) and nothing to track
    @Test
    func testNoAdYieldsNothingToTrack() throws {
        let response = try decodeResponse("""
        [{ "placement": "protected_surface", "creatives": [] }]
        """)
        let decision = try #require(response.first)
        #expect(decision.isNoAd)
        // No creatives → no tracking blocks to fire from; the SDK exposes no fallback creative.
        #expect((decision.creatives ?? []).isEmpty)
    }
}
