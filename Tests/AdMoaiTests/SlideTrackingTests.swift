@testable import AdMoai
import Foundation
import Testing

// Carousel slide tracking — the helpers a publisher's app calls per slide.
//
// Feature: A Carousel's slides report their own views and clicks
//   As a publisher's tech team
//   I want one call per slide view and per slide click
//   So that each slide is counted once per served response and every tap is billed once
//
// The shared cross-SDK scenarios (F16-F20) run in `FixtureScenariosTests`; these tests pin the
// same rules on hand-built creatives, plus the edges the manifest does not name.

private func slideJSON(_ n: Int, views: Bool = true, clicks: Bool = true) -> String {
    let tracking = [
        views ? #""views": [{"key": "slide_view", "url": "https://t/slide\#(n)/view"}]"# : nil,
        clicks ? #""clicks": [{"key": "default", "url": "https://t/slide\#(n)/click"}]"# : nil,
    ].compactMap { $0 }.joined(separator: ",")
    return """
    {"slideId": "slide_\(n)", "position": \(n), "contents": [], "tracking": {\(tracking)}}
    """
}

/// A slide whose template added events beyond the standard `slide_view` and `default`.
private func customSlideJSON(views: [String], clicks: [String]) -> String {
    func entries(_ keys: [String], _ kind: String) -> String {
        keys.map { #"{"key": "\#($0)", "url": "https://t/custom/\#($0)"}"# }.joined(separator: ",")
    }
    return """
    {"slideId": "slide_1", "position": 1, "contents": [],
     "tracking": {"views": [\(entries(views, "view"))], "clicks": [\(entries(clicks, "click"))]}}
    """
}

private func creative(slides: [String]) throws -> Creative {
    let json = """
    {
      "contents": [{ "key": "slides", "type": "slides", "value": [\(slides.joined(separator: ","))] }],
      "advertiser": { "name": "Acme" },
      "tracking": {
        "thirdPartyTrackers": [
          {"trackerId": "any", "eventType": "click", "matchType": "any", "url": "https://agency.example/any"},
          {"trackerId": "default", "eventType": "click", "matchType": "specific",
           "eventKey": "default", "url": "https://agency.example/default"},
          {"trackerId": "other", "eventType": "click", "matchType": "specific",
           "eventKey": "save", "url": "https://agency.example/other"},
          {"trackerId": "save_offer", "eventType": "click", "matchType": "specific",
           "eventKey": "save_offer", "url": "https://agency.example/save_offer"},
          {"trackerId": "imp", "eventType": "impression", "url": "https://agency.example/imp"}
        ]
      }
    }
    """
    return try JSONDecoder().decode(Creative.self, from: Data(json.utf8))
}

extension MockNetworkTests {
    struct SlideTrackingTests {
        private func sdk() -> AdMoai {
            AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
        }

        private func sent() -> [String] {
            MockURLProtocol.capturedRequests.compactMap { $0.url?.absoluteString }
        }

        /// Waits for `count` requests, then proves nothing more arrives.
        private func expectRequests(_ count: Int) async {
            await MockURLProtocol.waitForRequests(count)
            _ = await MockURLProtocol.waitForRequests(count + 1, timeout: 0.2)
        }

        @Test func aSlideViewIsSentOncePerResponse() async throws {
            let creative = try creative(slides: [slideJSON(1)])
            let sdk = sdk()
            MockURLProtocol.reset()
            sdk.trackSlideView(creative.slides[0])
            sdk.trackSlideView(creative.slides[0])
            await expectRequests(1)
            #expect(sent() == ["https://t/slide1/view"])
        }

        @Test func bulkViewsSendEachSlideOnce() async throws {
            let creative = try creative(slides: [slideJSON(1), slideJSON(2), slideJSON(3)])
            let sdk = sdk()
            MockURLProtocol.reset()
            sdk.trackSlideViews(creative.slides)
            sdk.trackSlideViews(Array(creative.slides[1...]))
            await expectRequests(3)
            #expect(Set(sent()) == ["https://t/slide1/view", "https://t/slide2/view", "https://t/slide3/view"])
            #expect(sent().count == 3)
        }

        @Test func aClickBeforeTheViewSendsTheViewThenTheClick() async throws {
            let creative = try creative(slides: [slideJSON(1)])
            let sdk = sdk()
            MockURLProtocol.reset()
            let dispatched = DispatchLog()
            sdk.beaconSession.observeDispatches { dispatched.append($0.url?.absoluteString ?? "") }
            defer { sdk.beaconSession.observeDispatches(nil) }
            sdk.trackSlideClick(creative.slides[0], in: creative)
            await expectRequests(4)
            // Dispatch order is the contract; arrival order at the mock is the session's.
            #expect(dispatched.urls == ["https://t/slide1/view", "https://t/slide1/click"])
        }

        /// BR-SDK-05 under a race: thread A claims the view and stalls before dispatching it;
        /// thread B's click must wait for it rather than dispatch first.
        @Test func aClickRacingAnotherThreadsViewStillDispatchesTheViewFirst() throws {
            let creative = try creative(slides: [slideJSON(1)])
            let sdk = sdk()
            MockURLProtocol.reset()
            let dispatched = DispatchLog()
            let aInside = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let bDone = DispatchSemaphore(value: 0)
            let group = DispatchGroup()
            sdk.beaconSession.observeDispatches { request in
                let url = request.url?.absoluteString ?? ""
                if url == "https://t/slide1/view" {
                    aInside.signal()
                    _ = release.wait(timeout: .now() + 1)
                }
                dispatched.append(url)
            }
            defer { sdk.beaconSession.observeDispatches(nil) }
            let slide = creative.slides[0]
            group.enter()
            DispatchQueue.global().async {
                sdk.trackSlideView(slide)
                group.leave()
            }
            _ = aInside.wait(timeout: .now() + 2)
            group.enter()
            DispatchQueue.global().async {
                sdk.trackSlideClick(slide, in: creative)
                bDone.signal()
                group.leave()
            }
            _ = bDone.wait(timeout: .now() + 0.3)
            release.signal()
            _ = group.wait(timeout: .now() + 3)
            let first = dispatched.urls.filter { $0.hasPrefix("https://t/") }
            #expect(first == ["https://t/slide1/view", "https://t/slide1/click"])
        }

        @Test func aTapOnASlideWithoutAClickTrackerStillCountsItsView() async throws {
            let creative = try creative(slides: [slideJSON(1, clicks: false)])
            let sdk = sdk()
            MockURLProtocol.reset()
            sdk.trackSlideClick(creative.slides[0], in: creative)
            sdk.trackSlideClick(creative.slides[0], in: creative)
            await expectRequests(1)
            #expect(sent() == ["https://t/slide1/view"], "the tap proves the slide was seen; no click, no fan-out")
        }

        @Test func aClickAfterTheViewSendsOnlyTheClick() async throws {
            let creative = try creative(slides: [slideJSON(1)])
            let sdk = sdk()
            MockURLProtocol.reset()
            sdk.trackSlideView(creative.slides[0])
            await expectRequests(1)
            MockURLProtocol.reset()
            sdk.trackSlideView(creative.slides[0])
            sdk.trackSlideClick(creative.slides[0], in: creative)
            await expectRequests(3)
            #expect(sent().filter { $0.hasPrefix("https://t/") } == ["https://t/slide1/click"])
        }

        @Test func everyClickFansOutTheApplicableThirdPartyTrackersOnce() async throws {
            let creative = try creative(slides: [slideJSON(1)])
            let sdk = sdk()
            MockURLProtocol.reset()
            sdk.trackSlideClick(creative.slides[0], in: creative)
            sdk.trackSlideClick(creative.slides[0], in: creative)
            await expectRequests(7)
            let thirdParty = sent().filter { $0.hasPrefix("https://agency.example/") }
            #expect(thirdParty.sorted() == [
                "https://agency.example/any", "https://agency.example/any",
                "https://agency.example/default", "https://agency.example/default",
            ])
        }

        @Test func aSlideViewNeverFansOutThirdPartyTrackers() async throws {
            let creative = try creative(slides: [slideJSON(1), slideJSON(2)])
            let sdk = sdk()
            MockURLProtocol.reset()
            sdk.trackSlideViews(creative.slides)
            await expectRequests(2)
            #expect(sent().allSatisfy { $0.hasPrefix("https://t/") })
        }

        @Test func aSlideWithoutTrackingIsANoOp() async throws {
            let creative = try creative(slides: [
                #"{"slideId": "slide_1", "position": 1, "contents": []}"#,
                slideJSON(2, views: false, clicks: false),
            ])
            let sdk = sdk()
            MockURLProtocol.reset()
            sdk.trackSlideViews(creative.slides)
            sdk.trackSlideClick(creative.slides[0], in: creative)
            sdk.trackSlideClick(creative.slides[1], in: creative)
            await expectRequests(0)
            #expect(sent().isEmpty, "no tracker at all: nothing to send, and no fan-out")
        }

        @Test func slideAndPinViewsKeepIndependentLedgers() async throws {
            let creative = try creative(slides: [slideJSON(1)])
            let sdk = sdk()
            #expect(sdk.slideViewLedger !== sdk.pinViewLedger)
            #expect(sdk.slideViewLedger.claim("https://t/shared"))
            #expect(sdk.pinViewLedger.claim("https://t/shared"), "claiming as a slide does not claim as a pin")
            MockURLProtocol.reset()
            sdk.trackSlideView(creative.slides[0])
            await expectRequests(1)
            #expect(sent() == ["https://t/slide1/view"])
        }

        /// The Carousel has no creative-level click: `fireClick` records nothing for it, and
        /// the third-party trackers do not fan out for a click the creative cannot record.
        @Test func fireClickOnACreativeWithoutAClickSendsNothing() async throws {
            let creative = try creative(slides: [slideJSON(1)])
            MockURLProtocol.reset()
            sdk().fireClick(tracking: creative.tracking)
            await expectRequests(0)
            #expect(sent().isEmpty)
        }

        @Test func aViewSendsOnlyTheSlideViewEntry() async throws {
            let slide = customSlideJSON(views: ["slide_shown_custom", "slide_view"], clicks: ["default"])
            let creative = try creative(slides: [slide])
            let sdk = sdk()
            MockURLProtocol.reset()
            sdk.trackSlideView(creative.slides[0])
            await expectRequests(1)
            #expect(sent() == ["https://t/custom/slide_view"], "other view-type entries are never sent by the helper")
        }

        @Test func aClickSendsTheViewThenOnlyTheDefaultClickAndItsTrackers() async throws {
            let slide = customSlideJSON(
                views: ["slide_view", "slide_shown_custom"], clicks: ["save_offer", "default"]
            )
            let creative = try creative(slides: [slide])
            let sdk = sdk()
            MockURLProtocol.reset()
            let dispatched = DispatchLog()
            sdk.beaconSession.observeDispatches { dispatched.append($0.url?.absoluteString ?? "") }
            defer { sdk.beaconSession.observeDispatches(nil) }
            sdk.trackSlideClick(creative.slides[0], in: creative)
            await expectRequests(4)
            #expect(dispatched.urls.filter { $0.hasPrefix("https://t/") }
                == ["https://t/custom/slide_view", "https://t/custom/default"])
            let thirdParty = sent().filter { $0.hasPrefix("https://agency.example/") }
            #expect(thirdParty.sorted() == ["https://agency.example/any", "https://agency.example/default"])
        }

        @Test func aSlideWhoseOnlyClickIsCustomCountsItsViewAndNothingElse() async throws {
            let slide = customSlideJSON(views: ["slide_view"], clicks: ["save_offer"])
            let creative = try creative(slides: [slide])
            let sdk = sdk()
            MockURLProtocol.reset()
            sdk.trackSlideClick(creative.slides[0], in: creative)
            await expectRequests(1)
            #expect(sent() == ["https://t/custom/slide_view"], "no default click: no click, no fan-out")
        }
    }
}
