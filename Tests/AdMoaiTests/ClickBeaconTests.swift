import Foundation
import Testing

@testable import AdMoai

// Feature: A click beacon records the click and nothing else
//   As a publisher's app
//   I want fireClick to send the click beacon exactly once
//   So that the click is recorded, and opening the destination stays my app's job
//
// `/v1/tracking` answers a click with `302 Location: <destination>` so a browser can record
// and land in one hop. An SDK beacon is not navigation: following the redirect downloaded the
// advertiser's whole landing page in the background on every click.

private func decodeTracking(_ json: String) throws -> Tracking {
    try JSONDecoder().decode(Tracking.self, from: json.data(using: .utf8)!)
}

// Nested under `MockNetworkTests` so it can never run concurrently with another
// MockURLProtocol-driven suite — see MockNetworkTests for why that matters.
extension MockNetworkTests {
    @Suite
    struct ClickBeaconTests {

        private let clickURL = "https://api.mock.admoai.com/v1/tracking?e=CLICK"

        private func clicks() throws -> Tracking {
            try decodeTracking("""
                { "clicks": [{"key": "default", "url": "\(clickURL)"}] }
                """)
        }

        private func makeSDK() -> AdMoai {
            AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
        }

        // Scenario: the tracking endpoint answers the click with a redirect
        @Test
        func testRedirectedClickIsSentOnceAndLocationNeverRequested() async throws {
            MockURLProtocol.reset(
                stub: MockURLProtocol.Stub(
                    statusCode: 302,
                    body: Data(),
                    headers: ["Location": "https://shop.advertiser.example/landing"]
                ))
            makeSDK().fireClick(tracking: try clicks())

            #expect(await MockURLProtocol.waitForRequests(1))
            // Give a follow-up (which would be the bug) time to appear, then assert it did not.
            #expect(!(await MockURLProtocol.waitForRequests(2, timeout: 0.5)))
            #expect(MockURLProtocol.capturedRequests.map { $0.url?.absoluteString } == [clickURL])
        }

        // Scenario: the tracking endpoint answers the click with a 2xx
        @Test
        func testAcceptedClickIsSentOnce() async throws {
            MockURLProtocol.reset(
                stub: MockURLProtocol.Stub(statusCode: 202, body: Data(), headers: [:]))
            makeSDK().fireClick(tracking: try clicks())

            #expect(await MockURLProtocol.waitForRequests(1))
            #expect(!(await MockURLProtocol.waitForRequests(2, timeout: 0.5)))
            #expect(MockURLProtocol.capturedRequests.map { $0.url?.absoluteString } == [clickURL])
        }

        // Scenario: the click key is not in the creative's tracking
        @Test
        func testMissingClickKeySendsNothing() async throws {
            MockURLProtocol.reset()
            makeSDK().fireClick(tracking: try clicks(), key: "cta_tap")

            _ = await MockURLProtocol.waitForRequests(1, timeout: 0.4)
            #expect(MockURLProtocol.capturedRequests.isEmpty)
        }

        // Scenario: copies of the SDK share one beacon session
        @Test
        func testCopiedSDKStillSendsTheBeaconAfterTheOriginalIsGone() async throws {
            MockURLProtocol.reset(
                stub: MockURLProtocol.Stub(
                    statusCode: 302,
                    body: Data(),
                    headers: ["Location": "https://shop.advertiser.example/landing"]
                ))
            var copy: AdMoai?
            do {
                let original = makeSDK()
                copy = original
            }
            copy?.fireClick(tracking: try clicks())

            #expect(await MockURLProtocol.waitForRequests(1))
            #expect(!(await MockURLProtocol.waitForRequests(2, timeout: 0.5)))
        }
    }
}
