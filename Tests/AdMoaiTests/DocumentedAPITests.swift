@testable import AdMoai
import Foundation
import Testing
#if canImport(UIKit) && canImport(SafariServices)
    import SafariServices
#endif
#if canImport(UIKit)
    import UIKit
#endif

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
    @available(*, deprecated) // `fireCustom` is exercised deliberately as a documented alias.
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

        // README "Third-party Event Trackers (automatic)" + response tree: the documented
        // field and entry type exist (renaming either breaks this build, as promised).
        let documentedTrackers: [ThirdPartyTracker]? = creative.tracking.thirdPartyTrackers
        if let entry = documentedTrackers?.first {
            let _: (String, String, String?, String?, String) =
                (entry.trackerId, entry.eventType, entry.matchType, entry.eventKey, entry.url)
        }

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
            """
        )

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
            Decision.self, from: Data(#"{"placement":"home","creatives":[]}"#.utf8)
        )
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

    // MARK: - Audience signals

    // Scenario: README "Audience signals" — every call and type the guide shows
    @Test
    func testDocumentedAudienceSignalsSurfaceExists() throws {
        var sdk = AdMoai(config: docConfig())

        let builder = try sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .setAgeGroup(.age25To34)
            .setGender(.preferNotToSay)
            .setAccountType(.personal)
            .setSubscriptionStatus(.noSubscription)
            .setAccountTenure(.days0To30)
            .setActivityFrequency30d(.zero)
            .setLastActivityRecency(.never)
            .setPublisherSegments(["airport_commuter", "high_value"])
        _ = try builder.setPublisherSegments(nil)
        _ = builder.disableDeviceCollection()
        #expect(throws: SDKError.self) { try builder.setPublisherSegments(["not valid"]) }
        #expect(AudienceSignals.Key.allCases.count == 8)

        sdk.setDeviceCarrier("Example Mobile")
        sdk.enableDeviceCategoryCollection()
        sdk.setDeviceCategory(.tablet)
        sdk.setDeviceCategory(nil)
        sdk.clearDeviceConfig()
        sdk.resetDeviceConfig()

        let refusal = APIError.validationError([])
        if case let .validationError(errors) = refusal {
            #expect(errors.map(\.code).isEmpty)
        }

        // README "Reading an error code"
        let rejected: APIError = .requestRejected(status: 400, errors: [])
        if case let .requestRejected(status, errors) = rejected {
            #expect(status == 400)
            #expect(errors.isEmpty)
        }
        for refusal in rejected.engineErrors {
            let code: Int = refusal.code
            let message: String = refusal.message
            _ = (code, message)
        }
        let status: Int? = rejected.httpStatus
        #expect(status == 400)
        // README "Upgrading from 1.9.0"
        switch APIError.requestRejected(status: 429, errors: []) {
        case .requestRejected(429, _), .clientError(.tooManyRequests): break
        case .requestRejected(410, _), .clientError(.gone): Issue.record("410 is not 429")
        default: Issue.record("a 429 matches the back-off case")
        }
    }

    // Scenario: README "Carousel" — slides in server order, read through `getContent(key:)`, and
    // the three slide trackers
    @Test
    func testDocumentedCarouselSurfaceExists() throws {
        let sdk = AdMoai(config: docConfig())
        let json = """
        {"contents": [{"key": "slides", "type": "slides", "value": [
            {"slideId": "slide_b", "position": 2,
             "contents": [{"key": "image", "value": "https://cdn.example/b.png", "type": "image"},
                          {"key": "destination_url", "value": "https://example.com/b", "type": "url"}]},
            {"slideId": "slide_a", "position": 1,
             "contents": [{"key": "headline", "value": "A", "type": "text"}]}
         ]}], "metadata": {"effectiveStandardFormatKey": "carousel"}, "advertiser": {}, "tracking": {}}
        """
        let creative = try JSONDecoder().decode(Creative.self, from: Data(json.utf8))

        #expect(creative.metadata?.effectiveStandardFormatKey == "carousel")
        #expect(creative.slides.map(\.slideId) == ["slide_b", "slide_a"]) // never re-sorted
        let first = try #require(creative.slides.first)
        let position: Int = first.position
        #expect(position == 2)
        #expect(first.contents.getContent(key: "image")?.value.description == "https://cdn.example/b.png")
        #expect(first.contents.getContent(key: "destination_url")?.value.description == "https://example.com/b")
        #expect(creative.slides[1].contents.getContent(key: "image") == nil)
        let tracking: SlideTracking? = first.tracking
        #expect(tracking == nil) // a slide without tracking still renders

        let view: () = sdk.trackSlideView(first)
        let views: () = sdk.trackSlideViews(creative.slides)
        let click: () = sdk.trackSlideClick(first, in: creative)
        _ = (view, views, click)
    }

    // Scenario: README "Branded Assets" — `metadata.assetContext`, the three content keys and
    // `fireAssetTap`; README "Reading the pins" — `pinImage` read the same way
    @Test
    func testDocumentedBrandedAssetsSurfaceExists() throws {
        let sdk = AdMoai(config: docConfig())
        let json = """
        {"contents": [
            {"key": "branded_image", "value": "https://cdn.example/car.png", "type": "image"},
            {"key": "accessible_label", "value": "Acme car", "type": "text"},
            {"key": "destination_url", "value": "https://example.com", "type": "url"},
            {"key": "pinImage", "value": "https://cdn.example/pin.png", "type": "image"}
         ], "metadata": {"effectiveStandardFormatKey": "branded_assets", "assetContext": "vehicle_marker"},
         "advertiser": {}, "tracking": {}}
        """
        let creative = try JSONDecoder().decode(Creative.self, from: Data(json.utf8))
        let contents = creative.contents

        #expect(creative.metadata?.assetContext == "vehicle_marker")
        #expect(contents.getContent(key: "branded_image")?.value.description == "https://cdn.example/car.png")
        #expect(contents.getContent(key: "accessible_label")?.value.description == "Acme car")
        #expect(contents.getContent(key: "destination_url")?.value.description == "https://example.com")
        #expect(contents.getContent(key: "pinImage")?.value.description == "https://cdn.example/pin.png")

        let tap: () = sdk.fireAssetTap(tracking: creative.tracking)
        let click: () = sdk.fireClick(tracking: creative.tracking)
        _ = (tap, click)
    }

    // MARK: - Lead Generation forms

    // Scenario: README "Lead Generation forms" / "Opt in" — both providers, opt-in, opt-out,
    // re-opt-in for a new user
    @Test
    func testLeadGenerationOptInSurfaceExists() {
        var sdk = AdMoai(config: docConfig())
        #expect(!sdk.interactiveExperiencesEnabled)

        let boltShift = BoltShiftProfileValues()
        #expect(boltShift.availableKeys == [.fullName, .email, .phone])
        sdk.enableInteractiveExperiences(valueProvider: boltShift)

        // A new signed-in user: a new provider, or opt out on logout.
        sdk.enableInteractiveExperiences(valueProvider: NoPrefillProvider())
        #expect(NoPrefillProvider().availableKeys.isEmpty)
        sdk.setUserConfig(id: "user_456")
        sdk.disableInteractiveExperiences()
        #expect(!sdk.interactiveExperiencesEnabled)
    }

    // Scenario: README "Lead Generation forms" / "Reading the creative" — the switch over
    // `interactiveExperience` and the no-opt-in controller path
    @Test
    @MainActor
    func testLeadGenerationReadingSurfaceExists() throws {
        let sdk = AdMoai(config: docConfig())
        let plain = try docCreative(journey: nil)
        #expect(plain.interactiveExperience == nil)

        var served: [String] = []
        for creative in [plain] {
            switch creative.interactiveExperience {
            case nil:
                served.append("native")
            case .unsupported?:
                break
            case let .leadGeneration(experience)?:
                served.append("lead")
                // Not opted in: no controller, so the app does not show the creative.
                #expect(sdk.makeLeadFormController(for: experience, presentation: .inline) == nil)
                #expect(sdk.makeLeadFormController(for: experience, presentation: .fullScreen) == nil)
            }
        }
        #expect(served == ["native"])
    }

    #if canImport(UIKit) && canImport(SafariServices)
        // Scenario: README "Lead Generation forms" / "Showing the form" and "Delegate" — the
        // documented host compiles; it is never run, so no form is opened.
        @Test
        @MainActor
        func testLeadGenerationHostSurfaceExists() throws {
            let sdk = AdMoai(config: docConfig())
            let host = try LeadCreativeHost(
                creative: docCreative(journey: nil),
                sdk: sdk,
                container: UIView(),
                presenter: UIViewController()
            )
            _ = host.creativeTapped
        }
    #endif
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

// Scenario: README "Lead Generation forms" — the providers exactly as documented.
final class BoltShiftProfileValues: LeadFormValueProvider {
    private let profile: [StandardAttributeKey: String] = [
        .fullName: "Alex Rider",
        .email: "alex@example.com",
        .phone: "+1 555 0100",
    ]

    var availableKeys: Set<StandardAttributeKey> {
        Set(profile.keys)
    }

    func value(for key: StandardAttributeKey) async -> String? {
        profile[key]
    }
}

final class NoPrefillProvider: LeadFormValueProvider {
    var availableKeys: Set<StandardAttributeKey> {
        []
    }
}

#if canImport(UIKit) && canImport(SafariServices)
    // Scenario: README "Lead Generation forms" — the host, tap handling and delegate as documented.
    @MainActor
    final class LeadCreativeHost: LeadFormControllerDelegate {
        private var controller: LeadFormController?
        private let creative: Creative
        private let sdk: AdMoai
        private let container: UIView
        private weak var presenter: UIViewController?

        init(creative: Creative, sdk: AdMoai, container: UIView, presenter: UIViewController) {
            self.creative = creative
            self.sdk = sdk
            self.container = container
            self.presenter = presenter
        }

        func prepare(for experience: LeadGenerationExperience, fullScreen: Bool = false) {
            let presentation: LeadFormPresentation = fullScreen ? .fullScreen : .inline
            guard let controller = sdk.makeLeadFormController(for: experience, presentation: presentation) else {
                return
            }
            controller.delegate = self
            self.controller = controller
            controller.prepare()
        }

        func creativeTapped() {
            guard let controller else { return }
            sdk.fireClick(tracking: creative.tracking)
            controller.open()
            switch controller.presentation {
            case .inline:
                let form = controller.formView
                form.frame = container.bounds
                container.addSubview(form)
            case .fullScreen:
                presenter?.present(controller.formViewController, animated: true)
            }
        }

        func leadFormController(_ controller: LeadFormController, didChange state: LeadFormState) {
            switch state {
            case .visible:
                break
            case .failed(retryable: true):
                controller.retry()
            case .failed(retryable: false), .expired:
                closeForm(controller)
            case let .submitted(leadId):
                _ = leadId
            default:
                break
            }
        }

        func leadFormControllerDidRequestClose(_ controller: LeadFormController) {
            closeForm(controller)
        }

        func leadFormController(_: LeadFormController, openExternalURL url: URL, purpose _: LeadFormLinkPurpose) {
            presenter?.present(SFSafariViewController(url: url), animated: true)
        }

        // README "Good to know": Back.
        func backTapped() {
            if controller?.handleBack() == true {
                return
            }
        }

        private func closeForm(_ controller: LeadFormController) {
            controller.formView.removeFromSuperview()
            controller.dispose()
            self.controller = nil
        }
    }
#endif
