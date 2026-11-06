@testable import AdMoai
import Foundation
import OSLog
import Testing

// Playground token
//
// Feature: Talk to a Customer Playground with one optional SDKConfig parameter
//   As a publisher's tech team integrating against a playground
//   I want to set `playgroundToken` and get the playground decision endpoint
//   So that what I test is the SDK I will ship, and leaving it unset changes nothing (adhub#3280)

private let logger = Logger(subsystem: "com.admoai.sdk.tests", category: "PlaygroundTokenTests")

private func client(playgroundToken: String?) -> AdMoaiClient {
    AdMoaiClient(
        baseURL: "https://api.mock.admoai.com",
        apiVersion: "2025-11-01",
        defaultLanguage: "en",
        playgroundToken: playgroundToken,
        logger: logger
    )
}

private func sampleRequest() -> DecisionRequest {
    AdMoai(config: SDKConfig(baseUrl: "https://api.mock.admoai.com"))
        .createRequestBuilder()
        .addPlacement(key: "home", count: 2)
        .setUserId("user123")
        .build()
}

/// JSONEncoder does not order object keys, so bodies compare as JSON, not bytes.
private func sameJSON(_ lhs: Data?, _ rhs: Data) throws -> Bool {
    guard let lhs else { return false }
    let a = try JSONSerialization.jsonObject(with: lhs) as? NSDictionary
    let b = try JSONSerialization.jsonObject(with: rhs) as? NSDictionary
    return a != nil && a == b
}

/// The live request as it was before `playgroundToken` existed.
private let liveHeaders: [String: String] = [
    "Content-Type": "application/json",
    "Accept": "application/json",
    "User-Agent": "AdMoaiSDK/\(SDK_VERSION)",
    "Accept-Language": "en",
    "X-Decision-Version": "2025-11-01",
]

struct PlaygroundTokenTests {
    // Scenario: no token -> the live request, byte-identical to before
    @Test
    func testUnsetTokenBuildsTheLiveRequest() throws {
        let request = sampleRequest()
        let http = try client(playgroundToken: nil).createDecisionRequest(request)

        #expect(http.path == "/v1/decision")
        #expect(http.method == .post)
        #expect(http.headers == liveHeaders)
        #expect(try sameJSON(http.body, JSONEncoder().encode(request)))
    }

    // Scenario: empty token is treated as unset
    @Test
    func testEmptyTokenIsUnset() throws {
        let request = sampleRequest()
        let http = try client(playgroundToken: "").createDecisionRequest(request)

        #expect(http.path == "/v1/decision")
        #expect(http.headers == liveHeaders)
        #expect(SDKConfig(baseUrl: "https://x", playgroundToken: "").playgroundToken == nil)
    }

    // Scenario: token set -> playground path + X-Playground-Token, everything else unchanged
    @Test
    func testTokenRoutesToPlayground() throws {
        let request = sampleRequest()
        let http = try client(playgroundToken: "pg_abc").createDecisionRequest(request)

        var expected = liveHeaders
        expected["X-Playground-Token"] = "pg_abc"
        #expect(http.path == "/v1/playground/decision")
        #expect(http.method == .post)
        #expect(http.headers == expected)
        #expect(try sameJSON(http.body, JSONEncoder().encode(request)))
    }

    // Scenario: SDKConfig defaults to live and keeps the token it is given
    @Test
    func testSDKConfigDefault() {
        #expect(SDKConfig(baseUrl: "https://x").playgroundToken == nil)
        #expect(SDKConfig(baseUrl: "https://x", playgroundToken: "pg_abc").playgroundToken == "pg_abc")
    }

    // Scenario: printing, logging or dumping a config never shows the token
    @Test
    func testTokenIsRedactedWhenPrinted() {
        let token = "pg_secret_token_123"
        let config = SDKConfig(baseUrl: "https://x", apiVersion: "2025-11-01", playgroundToken: token)
        var dumped = ""
        dump(config, to: &dumped)
        let admoai = AdMoai(config: config)
        for text in [
            "\(config)", String(describing: config), String(reflecting: config), dumped,
            String(describing: admoai), String(reflecting: admoai),
        ] {
            #expect(!text.contains(token), "token leaked in: \(text)")
        }
        #expect("\(config)".contains("playgroundToken: <redacted>"))
        #expect("\(config)".contains(#"apiVersion: "2025-11-01""#))
        #expect("\(SDKConfig(baseUrl: "https://x"))".contains("playgroundToken: nil"))
    }

    // Scenario: a refusal reason header becomes a warning; no header, no warning
    @Test
    func testPlaygroundReasonMessage() {
        #expect(AdMoaiClient.playgroundReasonMessage(nil) == nil)
        #expect(AdMoaiClient.playgroundReasonMessage("") == nil)
        let message = AdMoaiClient.playgroundReasonMessage("revoked")
        #expect(message?.contains("revoked") == true)
        #expect(message?.contains("playgroundToken") == true)
    }
}

extension MockNetworkTests {
    struct PlaygroundTokenWireTests {
        private func send(playgroundToken: String?) async throws -> URLRequest {
            MockURLProtocol.reset(stub: .init(body: Data(#"{"success":true,"data":[]}"#.utf8)))
            let base = MockURLProtocol.config(apiVersion: "2025-11-01", defaultLanguage: "en")
            let config = SDKConfig(
                baseUrl: base.baseUrl,
                apiVersion: base.apiVersion,
                defaultLanguage: base.defaultLanguage,
                sessionConfiguration: base.sessionConfiguration,
                playgroundToken: playgroundToken
            )
            let sdk = AdMoai(config: config)
            _ = try await sdk.requestAds(sdk.createRequestBuilder().addPlacement(key: "home").build())
            return try #require(MockURLProtocol.lastRequest)
        }

        // Scenario: through the public entry point, the token reaches the wire on the same host
        @Test
        func testTokenOnTheWire() async throws {
            let sent = try await send(playgroundToken: "pg_abc")
            #expect(sent.url?.absoluteString == "https://api.mock.admoai.com/v1/playground/decision")
            #expect(sent.value(forHTTPHeaderField: "X-Playground-Token") == "pg_abc")
            #expect(sent.value(forHTTPHeaderField: "X-Decision-Version") == "2025-11-01")
        }

        // Scenario: without a token the wire request is the live one, with no playground header
        @Test
        func testNoTokenOnTheWire() async throws {
            let sent = try await send(playgroundToken: nil)
            #expect(sent.url?.absoluteString == "https://api.mock.admoai.com/v1/decision")
            #expect(sent.value(forHTTPHeaderField: "X-Playground-Token") == nil)
        }
    }
}
