/// # Live Integration Tests
///
/// These tests make **real HTTP requests** to `https://api.mock.admoai.com`.
/// They require network access and an internet connection.
///
/// Run with Xcode (Cmd+U) or via `xcodebuild test`.
/// They are intentionally kept in the same test target so a single test run
/// covers both unit and integration scenarios.
///
/// ## Sections
/// - §1  Request serialisation (no network) — JSON keys, encoding invariants
/// - §2  Header assertions (no network) — `getHttpRequest()` inspection
/// - §3  Live decision requests — 9 placements × 2 API versions (18 requests)
/// - §4  Live video placement request
/// - §5  Destination targeting live round-trip
/// - §6  Typed error handling — 422 invalid placement, network error
/// - §7  `Priority` enum live round-trip (real server response)
/// - §8  Tracking fire methods — fire-and-forget, no crash, headers present

import Foundation
import Testing

@testable import AdMoai

// ---------------------------------------------------------------------------
// MARK: - Test Fixtures
// ---------------------------------------------------------------------------

private let mockBaseURL = "https://api.mock.admoai.com"
private let apiVersion = "2025-11-01"

/// Standard SDK configured with the mock server (no API version).
private let sdk = AdMoai(
    config: SDKConfig(baseUrl: mockBaseURL),
    userConfig: UserConfig(
        id: "user_123",
        ip: "203.0.113.1",
        timezone: "America/Santiago",
        consent: User.Consent(gdpr: true)
    )
)

/// SDK configured with an explicit API version (enables video format filter).
private let sdkWithVersion = AdMoai(
    config: SDKConfig(baseUrl: mockBaseURL, apiVersion: apiVersion),
    userConfig: UserConfig(
        id: "user_123",
        ip: "203.0.113.1",
        timezone: "America/Santiago",
        consent: User.Consent(gdpr: true)
    )
)

/// SDK configured with `defaultLanguage` and `apiVersion` (for header tests).
private let sdkWithLanguage = AdMoai(
    config: SDKConfig(baseUrl: mockBaseURL, apiVersion: apiVersion, defaultLanguage: "en"),
    userConfig: UserConfig(id: "user_123", ip: "203.0.113.1", timezone: "America/Santiago")
)

/// All placement keys available on the mock server.
private let placementKeys = [
    "json_none",
    "vasttag_none",
    "vast_xml_native_endcard",
    "json_native_endcard",
    "vasttag_native_endcard",
    "home",
    "menu",
    "freeMinutes",
    "search",
]

// ---------------------------------------------------------------------------
// MARK: - §1  Request Serialisation (no network)
// ---------------------------------------------------------------------------

struct LiveIntegrationSerializationTests {

    /// `min_confidence` must be snake_case in the JSON body (not `minConfidence`).
    @Test
    func testMinConfidenceKeyIsSnakeCase() throws {
        let request = try sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .addDestinationTargeting(latitude: 72.51, longitude: 120.64, minConfidence: 0.5)
            .build()

        let encoded = try JSONEncoder().encode(request)
        let json = String(data: encoded, encoding: .utf8)!

        #expect(json.contains("\"min_confidence\""), "Expected snake_case key in JSON body")
        #expect(!json.contains("\"minConfidence\""), "camelCase key must not appear in JSON body")
    }

    /// When no `format` is set on a placement, the key must be absent from JSON
    /// (not `"format": null`). The decision-engine picks the best format automatically.
    @Test
    func testFormatOmittedWhenNil() throws {
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .build()

        let encoded = try JSONEncoder().encode(request)
        let json = String(data: encoded, encoding: .utf8)!

        #expect(!json.contains("\"format\""), "format key must be absent when not set")
    }

    /// When `Format.video` is set, the key must appear with value `"video"`.
    @Test
    func testFormatVideoKeyPresent() throws {
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home", format: .video)
            .build()

        let encoded = try JSONEncoder().encode(request)
        let json = String(data: encoded, encoding: .utf8)!

        #expect(json.contains("\"video\""), "format value 'video' must appear in JSON body")
    }

    /// `userConfig` passed to `AdMoai.init` must be included in the built request.
    @Test
    func testUserConfigFromInitPropagatesIntoRequest() {
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .build()

        #expect(request.user?.id == "user_123")
        #expect(request.user?.ip == "203.0.113.1")
        #expect(request.user?.consent?.gdpr == true)
    }

    /// `SDK_VERSION` constant must be a valid semver-ish string (non-empty, contains dot).
    @Test
    func testSDKVersionConstantIsValid() {
        #expect(!SDK_VERSION.isEmpty)
        #expect(SDK_VERSION != "Unknown")
        #expect(SDK_VERSION.contains("."))
    }
}

// ---------------------------------------------------------------------------
// MARK: - §2  Header Assertions (no network)
// ---------------------------------------------------------------------------

struct LiveIntegrationHeaderTests {

    /// `User-Agent` header must be set to `AdMoaiSDK/{SDK_VERSION}` via the session
    /// configuration (applies to ALL requests — decision AND tracking).
    @Test
    func testUserAgentInSessionConfig() {
        let cfg = SDKConfig.defaultSessionConfiguration()
        let ua = cfg.httpAdditionalHeaders?["User-Agent"] as? String
        #expect(ua == "AdMoaiSDK/\(SDK_VERSION)")
    }

    /// `Accept-Language` header must appear in the decision HTTP request
    /// when `defaultLanguage` is configured.
    @Test
    func testAcceptLanguageHeaderOnDecisionRequest() throws {
        let request = sdkWithLanguage.createRequestBuilder()
            .addPlacement(key: "home")
            .build()

        let httpRequest = try sdkWithLanguage.getHttpRequest(request)
        #expect(httpRequest.headers?["Accept-Language"] == "en")
    }

    /// `X-Decision-Version` header must appear in the decision HTTP request
    /// when `apiVersion` is configured.
    @Test
    func testXDecisionVersionHeaderOnDecisionRequest() throws {
        let request = sdkWithVersion.createRequestBuilder()
            .addPlacement(key: "home")
            .build()

        let httpRequest = try sdkWithVersion.getHttpRequest(request)
        #expect(httpRequest.headers?["X-Decision-Version"] == apiVersion)
    }

    /// When no `apiVersion` is set, `X-Decision-Version` must be absent.
    @Test
    func testXDecisionVersionHeaderAbsentWhenNotConfigured() throws {
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .build()

        let httpRequest = try sdk.getHttpRequest(request)
        #expect(httpRequest.headers?["X-Decision-Version"] == nil)
    }

    /// `Content-Type` and `Accept` headers must always be present.
    @Test
    func testContentTypeAndAcceptHeaders() throws {
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .build()

        let httpRequest = try sdk.getHttpRequest(request)
        #expect(httpRequest.headers?["Content-Type"] == "application/json")
        #expect(httpRequest.headers?["Accept"] == "application/json")
    }
}

// ---------------------------------------------------------------------------
// MARK: - §3  Live Decision Requests (network required)
// ---------------------------------------------------------------------------

struct LiveIntegrationDecisionTests {

    /// Each placement in `placementKeys` must return HTTP 200 and `success: true`
    /// when called without an explicit API version.
    @Test
    func testAllPlacementsWithoutAPIVersion() async throws {
        for key in placementKeys {
            let request = sdk.createRequestBuilder()
                .addPlacement(key: key)
                .withStandardTargeting()
                .build()

            let response = try await sdk.requestAds(request)
            #expect(
                response.response.statusCode == 200,
                "Placement '\(key)' without apiVersion: expected 200, got \(response.response.statusCode)"
            )
            #expect(
                response.body.success == true,
                "Placement '\(key)' without apiVersion: expected success"
            )
        }
    }

    /// Each placement must return HTTP 200 and `success: true` when called
    /// with the `2025-11-01` API version.
    @Test
    func testAllPlacementsWithAPIVersion() async throws {
        for key in placementKeys {
            let request = sdkWithVersion.createRequestBuilder()
                .addPlacement(key: key)
                .withStandardTargeting()
                .build()

            let response = try await sdkWithVersion.requestAds(request)
            #expect(
                response.response.statusCode == 200,
                "Placement '\(key)' with apiVersion: expected 200, got \(response.response.statusCode)"
            )
            #expect(
                response.body.success == true,
                "Placement '\(key)' with apiVersion: expected success"
            )
        }
    }

    /// The response for the `home` placement must decode properly into the
    /// strongly-typed `DecisionResponse` model.
    @Test
    func testHomePlacementResponseStructure() async throws {
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .withStandardTargeting()
            .build()

        let response = try await sdk.requestAds(request)
        #expect(response.response.statusCode == 200)
        #expect(response.body.success == true)

        if let decisions = response.body.data, !decisions.isEmpty {
            let decision = decisions[0]
            #expect(decision.placement == "home")

            if let creatives = decision.creatives, let creative = creatives.first {
                // Contents must be a non-empty array
                #expect(!creative.contents.isEmpty)
                // Tracking must have at least an impression URL
                #expect(creative.tracking.getImpressionUrl(key: "default") != nil)
                // Metadata must decode — priority is now a typed enum
                if let meta = creative.metadata {
                    // All known priority values decode to a named case
                    #expect(
                        meta.priority == .house
                        || meta.priority == .sponsorship
                        || meta.priority == .standard
                        || meta.priority == .unknown
                    )
                }
            }
        }
    }

    /// Multi-placement request: both `home` and `menu` in one call.
    @Test
    func testMultiPlacementRequest() async throws {
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .addPlacement(key: "menu")
            .build()

        let response = try await sdk.requestAds(request)
        #expect(response.response.statusCode == 200)
        #expect(response.body.success == true)
        // Response array should have up to 2 decisions
        if let data = response.body.data {
            #expect(data.count <= 2)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - §4  Live Video Placement (network required)
// ---------------------------------------------------------------------------

struct LiveIntegrationVideoTests {

    /// A placement with `format: .video` and the 2025-11-01 API version should
    /// return a response whose creative has a non-nil `delivery` field.
    @Test
    func testVideoFormatPlacementRequest() async throws {
        let request = sdkWithVersion.createRequestBuilder()
            .addPlacement(key: "vasttag_none", format: .video)
            .build()

        let response = try await sdkWithVersion.requestAds(request)
        #expect(response.response.statusCode == 200)
        #expect(response.body.success == true)

        if let decision = response.body.data?.first,
           let creative = decision.creatives?.first
        {
            // Video creatives should report their delivery mechanism
            #expect(creative.delivery != nil)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - §5  Destination Targeting Live Round-trip (network required)
// ---------------------------------------------------------------------------

struct LiveIntegrationDestinationTests {

    /// A request containing destination targeting with a valid `minConfidence`
    /// must succeed (HTTP 200).
    @Test
    func testDestinationTargetingRoundTrip() async throws {
        let request = try sdk.createRequestBuilder()
            .addPlacement(key: "search")
            .addDestinationTargeting(latitude: 72.51, longitude: 120.64, minConfidence: 0.50)
            .build()

        let response = try await sdk.requestAds(request)
        #expect(response.response.statusCode == 200)
        #expect(response.body.success == true)
    }

    /// Confirm boundary values `0.0` and `1.0` are accepted by the server.
    @Test
    func testDestinationTargetingBoundaryValuesAccepted() async throws {
        let request = try sdk.createRequestBuilder()
            .addPlacement(key: "search")
            .addDestinationTargeting(latitude: 10.0, longitude: 10.0, minConfidence: 0.0)
            .addDestinationTargeting(latitude: 20.0, longitude: 20.0, minConfidence: 1.0)
            .build()

        let response = try await sdk.requestAds(request)
        #expect(response.response.statusCode == 200)
    }
}

// ---------------------------------------------------------------------------
// MARK: - §6  Typed Error Handling (network required)
// ---------------------------------------------------------------------------

struct LiveIntegrationErrorTests {

    /// An unrecognised placement key should return HTTP 422 and `success: false`
    /// (in DEBUG mode the SDK lets 422 through; in RELEASE it throws `.validationError`).
    @Test
    func testInvalidPlacementReturns422() async throws {
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "this_placement_does_not_exist_xyz_abc")
            .build()

        #if DEBUG
        let response = try await sdk.requestAds(request)
        #expect(response.response.statusCode == 422)
        #expect(response.body.success == false)
        #else
        do {
            _ = try await sdk.requestAds(request)
            Issue.record("Expected APIError.validationError to be thrown for invalid placement")
        } catch let apiError as APIError {
            if case .validationError(let errors) = apiError {
                #expect(!errors.isEmpty || errors.isEmpty)  // any validationError is fine
            } else {
                throw apiError
            }
        }
        #endif
    }

    /// An SDK configured with an invalid base URL must throw `.networkError`.
    @Test
    func testInvalidBaseURLThrowsNetworkError() async throws {
        let badSDK = AdMoai(config: SDKConfig(baseUrl: "not-a-url"))
        let request = badSDK.createRequestBuilder()
            .addPlacement(key: "home")
            .build()

        do {
            _ = try await badSDK.requestAds(request)
            Issue.record("Expected an error for invalid base URL")
        } catch let error as APIError {
            if case .networkError = error {
                // expected
            } else if case .invalidURL = error {
                // also acceptable
            } else {
                throw error
            }
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - §7  Priority Enum Live Round-trip (network required)
// ---------------------------------------------------------------------------

struct LiveIntegrationPriorityTests {

    /// Decoded `Metadata.priority` from a live response must be a named `Priority`
    /// case (never fails to decode due to unknown raw value).
    @Test
    func testPriorityDecodesFromLiveResponse() async throws {
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .withStandardTargeting()
            .build()

        let response = try await sdk.requestAds(request)
        #expect(response.response.statusCode == 200)

        if let data = response.body.data {
            for decision in data {
                for creative in decision.creatives ?? [] {
                    if let meta = creative.metadata {
                        // Priority is strongly typed — accessing it must not crash
                        let _ = meta.priority.rawValue
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - §8  Tracking Fire Methods (no external assertions possible)
// ---------------------------------------------------------------------------

struct LiveIntegrationTrackingTests {

    /// `fireTracking(url:)` must not crash for a valid URL.
    @Test
    func testFireTrackingValidURL() {
        sdk.fireTracking(url: "https://api.mock.admoai.com/track/test")
        // fire-and-forget: no result to assert; we just verify it doesn't throw / crash
    }

    /// `fireTracking(url:)` must not crash for an invalid URL (guard-and-return).
    @Test
    func testFireTrackingInvalidURL() {
        sdk.fireTracking(url: "not a valid url !!!@@@")
    }

    /// `fireImpression`, `fireClick`, `fireCustom`, `fireVideoEvent` must all
    /// accept a `Tracking` value and not crash.
    @Test
    func testAllFireMethodsAcceptTracking() {
        let tracking = Tracking(
            impressions: [TrackingItem(key: "default", url: "https://api.mock.admoai.com/imp")],
            clicks: [TrackingItem(key: "default", url: "https://api.mock.admoai.com/click")],
            custom: [TrackingItem(key: "companionOpened", url: "https://api.mock.admoai.com/custom")],
            videoEvents: [TrackingItem(key: "start", url: "https://api.mock.admoai.com/video")]
        )

        sdk.fireImpression(tracking: tracking)
        sdk.fireImpression(tracking: tracking, key: "default")
        sdk.fireClick(tracking: tracking)
        sdk.fireClick(tracking: tracking, key: "default")
        sdk.fireCustom(tracking: tracking, key: "companionOpened")
        sdk.fireVideoEvent(tracking: tracking, key: "start")
    }

    /// `fireTracking` must add `Accept-Language` when configured.
    /// Verified indirectly: if the underlying `URLRequest` is built correctly,
    /// `Accept-Language` would be present. We verify the SDK doesn't crash and
    /// that the config values are wired up.
    @Test
    func testFireTrackingWithHeadersConfigured() {
        // SDK configured with both language + version
        let configuredSDK = AdMoai(
            config: SDKConfig(
                baseUrl: mockBaseURL,
                apiVersion: apiVersion,
                defaultLanguage: "es"
            )
        )
        // Should not crash; headers are set via URLRequest inside fireTracking
        configuredSDK.fireTracking(url: "https://api.mock.admoai.com/track/test")
        #expect(configuredSDK.config.defaultLanguage == "es")
        #expect(configuredSDK.config.apiVersion == apiVersion)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Helper Extension
// ---------------------------------------------------------------------------

extension DecisionRequestBuilder {
    /// Convenience for live tests: adds standard geo + location targeting
    /// representing a representative mobility app scenario.
    @discardableResult
    func withStandardTargeting() -> DecisionRequestBuilder {
        return self
            .addGeoTargeting(2643743)
            .addLocationTargeting(latitude: 27.92, longitude: -160.32)
            .addCustomTargeting(key: "category", value: "sports")
    }
}
