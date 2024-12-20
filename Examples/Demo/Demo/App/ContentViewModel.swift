import AdMoai
import Foundation
import UIKit

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var placement: Placement = Placement(key: "home")
    @Published var user = User(
        id: "user_123",
        ip: "203.0.113.1",
        timezone: TimeZone.current.identifier,
        consent: User.Consent(gdpr: true)
    )
    @Published var targeting: Targeting = Targeting()
    @Published var isLoading = false
    @Published var response: APIResponse<DecisionResponse>?
    @Published var collectAppData = true
    @Published var collectDeviceData = true

    private var sdk: AdMoai

    // MARK: - Initialization

    init() {
        /// Initialize the SDK with a configuration
        let config = SDKConfig(baseUrl: "https://mock.api.admoai.com")
        self.sdk = AdMoai(config: config)

        /// For completeness, we can set the user config to a different user to see how the SDK behaves with different users.
        sdk.setUserConfig(id: "sample_user")
        user = User(
            id: sdk.userConfig.id, ip: user.ip, timezone: user.timezone, consent: user.consent)
    }

    // MARK: - Public Methods

    /// Builds a decision request with current configuration
    func buildRequest() -> DecisionRequest {
        let builder = sdk.createRequestBuilder()
            .addPlacement(placement)
            .setGeoTargeting(targeting.geo)
            .setLocationTargeting(targeting.location)
            .setCustomTargeting(targeting.custom)
            .setUserIp(user.ip)
            .setUserId(user.id)
            .setUserTimezone(user.timezone)
            .setUserConsent(user.consent ?? User.Consent(gdpr: false))

        /// Optionally disable data collection based on user preferences
        if !collectAppData {
            _ = builder.disableAppCollection()
        }

        if !collectDeviceData {
            _ = builder.disableDeviceCollection()
        }

        return builder.build()
    }

    /// Returns the HTTP request that would be sent to the server
    func getHTTPRequest() throws -> HTTPRequest {
        let request = buildRequest()
        return try sdk.getHttpRequest(request)
    }

    /// Loads ads from the server using current configuration
    func loadAds() async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let request = buildRequest()
        response = try await sdk.requestAds(request)
    }

    func handleAdImpression(creative: Creative, key: String) {
        sdk.fireImpression(tracking: creative.tracking, key: key)
    }

    func handleAdClick(creative: Creative, key: String) {
        if let clickUrl = creative.tracking.getClickUrl(key: key),
            let url = URL(string: clickUrl)
        {
            UIApplication.shared.open(url)
        }
    }

    func handleCustomEvent(tracking: Tracking, key: String) {
        sdk.fireCustom(tracking: tracking, key: key)
    }
}
