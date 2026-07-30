import Foundation
import Testing

@testable import AdMoai

// Documented-API compile check
//
// Feature: Every API symbol the README shows a publisher actually exists
//   As a publisher following the README
//   I want the documented calls to compile against the shipped SDK
//   So that a documented method that does not exist fails OUR build rather than my first
//   integration
//
// This file is deliberately mostly type-checking rather than assertion: its value is that it
// **compiles**. The Android round found three builder methods documented under names that do not
// exist, a `Quick Start` calling an `initialize` overload that was never defined, and a false
// claim that tracking returns a stream. Every one of those is a compile error here.
//
// When the README gains a new documented call, add it below. The runtime assertions are
// incidental — they only keep the compiler from optimising the calls away and prove the
// documented no-op paths really are no-ops.

/// Routes through the stateless stub, not `MockURLProtocol`: this suite never inspects what was
/// sent, so it must not share capture state with the serialized `MockNetworkTests` suite.
private func docConfig(apiVersion: String? = "2025-11-01") -> SDKConfig {
    BlackHoleURLProtocol.config(
        apiVersion: apiVersion,
        defaultLanguage: "en"
    )
}

struct DocumentedAPITests {

    // MARK: - Quick Start

    // Scenario: README "Initialize the SDK" / "Configure User Settings" / "Clean Up on Logout"
    @Test
    func testQuickStartSurfaceExists() {
        var sdk = AdMoai(config: docConfig())

        sdk.setUserConfig(
            id: "user_123",
            ip: "203.0.113.1",
            timezone: TimeZone.current.identifier,
            consent: User.Consent(gdpr: true)
        )
        sdk.setDeviceConfig(model: "iPhone", os: "iOS", osVersion: "17.0")
        sdk.setAppConfig(name: "MyApp", version: "1.0.0")

        sdk.clearUserConfig()
        sdk.clearDeviceConfig()
        sdk.clearAppConfig()

        #expect(sdk.config.apiVersion == "2025-11-01")
    }

    // Scenario: README "Build and Send a Request" — every builder method the docs show
    @Test
    func testDocumentedBuilderSurfaceExists() throws {
        let sdk = AdMoai(config: docConfig())

        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home", format: .native)
            .addPlacement(key: "promotions", format: .video)
            .addGeoTargeting(2_643_743)
            .addCustomTargeting(key: "category", value: "news")
            .addLocationTargeting(latitude: 40.7128, longitude: -74.006)
            .setUserId("user_123")
            .build()

        #expect(request.placements.count == 2)

        // Documented as throwing, because `minConfidence` is range-validated.
        let destination = try sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .addDestinationTargeting(latitude: 40.7128, longitude: -74.006, minConfidence: 0.8)
            .build()
        #expect(destination.targeting?.destination?.isEmpty == false)
    }

    // Scenario: README "Extract Content"
    @Test
    func testDocumentedContentAccessorsExist() throws {
        let creative = try docCreative(journey: nil)
        _ = creative.contents.getContent(key: "headline")?.value.description
        #expect(creative.contents.hasContents())
        #expect(creative.contents.isType(key: "headline", type: "text"))
    }

    // MARK: - Event Tracking

    // Scenario: README "Event Tracking → Available Methods". All are documented as
    //   fire-and-forget returning Void — if any returned a value or threw, this would not compile
    //   as written.
    @available(*, deprecated)  // `fireCustom` is exercised deliberately as a documented alias.
    @Test
    func testDocumentedTrackingMethodsExistAndReturnVoid() throws {
        let sdk = AdMoai(config: docConfig())
        let creative = try docCreative(journey: nil)

        let void: Void = sdk.fireImpression(tracking: creative.tracking)
        sdk.fireImpression(tracking: creative.tracking, key: "default")
        sdk.fireClick(tracking: creative.tracking)
        sdk.fireClick(tracking: creative.tracking, key: "default")
        sdk.fireVideoEvent(tracking: creative.tracking, key: "start")
        sdk.fireCustomEvent(tracking: creative.tracking, key: "companionOpened")
        sdk.fireCustom(tracking: creative.tracking, key: "companionOpened")
        sdk.fireCompletion(tracking: creative.tracking, key: "journey_complete")
        sdk.fireTracking(url: "https://api.admoai.com/v1/tracking?e=abc")

        #expect(void == ())
    }

    // MARK: - Journey Takeover Ads

    // Scenario: README "The sessionId contract" — sticky, per-request override, per-request clear
    @Test
    func testDocumentedSessionIdSurfaceExists() {
        var sdk = AdMoai(config: docConfig(), sessionId: "trip-9f3c-2025")
        #expect(sdk.sessionId == "trip-9f3c-2025")

        sdk.setSessionId("trip-a17d-2025")
        #expect(sdk.sessionId == "trip-a17d-2025")

        let overridden = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .setSessionId("just-this-request")
            .build()
        #expect(overridden.sessionId == "just-this-request")

        let cleared = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .clearSessionId()
            .build()
        #expect(cleared.sessionId == nil)

        // The sticky value survives both.
        #expect(sdk.sessionId == "trip-a17d-2025")
        sdk.clearSessionId()
        #expect(sdk.sessionId == nil)
    }

    // Scenario: README "journeyOpt — three states". The docs claim exactly `.optIn`/`.optOut`
    //   with wire values "in"/"out", and that omitting is a distinct third state.
    @Test
    func testDocumentedJourneyOptSurfaceExists() {
        #expect(JourneyOpt.optIn.rawValue == "in")
        #expect(JourneyOpt.optOut.rawValue == "out")

        let sdk = AdMoai(config: docConfig())
        let optedIn = sdk.createRequestBuilder()
            .addPlacement(key: "home").setJourneyOpt(.optIn).build()
        #expect(optedIn.journeyOpt == .optIn)

        let omitted = sdk.createRequestBuilder()
            .addPlacement(key: "home").setJourneyOpt(.optIn).clearJourneyOpt().build()
        #expect(omitted.journeyOpt == nil)
    }

    // Scenario: README "Reading Journey metadata" — all thirteen documented accessors
    @Test
    func testDocumentedJourneyAccessorsExist() throws {
        let creative = try docCreative(
            journey: """
                {
                    "dealId": "deal_1", "instanceId": "inst_1", "definitionKey": "ride",
                    "stageId": "s1", "stageKey": "pre_ride", "stageNodeId": "n1",
                    "sessionId": "trip-1", "optStatus": "in", "isCompletion": false,
                    "pricingModel": "cpt", "fallbackBillingMode": "bill_per_stage"
                }
                """)

        #expect(creative.isJourneyAd)
        #expect(creative.journeyDealId == "deal_1")
        #expect(creative.journeyInstanceId == "inst_1")
        #expect(creative.journeyDefinitionKey == "ride")
        #expect(creative.journeyStageId == "s1")
        #expect(creative.journeyStageKey == "pre_ride")
        #expect(creative.journeyStageNodeId == "n1")
        #expect(creative.journeySessionId == "trip-1")
        #expect(creative.journeyOptStatus == .optIn)
        #expect(creative.journeyPricingModel == "cpt")
        #expect(creative.journeyFallbackBillingMode == "bill_per_stage")
        #expect(creative.isJourneyCompletion == false)
        #expect(creative.hasCompletionUrl == false)
    }

    // Scenario: README "No-ad is correct behaviour" — `decision.isNoAd`
    @Test
    func testDocumentedNoAdSurfaceExists() throws {
        let decision = try JSONDecoder().decode(
            Decision.self, from: Data(#"{"placement":"home","creatives":[]}"#.utf8))
        #expect(decision.isNoAd)
        #expect(!decision.hasCreative)
    }

    // MARK: - Video

    // Scenario: README "Detecting Video Ads" and the VAST double-count rule
    @Test
    func testDocumentedVideoSurfaceExists() throws {
        let creative = try docCreative(journey: nil)
        #expect(creative.isJsonDelivery() == false)
        #expect(creative.isVastTagDelivery() == false)
        #expect(creative.isVastXmlDelivery() == false)
        _ = creative.getVastTagUrl()
        _ = creative.getVastTagUrl(mediaType: "video/mp4", mediaDelivery: "progressive")
        _ = creative.getVastXmlBase64()
        _ = creative.getVastXmlBase64(mediaType: "video/mp4", mediaDelivery: "streaming")
    }

    // MARK: - Response Structure

    // Scenario: README "Response Structure" — every documented node of the tree, including the
    //   five tracking lists (so `completions` is discoverable) and `journey`.
    @Test
    func testDocumentedResponseTreeExists() throws {
        let creative = try docCreative(journey: nil)
        _ = creative.contents
        _ = creative.advertiser
        _ = creative.template?.key
        _ = creative.template?.style
        _ = creative.metadata?.adId
        _ = creative.delivery
        _ = creative.vast?.tagUrl
        _ = creative.vast?.xmlBase64
        _ = creative.journey
        _ = creative.verificationScriptResources

        _ = creative.tracking.impressions
        _ = creative.tracking.clicks
        _ = creative.tracking.custom
        _ = creative.tracking.videoEvents
        _ = creative.tracking.completions
        #expect(creative.tracking.getImpressionUrl(key: "default") != nil)
        #expect(creative.tracking.getClickUrl(key: "nope") == nil)
        #expect(creative.tracking.getCustomUrl(key: "nope") == nil)
        #expect(creative.tracking.getVideoEventUrl(key: "nope") == nil)
        #expect(creative.tracking.getCompletionUrl(key: "nope") == nil)
        #expect(creative.tracking.hasTrackingFor(type: .impression, key: "default"))
    }
}

// MARK: - Support

/// A well-formed creative with an optional `journey` block, used to type-check the documented
/// read surface without inventing a second fixture format.
private func docCreative(journey: String?) throws -> Creative {
    let journeyFragment = journey.map { ",\n    \"journey\": \($0)" } ?? ""
    let json = """
        {
            "contents": [{"key": "headline", "value": "Hi", "type": "text"}],
            "advertiser": {"id": "adv1", "name": "Acme"},
            "template": {"key": "standard", "style": "default"},
            "tracking": {"impressions": [{"key": "default", "url": "https://h/v1/tracking?e=a"}]},
            "metadata": {
                "adId": "a", "creativeId": "c", "templateId": "t", "placementId": "p",
                "priority": "standard"
            }\(journeyFragment)
        }
        """
    return try JSONDecoder().decode(Creative.self, from: Data(json.utf8))
}
