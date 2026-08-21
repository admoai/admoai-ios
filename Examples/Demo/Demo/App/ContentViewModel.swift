import AdMoai
import Foundation
import OSLog
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

    var sdk: AdMoai

    private let logger = Logger(subsystem: "com.admoai.example", category: "AdClick")

    // MARK: - Initialization

    init() {
        /// Initialize the SDK with a configuration
        let config = SDKConfig(baseUrl: "http://localhost:8080", apiVersion: "2025-11-01")
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
            .setDestinationTargeting(targeting.destination)
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

    /// Handles a tap on an ad: record the click, then navigate — two separate steps.
    ///
    /// `fireClick` reports the click and gives you nothing to open. The destination comes from the
    /// creative's own content field (`destinationKey`), never from `tracking.clicks[].url`: that
    /// URL is a measurement endpoint, and opening it both double-counts the click and sends the
    /// user to an opaque redirect instead of the advertiser's page.
    func handleAdClick(creative: Creative, trackingKey: String, destinationKey: String) {
        sdk.fireClick(tracking: creative.tracking, key: trackingKey)

        /// No destination is a valid outcome — the `textOnly` template declares none. The
        /// click is still recorded above; there is simply nowhere to go.
        guard let destination = AdClickResolver.destination(in: creative, key: destinationKey)
        else { return }

        switch destination {
        case .web(let url):
            UIApplication.shared.open(url)
        case .deeplink(let url):
            /// Your app owns its own links: route them through your router or `NavigationPath`
            /// rather than handing them back to the system. The Demo has no internal routes, so
            /// it reports where it would have navigated.
            logger.info("Would route in-app deeplink: \(url.absoluteString, privacy: .public)")
        }
    }

    func handleCustomEvent(tracking: Tracking, key: String) {
        sdk.fireCustomEvent(tracking: tracking, key: key)
    }
}
