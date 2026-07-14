/// # Journey Live Integration Tests
///
/// Real HTTP requests to `https://api.mock.admoai.com`. Diagnostic, not part of the
/// deterministic gate — gated behind `ADMOAI_LIVE_TESTS=1` (see `LiveTestGate`).
///
/// ## Deployment awareness
/// The Journey engine version (`2025-11-01` with `sessionId`/`journeyOpt` support) may not be
/// deployed to the mock host yet. A pre-Journey engine validates request bodies strictly and
/// rejects the additive Journey fields with HTTP 400 (`unknown field "sessionId"`). These
/// tests therefore:
/// - always verify what holds regardless of deployment (normal-ad serving + tracking under
///   `X-Tracking-Version` — residual risk #1), and
/// - treat Journey-field acceptance as **deployment-pending** (not a hard failure) until the
///   engine reports it, then assert the full contract.
///
/// This doubles as the deployment-readiness probe: once `2025-11-01` is live, the Journey
/// acceptance checks assert success automatically.

import Foundation
import Testing

@testable import AdMoai

private let liveBaseURL = "https://api.mock.admoai.com"
private let journeyApiVersion = "2025-11-01"

/// No Journey fields — always valid against any engine version.
private func makeNormalSDK() -> AdMoai {
    AdMoai(
        config: SDKConfig(baseUrl: liveBaseURL, apiVersion: journeyApiVersion),
        userConfig: UserConfig(id: "user_live", ip: "203.0.113.5", timezone: "America/Santiago")
    )
}

/// `true` when the response is a pre-Journey engine rejecting the additive fields as unknown.
private func isJourneyNotDeployed(_ response: APIResponse<DecisionResponse>) -> Bool {
    response.response.statusCode == 400
        && (response.rawBody?.lowercased().contains("unknown field") ?? false)
}

@Suite(.tags(.live), .enabled(if: LiveTestGate.enabled))
struct JourneyLiveIntegrationTests {

    // MARK: - True regardless of Journey deployment

    // Scenario (residual risk #1): a normal ad serves AND its impression tracking records
    //   under X-Tracking-Version — proving the header switch did not break normal tracking.
    @Test
    func testNormalAdServesAndTracksUnderXTrackingVersion() async throws {
        let sdk = makeNormalSDK()
        let request = sdk.createRequestBuilder().addPlacement(key: "home").build()

        let response = try await sdk.requestAds(request)
        #expect(response.response.statusCode == 200)
        #expect(response.body.success == true)

        guard
            let impressionURL = response.body.data?
                .first?.creatives?.first?.tracking.getImpressionUrl(key: "default"),
            let url = URL(string: impressionURL)
        else {
            return  // No creative served this run (mock inventory dependent) — nothing to fire.
        }

        var trackingRequest = URLRequest(url: url)
        trackingRequest.setValue(journeyApiVersion, forHTTPHeaderField: "X-Tracking-Version")
        let (_, trackingResponse) = try await URLSession.shared.data(for: trackingRequest)
        let statusCode = (trackingResponse as? HTTPURLResponse)?.statusCode ?? 0
        #expect(
            (200...299).contains(statusCode),
            "normal-ad tracking under X-Tracking-Version returned \(statusCode), expected 2xx")
    }

    // MARK: - Journey acceptance (deployment-pending until 2025-11-01 is live)

    // Scenario: the engine accepts a Journey request (sessionId + journeyOpt=in).
    //   Pending deployment, the engine rejects the unknown fields with 400 — recorded, not failed.
    @Test
    func testJourneyContextAcceptedOptIn() async throws {
        try await assertJourneyAccepted(opt: .optIn, sessionId: "live-trip-in-001")
    }

    // Scenario: journeyOpt=out is likewise accepted (deployment-pending).
    @Test
    func testJourneyContextAcceptedOptOut() async throws {
        try await assertJourneyAccepted(opt: .optOut, sessionId: "live-trip-out-001")
    }

    private func assertJourneyAccepted(opt: JourneyOpt, sessionId: String) async throws {
        let sdk = AdMoai(
            config: SDKConfig(baseUrl: liveBaseURL, apiVersion: journeyApiVersion),
            sessionId: sessionId
        )
        let request = sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .setJourneyOpt(opt)
            .build()

        let response: APIResponse<DecisionResponse>
        do {
            response = try await sdk.requestAds(request)
        } catch let error as APIError {
            // In RELEASE builds a 400 throws `.clientError(.badRequest)` (DEBUG returns it as
            // a body). Either way, a pre-Journey engine rejecting the fields is deployment-
            // pending, not a test failure.
            if case .clientError(.badRequest) = error { return }
            throw error
        }

        if isJourneyNotDeployed(response) {
            // Engine predates Journey — expected pre-deployment. Not a failure.
            return
        }

        // Engine is Journey-aware — assert the full contract.
        #expect(response.response.statusCode == 200)
        #expect(response.body.success == true)

        // Journey metadata (if a Journey deal served) must read safely and tolerantly.
        if let creative = response.body.data?.first?.creatives?.first, creative.isJourneyAd {
            #expect(creative.journeyDealId != nil)
            _ = creative.journeyOptStatus
            _ = creative.isJourneyCompletion
        }
    }
}
