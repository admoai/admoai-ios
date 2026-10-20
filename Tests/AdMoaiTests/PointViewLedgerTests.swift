import Foundation
import Testing

@testable import AdMoai

/// Pin views are reported once per decision response — the scenarios of
/// `Sources/AdMoai/PointViewLedger.feature`, one test per scenario, named after it.
///
/// There is no Gherkin runner in this package, so `everyScenarioHasATest` holds the binding
/// instead: a scenario added to the feature without a test here, or a test whose scenario was
/// renamed away, fails the build.

/// Decodes `count` matched points as one decision response `response` would carry them. The
/// view URL embeds the response the way the engine's per-event token does: the same pin in
/// two responses has two different view URLs.
private func points(_ range: Range<Int>, response: String) throws -> [MatchedPoint] {
    let entries = range.map { i in
        """
        { "id": "p\(i)", "name": "P\(i)", "latitude": 1, "longitude": 1, "distance": \(i),
          "tracking": {
            "views":  [{ "key": "default", "url": "https://t/\(response)/view/p\(i)" }],
            "taps":   [{ "key": "default", "url": "https://t/\(response)/tap/p\(i)" }],
            "clicks": [{ "key": "default", "url": "https://t/\(response)/click/p\(i)" }]
          } }
        """
    }.joined(separator: ",")
    let json = """
        {
          "contents": [{ "key": "matched_points", "type": "matched_points", "value": [\(entries)] }],
          "advertiser": { "name": "Cabify" },
          "tracking": {}
        }
        """
    return try JSONDecoder().decode(Creative.self, from: Data(json.utf8)).matchedPoints
}

private func viewURLs(_ range: Range<Int>, response: String) -> Set<String> {
    Set(range.map { "https://t/\(response)/view/p\($0)" })
}

extension MockNetworkTests {
    @Suite
    struct PointViewLedgerTests {

        private func sdk() -> AdMoai {
            AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01"))
        }

        private func firedURLs() -> [String] {
            MockURLProtocol.capturedRequests.compactMap { $0.url?.absoluteString }
        }

        /// Fire-and-forget gives nothing to await, so "nothing was sent" can only be asserted
        /// after giving a stray request time to arrive.
        private func settle() async throws {
            try await Task.sleep(nanoseconds: 300_000_000)
        }

        static let scenarios: Set<String> = [
            "the first render fires every pin's view URLs",
            "a re-render of the same response fires nothing",
            "a re-render with new pins fires only the new ones",
            "a new decision response starts fresh",
            "memory is bounded",
            "single-point tracking follows the same rule",
            "taps and clicks are not deduplicated by this mechanism",
        ]

        @Test func everyScenarioHasATest() throws {
            let feature = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("../../Sources/AdMoai/PointViewLedger.feature")
            let text = try String(contentsOf: feature, encoding: .utf8)
            let titles = text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("Scenario:") }
                .map { $0.dropFirst("Scenario:".count).trimmingCharacters(in: .whitespaces) }
            #expect(Set(titles) == Self.scenarios)
        }

        @Test("the first render fires every pin's view URLs")
        func firstRenderFiresEveryView() async throws {
            let r = try points(0..<50, response: "r")

            MockURLProtocol.reset()
            sdk().trackPointViews(r)
            await MockURLProtocol.waitForRequests(50)
            try await settle()

            #expect(firedURLs().count == 50, "exactly one GET per view URL")
            #expect(Set(firedURLs()) == viewURLs(0..<50, response: "r"))
        }

        @Test("a re-render of the same response fires nothing")
        func reRenderFiresNothing() async throws {
            let r = try points(0..<50, response: "r")
            let sdk = self.sdk()
            MockURLProtocol.reset()
            sdk.trackPointViews(r)
            await MockURLProtocol.waitForRequests(50)
            try await settle()

            MockURLProtocol.reset()
            sdk.trackPointViews(r)
            try await settle()

            #expect(firedURLs().isEmpty)
        }

        /// A copy of the SDK value is the same SDK: the record lives in a reference every copy
        /// shares, the way the Journey session does.
        @Test func aCopyOfTheSDKSharesTheRecord() async throws {
            let r = try points(0..<3, response: "r")
            let original = sdk()
            let copy = original
            MockURLProtocol.reset()
            original.trackPointViews(r)
            await MockURLProtocol.waitForRequests(3)
            try await settle()

            MockURLProtocol.reset()
            copy.trackPointViews(r)
            try await settle()

            #expect(firedURLs().isEmpty)
        }

        @Test("a re-render with new pins fires only the new ones")
        func reRenderWithNewPinsFiresOnlyThoseNew() async throws {
            // A..J is 0..<10, F..T is 5..<20, K..T is 10..<20.
            let r = try points(0..<20, response: "r")
            let sdk = self.sdk()
            MockURLProtocol.reset()
            sdk.trackPointViews(Array(r[0..<10]))
            await MockURLProtocol.waitForRequests(10)
            try await settle()

            MockURLProtocol.reset()
            sdk.trackPointViews(Array(r[5..<20]))
            await MockURLProtocol.waitForRequests(10)
            try await settle()

            #expect(firedURLs().count == 10)
            #expect(Set(firedURLs()) == viewURLs(10..<20, response: "r"))
        }

        @Test("a new decision response starts fresh")
        func newResponseStartsFresh() async throws {
            let r1 = try points(0..<1, response: "r1")
            let r2 = try points(0..<1, response: "r2")
            #expect(r1[0].id == r2[0].id, "the same location in both responses")
            let sdk = self.sdk()
            MockURLProtocol.reset()
            sdk.trackPointViews(r1)
            await MockURLProtocol.waitForRequests(1)
            try await settle()

            MockURLProtocol.reset()
            sdk.trackPointViews(r2)
            await MockURLProtocol.waitForRequests(1)
            try await settle()

            #expect(firedURLs() == ["https://t/r2/view/p0"])
        }

        @Test("memory is bounded")
        func memoryIsBounded() throws {
            let ledger = PointViewLedger()
            #expect(ledger.capacity == 500)

            for response in 0..<100 {
                for pin in 0..<50 {
                    _ = ledger.claim("https://t/r\(response)/view/p\(pin)")
                }
            }

            #expect(ledger.count == 500, "the ten most recent full responses")
            #expect(!ledger.claim("https://t/r99/view/p0"), "the newest response is remembered")
            #expect(!ledger.claim("https://t/r90/view/p49"), "so is the tenth newest")
            #expect(ledger.claim("https://t/r89/view/p49"), "the eleventh is forgotten and fires")
            #expect(ledger.count == 500)
        }

        /// A pin re-rendered keeps its place: the next eviction takes the pin nobody has shown
        /// for longest, not the one the user is looking at.
        @Test func aRenderedPinIsNotTheNextEvicted() {
            let ledger = PointViewLedger(capacity: 2)
            _ = ledger.claim("a")
            _ = ledger.claim("b")
            _ = ledger.claim("a")
            _ = ledger.claim("c")

            #expect(!ledger.claim("a"))
            #expect(ledger.claim("b"))
        }

        /// Map callbacks arrive on any thread. Two renders racing over the same screenful must
        /// still send each view once.
        @Test func concurrentRendersFireEachViewOnce() async throws {
            let r = try points(0..<50, response: "r")
            let sdk = self.sdk()
            MockURLProtocol.reset()

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<8 {
                    group.addTask { sdk.trackPointViews(r) }
                }
            }
            await MockURLProtocol.waitForRequests(50)
            try await settle()

            #expect(firedURLs().count == 50)
            #expect(Set(firedURLs()) == viewURLs(0..<50, response: "r"))
        }

        @Test("single-point tracking follows the same rule")
        func singlePointFollowsTheSameRule() async throws {
            let point = try #require(try points(0..<1, response: "r").first)
            let sdk = self.sdk()
            MockURLProtocol.reset()
            sdk.trackPointView(point)
            await MockURLProtocol.waitForRequests(1)
            try await settle()

            MockURLProtocol.reset()
            sdk.trackPointView(point)
            sdk.trackPointViews([point])
            try await settle()

            #expect(firedURLs().isEmpty)
        }

        @Test("taps and clicks are not deduplicated by this mechanism")
        func tapsAndClicksAreNotDeduplicated() async throws {
            let point = try #require(try points(0..<1, response: "r").first)
            let sdk = self.sdk()
            MockURLProtocol.reset()
            sdk.trackPointView(point)
            await MockURLProtocol.waitForRequests(1)
            try await settle()

            MockURLProtocol.reset()
            sdk.trackPointTap(point)
            sdk.trackPointTap(point)
            sdk.trackPointClick(point)
            sdk.trackPointClick(point)
            await MockURLProtocol.waitForRequests(4)
            try await settle()

            #expect(firedURLs().filter { $0 == "https://t/r/tap/p0" }.count == 2)
            #expect(firedURLs().filter { $0 == "https://t/r/click/p0" }.count == 2)
            #expect(firedURLs().count == 4)
        }
    }
}
