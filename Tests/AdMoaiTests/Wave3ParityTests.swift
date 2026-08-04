import Foundation
import Testing

@testable import AdMoai

/// Wave 3 cross-SDK parity guards (F9–F20).
///
/// Each scenario pins one divergence found by walking the engine contract against all three SDKs.
/// Reverting the corresponding fix must make its scenario fail.
struct Wave3ParityTests {

    private var config: SDKConfig {
        SDKConfig(baseUrl: "https://mock.api.admoai.com", apiVersion: "2025-11-01")
    }

    // MARK: - F9: default timeouts match Android and Flutter

    // Scenario: a publisher accepts the SDK's default networking configuration.
    @Test
    func testDefaultRequestTimeoutMatchesOtherSDKs() {
        // Android and Flutter both default to 10s. iOS defaulted to 30s, so the same slow endpoint
        // succeeded here and timed out there — a multi-stage journey looked flaky on two platforms
        // only. An ad request slower than 10s is worthless anyway: the surface is long gone.
        let configuration = SDKConfig.defaultSessionConfiguration()
        #expect(configuration.timeoutIntervalForRequest == 10)
        #expect(configuration.timeoutIntervalForResource == 30)
    }

    // MARK: - F10: no placements fails locally, without a network round-trip

    // Scenario: a publisher submits a request they forgot to add a placement to.
    @Test
    func testRequestWithNoPlacementsThrowsBeforeNetwork() async {
        // The engine rejects this with a 422, so spending a round-trip to learn it is waste.
        // Android throws AdMoaiConfigurationException from build(); iOS raises here instead,
        // because making build() `throws` would force `try` on 80 call sites for no behavioural
        // gain. What the publisher observes is the same: a typed error, no network activity.
        let sdk = AdMoai(config: config)
        let request = sdk.createRequestBuilder().build()

        await #expect(throws: SDKError.noPlacements) {
            _ = try await sdk.requestAds(request)
        }
        #expect(throws: SDKError.noPlacements) {
            _ = try sdk.getHttpRequest(request)
        }
    }

    @Test
    func testRequestWithAPlacementDoesNotThrowLocally() throws {
        let sdk = AdMoai(config: config)
        let request = sdk.createRequestBuilder().addPlacement(key: "home").build()
        // Builds an HTTPRequest without touching the network — proves the guard is scoped to the
        // empty case and does not reject legitimate requests.
        let http = try sdk.getHttpRequest(request)
        #expect(http.path == "/v1/decision")
    }

    // MARK: - F12: geo targeting deduplicates, like every other targeting list

    // Scenario: the same geoname is added twice.
    @Test
    func testGeoTargetingDeduplicates() {
        // Location, destination and custom were already deduped here; geo was not, so identical
        // input produced a different body on Android (which dedupes) than on iOS. Geo is ANY, so
        // duplicates never changed the decision — but the payload should not differ by platform.
        let sdk = AdMoai(config: config)
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .addGeoTargeting(5128581)
            .addGeoTargeting(2643743)
            .addGeoTargeting(5128581)
            .build()

        #expect(request.targeting?.geo == [5128581, 2643743])
    }

    // MARK: - F15: getSkipOffset returns only meaningful scalars

    // Scenario: the content field exists but holds an explicit JSON null.
    @Test
    func testSkipOffsetNullContentYieldsNil() throws {
        // AnyCodable.description rendered NSNull as the literal "null", so getSkipOffset() handed
        // back a String a publisher would parse as a duration. Android and Flutter both return
        // null here.
        let creative = try decodeCreative(
            contents: """
                {"key": "skip_offset", "value": null, "type": "text"}
                """)
        #expect(creative.getSkipOffset() == nil)
    }

    @Test
    func testSkipOffsetStructuredContentYieldsNil() throws {
        let creative = try decodeCreative(
            contents: """
                {"key": "skip_offset", "value": {"seconds": 5}, "type": "text"}
                """)
        #expect(creative.getSkipOffset() == nil)
    }

    @Test
    func testSkipOffsetScalarContentStillResolves() throws {
        let creative = try decodeCreative(
            contents: """
                {"key": "skip_offset", "value": 5, "type": "integer"}
                """)
        #expect(creative.getSkipOffset() == "5")
    }

    // MARK: - F18: optStatus parsing tolerates case and whitespace

    // Scenario: the engine (or a future proxy) echoes a differently-cased opt status.
    @Test
    func testJourneyOptParsingIsCaseAndWhitespaceTolerant() {
        // Android trims and lowercases; iOS matched the raw value exactly. Today's engine marshals
        // a typed enum and only emits lowercase, so this is defensive — but a read path that
        // accepts "In" on one platform and nil on another is a parity seam either way.
        #expect(JourneyOpt.fromWire("in") == .optIn)
        #expect(JourneyOpt.fromWire("IN") == .optIn)
        #expect(JourneyOpt.fromWire("  Out  ") == .optOut)
        #expect(JourneyOpt.fromWire("sideways") == nil)
        #expect(JourneyOpt.fromWire(nil) == nil)
    }

    @Test
    func testJourneyOptDecodesToleranltyFromAResponse() throws {
        let creative = try decodeCreative(
            contents: """
                {"key": "headline", "value": "hi", "type": "text"}
                """,
            journey: #"{"dealId":"jad_1","instanceId":"jinst_1","optStatus":"IN"}"#)
        #expect(creative.journeyOptStatus == .optIn)
    }

    @Test
    func testUnknownOptStatusStaysNilAndDoesNotDropTheBlock() throws {
        let creative = try decodeCreative(
            contents: """
                {"key": "headline", "value": "hi", "type": "text"}
                """,
            journey: #"{"dealId":"jad_1","instanceId":"jinst_1","optStatus":"sideways"}"#)
        #expect(creative.journeyOptStatus == nil)
        // The surrounding Journey block must survive an unparseable enum.
        #expect(creative.journeyDealId == "jad_1")
    }

    // MARK: - F19: the SDK User-Agent does not depend on the session configuration

    // Scenario: a publisher supplies their own URLSessionConfiguration.
    @Test
    func testUserAgentSurvivesACustomSessionConfiguration() throws {
        // The UA used to live only in defaultSessionConfiguration()'s httpAdditionalHeaders, so a
        // custom configuration silently stripped the header that identifies SDK traffic in engine
        // logs. It is now set per-request.
        let bare = URLSessionConfiguration.ephemeral  // no httpAdditionalHeaders
        let sdk = AdMoai(
            config: SDKConfig(
                baseUrl: "https://mock.api.admoai.com",
                apiVersion: "2025-11-01",
                sessionConfiguration: bare))

        let request = sdk.createRequestBuilder().addPlacement(key: "home").build()
        let http = try sdk.getHttpRequest(request)

        #expect(http.headers?["User-Agent"] == "AdMoaiSDK/\(SDK_VERSION)")
    }
}

// MARK: - Helpers

private func decodeCreative(contents: String, journey: String? = nil) throws -> Creative {
    let json = """
        {
          "contents": [\(contents)],
          "advertiser": {},
          "template": {"key": "t"},
          "tracking": {}\(journey.map { ", \"journey\": \($0)" } ?? "")
        }
        """
    return try JSONDecoder().decode(Creative.self, from: json.data(using: .utf8)!)
}
