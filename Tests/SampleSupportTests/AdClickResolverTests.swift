import AdMoai
import Foundation
import Testing

@testable import SampleSupport

// Ad click handling — record the click, then navigate to the creative's own destination
//
// Feature: A tapped ad records one click and navigates once to the real destination
//   As a publisher integrating from the sample app
//   I want the destination to come from the creative's content fields, never from a tracking URL
//   So that the click is counted exactly once and the user lands on the advertiser's page
//
// Regression guard for admoai/admoai-ios#38: the Demo used to open tracking.clicks[].url and
// lean on its 302, which double-counts once the integrator also calls fireClick.

private func creative(
    contents: String,
    template: String = "standard",
    clicks: String = """
        [{ "key": "default", "url": "https://track.admoai.com/v1/tracking?e=opaque-token" }]
        """
) throws -> Creative {
    try JSONDecoder().decode(
        Creative.self,
        from: Data(
            """
            {
                "contents": \(contents),
                "advertiser": { "name": "Ride Share Co" },
                "template": { "key": "\(template)", "style": "default" },
                "tracking": { "impressions": [], "clicks": \(clicks), "custom": null }
            }
            """.utf8))
}

private func content(_ key: String, _ value: String, type: String = "url") -> String {
    #"{ "key": "\#(key)", "value": "\#(value)", "type": "\#(type)" }"#
}

struct AdClickResolverTests {

    // Scenario: Tapping a standard ad resolves the template's destination field
    @Test
    func standardResolvesDestinationUrl() throws {
        let ad = try creative(
            contents: "[\(content("destinationUrl", "https://example.com/product"))]")

        let destination = AdClickResolver.destination(in: ad, key: AdDestinationKey.standard)

        #expect(destination == .web(URL(string: "https://example.com/product")!))
    }

    // Scenario: The destination never comes from tracking.clicks — that URL is measurement only,
    // and its absence as a destination says nothing about whether the click is recorded.
    @Test
    func trackingUrlIsNeverADestination() throws {
        let ad = try creative(contents: "[\(content("headline", "New Product Launch", type: "text"))]")

        #expect(AdClickResolver.destination(in: ad, key: AdDestinationKey.standard) == nil)
        // The tracker is present and would have "worked" via its 302 — the bug this guards. The
        // caller still fires it; there is simply nowhere to navigate.
        #expect(ad.tracking.getClickUrl(key: "default") != nil)
    }

    // Scenario: Tapping carousel slide 2 opens slide 2's destination and no other slide's
    @Test
    func carouselResolvesPerSlideDestination() throws {
        let ad = try creative(
            contents: """
                [\(content("urlSlide1", "https://example.com/one")),
                 \(content("urlSlide2", "https://example.com/two")),
                 \(content("urlSlide3", "https://example.com/three"))]
                """)

        let slide2 = AdClickResolver.destination(in: ad, key: AdDestinationKey.carouselSlide(2))

        #expect(slide2 == .web(URL(string: "https://example.com/two")!))
    }

    // Scenario: A template without a destination field (textOnly) resolves to nothing, no crash
    @Test
    func textOnlyResolvesToNil() throws {
        let ad = try creative(
            contents: "[\(content("text", "Get 20% off on your first ride.", type: "textarea"))]",
            template: "textOnly",
            clicks: "null")

        #expect(AdClickResolver.destination(in: ad, key: AdDestinationKey.standard) == nil)
        // textOnly carries no clicks tracker either, so the tap is a complete no-op.
        #expect(ad.tracking.getClickUrl(key: "default") == nil)
    }

    // Scenario: A same-app deeplink is classified for the app's router, not the system opener
    @Test
    func deeplinkIsClassifiedSeparatelyFromWeb() {
        #expect(AdClickResolver.destination(from: "demoapp://offers/42")
            == .deeplink(URL(string: "demoapp://offers/42")!))
        #expect(AdClickResolver.destination(from: "https://example.com/offer")
            == .web(URL(string: "https://example.com/offer")!))
    }

    // Scenario: Blank or malformed destinations resolve to nothing rather than a bogus open
    @Test(arguments: ["", "   ", "not a url", "https://"])
    func malformedDestinationResolvesToNil(raw: String) {
        #expect(AdClickResolver.destination(from: raw) == nil)
    }
}
