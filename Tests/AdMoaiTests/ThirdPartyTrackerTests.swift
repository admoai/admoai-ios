import Foundation
import Testing

@testable import AdMoai

// Third-party Event Trackers — tolerant model + credential-isolated fan-out (mission E06)
//
// Feature: Fan out agency tracking URLs exactly as configured, and never anything else
//   As an agency buying through Admoai
//   I want one GET to my ad server per matching tracker per reported event
//   So that my independent counts reconcile against Admoai reporting
//
// Spec: adhub features/third-party-trackers/specs/E06-sdk.md — the parity matrix
// (§A model, §B impression fan-out, §C click fan-out, §D dedupe+limit, §E dispatcher
// isolation, §F sanitized logging). Test names reference matrix numbers.

private func decodeTracking(_ json: String) throws -> Tracking {
    try JSONDecoder().decode(Tracking.self, from: json.data(using: .utf8)!)
}

private func tracker(
    id: String = "tpt_01ARZ3NDEKTSV4RRFFQ69G5FAV",
    eventType: String = "impression",
    matchType: String? = nil,
    eventKey: String? = nil,
    url: String = "https://agency.example/imp"
) -> ThirdPartyTracker {
    ThirdPartyTracker(
        trackerId: id, eventType: eventType, matchType: matchType, eventKey: eventKey, url: url)
}

// MARK: - §A Model / decoding (pure, parallel-safe)

@Suite
struct ThirdPartyTrackerDecodingTests {

    // A1: absent field → nil; helpers unaffected
    @Test
    func testAbsentFieldDecodesToNil() throws {
        let tracking = try decodeTracking(
            #"{"impressions": [{"key": "default", "url": "https://t/imp"}]}"#)
        #expect(tracking.thirdPartyTrackers == nil)
        #expect(tracking.getImpressionUrl(key: "default") == "https://t/imp")
    }

    // A2: null field → nil
    @Test
    func testNullFieldDecodesToNil() throws {
        let tracking = try decodeTracking(#"{"thirdPartyTrackers": null}"#)
        #expect(tracking.thirdPartyTrackers == nil)
    }

    // A3 + A12: impression entry decodes; url byte-identical (query order, case, macros)
    @Test
    func testImpressionEntryDecodesVerbatim() throws {
        let rawURL = "https://Agency.example/Track?b=2&a=1&cb=%%CACHEBUSTER%%&x=a%20b"
        let tracking = try decodeTracking("""
            {"thirdPartyTrackers": [
                {"trackerId": "tpt_01ARZ3NDEKTSV4RRFFQ69G5FAV", "eventType": "impression",
                 "url": "\(rawURL)"}
            ]}
            """)
        let entry = try #require(tracking.thirdPartyTrackers?.first)
        #expect(entry.trackerId == "tpt_01ARZ3NDEKTSV4RRFFQ69G5FAV")
        #expect(entry.eventType == "impression")
        #expect(entry.matchType == nil)
        #expect(entry.eventKey == nil)
        #expect(entry.url == rawURL)
    }

    // A4: any-click entry
    @Test
    func testAnyClickEntryDecodes() throws {
        let tracking = try decodeTracking("""
            {"thirdPartyTrackers": [
                {"trackerId": "tpt_A", "eventType": "click", "matchType": "any",
                 "url": "https://agency.example/click"}
            ]}
            """)
        let entry = try #require(tracking.thirdPartyTrackers?.first)
        #expect(entry.matchType == "any")
        #expect(entry.eventKey == nil)
    }

    // A5: specific-click entry
    @Test
    func testSpecificClickEntryDecodes() throws {
        let tracking = try decodeTracking("""
            {"thirdPartyTrackers": [
                {"trackerId": "tpt_B", "eventType": "click", "matchType": "specific",
                 "eventKey": "cta_tap", "url": "https://agency.example/cta"}
            ]}
            """)
        let entry = try #require(tracking.thirdPartyTrackers?.first)
        #expect(entry.matchType == "specific")
        #expect(entry.eventKey == "cta_tap")
    }

    // A6: unknown extra fields are ignored (forward compatibility)
    @Test
    func testUnknownExtraFieldsAreIgnored() throws {
        let tracking = try decodeTracking("""
            {"thirdPartyTrackers": [
                {"trackerId": "tpt_C", "eventType": "impression",
                 "url": "https://agency.example/imp", "futureField": {"nested": true}}
            ]}
            """)
        #expect(tracking.thirdPartyTrackers?.count == 1)
    }

    // A7 + A11: an entry missing a required field is dropped; siblings and the
    // response survive
    @Test
    func testStructurallyMalformedEntryIsDroppedSiblingsSurvive() throws {
        let tracking = try decodeTracking("""
            {"thirdPartyTrackers": [
                {"trackerId": "tpt_NO_URL", "eventType": "impression"},
                "not-an-object",
                {"trackerId": "tpt_OK", "eventType": "impression",
                 "url": "https://agency.example/imp"}
            ]}
            """)
        let entries = try #require(tracking.thirdPartyTrackers)
        #expect(entries.count == 1)
        #expect(entries.first?.trackerId == "tpt_OK")
    }

    // A11: a malformed thirdPartyTrackers block never fails the whole Tracking decode
    @Test
    func testMalformedBlockNeverFailsTrackingDecode() throws {
        let tracking = try decodeTracking(
            #"{"thirdPartyTrackers": "garbage", "clicks": [{"key": "default", "url": "https://t/c"}]}"#
        )
        #expect(tracking.thirdPartyTrackers == nil)
        #expect(tracking.getClickUrl(key: "default") == "https://t/c")
    }
}

// MARK: - §A semantic validation + §F sanitized reasons (pure, parallel-safe)

@Suite
struct ThirdPartyTrackerValidationTests {

    // A8: non-HTTPS urls are rejected
    @Test(arguments: [
        "http://agency.example/imp", "ftp://agency.example/imp",
        "javascript:alert(1)", "data:text/html,x", "agency.example/imp", "",
    ])
    func testNonHTTPSURLIsRejected(url: String) {
        let reason = ThirdPartyTrackerDispatcher.rejectionReason(tracker(url: url))
        #expect(reason != nil)
    }

    // A9: unknown eventType / matchType are rejected
    @Test
    func testUnknownEventTypeAndMatchTypeAreRejected() {
        #expect(
            ThirdPartyTrackerDispatcher.rejectionReason(tracker(eventType: "conversion")) != nil)
        #expect(
            ThirdPartyTrackerDispatcher.rejectionReason(
                tracker(eventType: "click", matchType: "fuzzy")) != nil)
        // A click without a matchType is not a shape the engine serves.
        #expect(
            ThirdPartyTrackerDispatcher.rejectionReason(
                tracker(eventType: "click", matchType: nil)) != nil)
    }

    // A10: specific click without eventKey is rejected
    @Test
    func testSpecificClickWithoutEventKeyIsRejected() {
        #expect(
            ThirdPartyTrackerDispatcher.rejectionReason(
                tracker(eventType: "click", matchType: "specific", eventKey: nil)) != nil)
        #expect(
            ThirdPartyTrackerDispatcher.rejectionReason(
                tracker(eventType: "click", matchType: "specific", eventKey: "")) != nil)
    }

    // Valid shapes pass
    @Test
    func testValidShapesPass() {
        #expect(ThirdPartyTrackerDispatcher.rejectionReason(tracker()) == nil)
        #expect(
            ThirdPartyTrackerDispatcher.rejectionReason(
                tracker(eventType: "click", matchType: "any", url: "https://a.example/c")) == nil)
        #expect(
            ThirdPartyTrackerDispatcher.rejectionReason(
                tracker(eventType: "click", matchType: "specific", eventKey: "cta_tap",
                    url: "https://a.example/s")) == nil)
    }

    // A12 + E30: a URL the parser cannot round-trip verbatim (raw macro) is rejected —
    // modern Foundation would re-encode %%CACHEBUSTER%% (and double-encode adjacent valid
    // escapes), iOS 14–16 would fail to parse it; both outcomes corrupt agency counts.
    @Test
    func testNonRoundTrippingURLIsRejected() {
        #expect(
            ThirdPartyTrackerDispatcher.rejectionReason(
                tracker(url: "https://agency.example/imp?cb=%%CACHEBUSTER%%")) != nil)
        // A clean RFC-3986 URL round-trips and passes.
        #expect(
            ThirdPartyTrackerDispatcher.rejectionReason(
                tracker(url: "https://agency.example/imp?b=2&a=1&ord=12345")) == nil)
    }

    // F35 (static half): rejection reasons are stable strings that never embed the URL,
    // so no logging path can leak it through them.
    @Test
    func testRejectionReasonsNeverContainTheURL() {
        let poisonURL = "http://leak.example/secret?campaign=X"
        let invalid = [
            tracker(url: poisonURL),
            tracker(eventType: "conversion", url: poisonURL),
            tracker(eventType: "click", matchType: "fuzzy", url: poisonURL),
            tracker(eventType: "click", matchType: "specific", eventKey: nil, url: poisonURL),
        ]
        for entry in invalid {
            let reason = ThirdPartyTrackerDispatcher.rejectionReason(entry)
            #expect(reason?.contains("leak.example") == false)
            #expect(reason?.contains("secret") == false)
        }
    }
}

// MARK: - Matching (pure, parallel-safe)

@Suite
struct ThirdPartyTrackerMatchingTests {

    // B14 / C22 (matching half): impressions never match clicks and vice versa
    @Test
    func testEventTypesNeverCrossMatch() {
        let imp = tracker()
        let anyClick = tracker(eventType: "click", matchType: "any", url: "https://a.example/c")
        #expect(ThirdPartyTrackerDispatcher.matches(imp, event: .impression))
        #expect(!ThirdPartyTrackerDispatcher.matches(imp, event: .click(key: "default")))
        #expect(!ThirdPartyTrackerDispatcher.matches(anyClick, event: .impression))
        #expect(ThirdPartyTrackerDispatcher.matches(anyClick, event: .click(key: "default")))
    }

    // C18–C20: any matches every key; specific matches only its key
    @Test
    func testClickMatchingByKey() {
        let anyClick = tracker(eventType: "click", matchType: "any", url: "https://a.example/c")
        let specific = tracker(
            eventType: "click", matchType: "specific", eventKey: "cta_tap",
            url: "https://a.example/s")
        #expect(ThirdPartyTrackerDispatcher.matches(anyClick, event: .click(key: "cta_tap")))
        #expect(ThirdPartyTrackerDispatcher.matches(anyClick, event: .click(key: "other")))
        #expect(ThirdPartyTrackerDispatcher.matches(specific, event: .click(key: "cta_tap")))
        #expect(!ThirdPartyTrackerDispatcher.matches(specific, event: .click(key: "other")))
    }
}

// MARK: - §B/§C/§D/§E fan-out through the network (serialized MockURLProtocol suite)

extension MockNetworkTests {
    @Suite
    struct ThirdPartyTrackerFanOutTests {

        /// Canonical impression+click on "default"/"cta_tap" plus the given trackers.
        private func trackingJSON(trackers: String) throws -> Tracking {
            try decodeTracking("""
                {
                    "impressions": [{"key": "default", "url": "https://api.mock.admoai.com/v1/t/imp"}],
                    "clicks": [
                        {"key": "default", "url": "https://api.mock.admoai.com/v1/t/click"},
                        {"key": "cta_tap", "url": "https://api.mock.admoai.com/v1/t/click-cta"}
                    ],
                    "thirdPartyTrackers": \(trackers)
                }
                """)
        }

        private func makeSDK() -> AdMoai {
            AdMoai(config: MockURLProtocol.config(apiVersion: "2025-11-01", defaultLanguage: "en"))
        }

        private func requests(to host: String) -> [URLRequest] {
            MockURLProtocol.capturedRequests.filter { $0.url?.host == host }
        }

        // B13 + E30: canonical + one tracker GET, exact URL, method GET
        @Test
        func testImpressionFiresCanonicalPlusTrackerVerbatim() async throws {
            MockURLProtocol.reset()
            let sdk = makeSDK()
            let rawURL = "https://agency.example/imp?b=2&a=1&ord=12345"
            let tracking = try trackingJSON(
                trackers: """
                    [{"trackerId": "tpt_1", "eventType": "impression", "url": "\(rawURL)"}]
                    """)
            sdk.fireImpression(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(2))
            let trackerReqs = requests(to: "agency.example")
            #expect(trackerReqs.count == 1)
            #expect(trackerReqs.first?.httpMethod == "GET")
            #expect(trackerReqs.first?.url?.absoluteString == rawURL)
            #expect(requests(to: "api.mock.admoai.com").count == 1)
        }

        // B14 + C22: only impression trackers fire on fireImpression
        @Test
        func testImpressionFiresOnlyImpressionTrackers() async throws {
            MockURLProtocol.reset()
            let sdk = makeSDK()
            let tracking = try trackingJSON(
                trackers: """
                    [{"trackerId": "tpt_1", "eventType": "impression", "url": "https://agency.example/i1"},
                     {"trackerId": "tpt_2", "eventType": "impression", "url": "https://agency.example/i2"},
                     {"trackerId": "tpt_3", "eventType": "click", "matchType": "any", "url": "https://agency.example/c1"}]
                    """)
            sdk.fireImpression(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(3))
            let urls = requests(to: "agency.example").compactMap { $0.url?.absoluteString }
            #expect(urls.sorted() == ["https://agency.example/i1", "https://agency.example/i2"])
        }

        // B15: no cross-invocation dedupe — two invocations fire the tracker twice
        @Test
        func testTwoInvocationsFireTwice() async throws {
            MockURLProtocol.reset()
            let sdk = makeSDK()
            let tracking = try trackingJSON(
                trackers: """
                    [{"trackerId": "tpt_1", "eventType": "impression", "url": "https://agency.example/imp"}]
                    """)
            sdk.fireImpression(tracking: tracking)
            sdk.fireImpression(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(4))
            #expect(requests(to: "agency.example").count == 2)
        }

        // B16 + C21: a key without a canonical URL fires nothing at all
        @Test
        func testMissingCanonicalKeyFiresNothing() async throws {
            MockURLProtocol.reset()
            let sdk = makeSDK()
            let tracking = try trackingJSON(
                trackers: """
                    [{"trackerId": "tpt_1", "eventType": "impression", "url": "https://agency.example/imp"},
                     {"trackerId": "tpt_2", "eventType": "click", "matchType": "any", "url": "https://agency.example/c"}]
                    """)
            sdk.fireImpression(tracking: tracking, key: "nonexistent")
            sdk.fireClick(tracking: tracking, key: "nonexistent")
            #expect(!(await MockURLProtocol.waitForRequests(1, timeout: 0.5)))
            #expect(MockURLProtocol.capturedRequests.isEmpty)
        }

        // B17: no trackers → canonical only, zero dispatcher activity
        @Test
        func testNoTrackersMeansCanonicalOnly() async throws {
            MockURLProtocol.reset()
            let sdk = makeSDK()
            let tracking = try decodeTracking(
                #"{"impressions": [{"key": "default", "url": "https://api.mock.admoai.com/v1/t/imp"}]}"#
            )
            sdk.fireImpression(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(1))
            #expect(!(await MockURLProtocol.waitForRequests(2, timeout: 0.5)))
        }

        // C18–C20: any fires on every valid key; specific only on its key
        @Test
        func testClickFanOutMatching() async throws {
            MockURLProtocol.reset()
            let sdk = makeSDK()
            let tracking = try trackingJSON(
                trackers: """
                    [{"trackerId": "tpt_any", "eventType": "click", "matchType": "any", "url": "https://agency.example/any"},
                     {"trackerId": "tpt_spec", "eventType": "click", "matchType": "specific", "eventKey": "cta_tap", "url": "https://agency.example/spec"}]
                    """)
            // "default" click: any fires, specific does not.
            sdk.fireClick(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(2))
            var urls = requests(to: "agency.example").compactMap { $0.url?.absoluteString }
            #expect(urls == ["https://agency.example/any"])

            // "cta_tap" click: both fire.
            MockURLProtocol.reset()
            sdk.fireClick(tracking: tracking, key: "cta_tap")
            #expect(await MockURLProtocol.waitForRequests(3))
            urls = requests(to: "agency.example").compactMap { $0.url?.absoluteString }
            #expect(
                urls.sorted() == ["https://agency.example/any", "https://agency.example/spec"])
        }

        // D23: byte-identical URLs dedupe within one invocation
        @Test
        func testExactURLDedupeWithinInvocation() async throws {
            MockURLProtocol.reset()
            let sdk = makeSDK()
            let tracking = try trackingJSON(
                trackers: """
                    [{"trackerId": "tpt_1", "eventType": "impression", "url": "https://agency.example/same"},
                     {"trackerId": "tpt_2", "eventType": "impression", "url": "https://agency.example/same"},
                     {"trackerId": "tpt_3", "eventType": "impression", "url": "https://agency.example/same?x=1"}]
                    """)
            sdk.fireImpression(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(3))
            #expect(!(await MockURLProtocol.waitForRequests(4, timeout: 0.5)))
            let urls = requests(to: "agency.example").compactMap { $0.url?.absoluteString }
            #expect(urls.sorted() == ["https://agency.example/same", "https://agency.example/same?x=1"])
        }

        // D24: the same URL on an impression and a click tracker fires on each event
        @Test
        func testSameURLAcrossEventTypesFiresPerEvent() async throws {
            MockURLProtocol.reset()
            let sdk = makeSDK()
            let tracking = try trackingJSON(
                trackers: """
                    [{"trackerId": "tpt_1", "eventType": "impression", "url": "https://agency.example/shared"},
                     {"trackerId": "tpt_2", "eventType": "click", "matchType": "any", "url": "https://agency.example/shared"}]
                    """)
            sdk.fireImpression(tracking: tracking)
            sdk.fireClick(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(4))
            #expect(requests(to: "agency.example").count == 2)
        }

        // D25 + D26 + D27: exactly 10 fire; 11 valid fire nothing; invalid entries do
        // not count toward the limit
        @Test
        func testLimitCountsValidEntriesOnly() async throws {
            func entries(_ count: Int, invalidExtra: Int = 0) -> String {
                var list: [String] = (0..<count).map {
                    #"{"trackerId": "tpt_\#($0)", "eventType": "impression", "url": "https://agency.example/t\#($0)"}"#
                }
                list += (0..<invalidExtra).map { _ in
                    #"{"trackerId": "tpt_bad", "eventType": "impression", "url": "http://insecure.example/x"}"#
                }
                return "[\(list.joined(separator: ",")) ]"
            }

            // 10 valid → all fire.
            MockURLProtocol.reset()
            let sdk = makeSDK()
            var tracking = try trackingJSON(trackers: entries(10))
            sdk.fireImpression(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(11))
            #expect(requests(to: "agency.example").count == 10)

            // 11 valid → none fire (canonical still does).
            MockURLProtocol.reset()
            tracking = try trackingJSON(trackers: entries(11))
            sdk.fireImpression(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(1))
            #expect(!(await MockURLProtocol.waitForRequests(2, timeout: 0.5)))
            #expect(requests(to: "agency.example").isEmpty)

            // 9 valid + 2 invalid (11 raw) → the 9 fire.
            MockURLProtocol.reset()
            tracking = try trackingJSON(trackers: entries(9, invalidExtra: 2))
            sdk.fireImpression(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(10))
            #expect(requests(to: "agency.example").count == 9)
            #expect(requests(to: "insecure.example").isEmpty)
        }

        // E28 + E32: tracker requests carry no Admoai identity and bypass the cache;
        // the canonical request keeps its identity. The SDK config carries an explicit
        // AdMoaiSDK User-Agent so the assertion can actually detect configuration
        // inheritance (a bare mock config would pass vacuously).
        @Test
        func testTrackerRequestsCarryNoAdmoaiIdentity() async throws {
            MockURLProtocol.reset()
            let config = MockURLProtocol.config(apiVersion: "2025-11-01", defaultLanguage: "en")
            config.sessionConfiguration.httpAdditionalHeaders = [
                "User-Agent": "AdMoaiSDK/test"
            ]
            let sdk = AdMoai(config: config)
            let tracking = try trackingJSON(
                trackers: """
                    [{"trackerId": "tpt_1", "eventType": "impression", "url": "https://agency.example/imp"}]
                    """)
            sdk.fireImpression(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(2))

            let trackerReq = try #require(requests(to: "agency.example").first)
            #expect(trackerReq.value(forHTTPHeaderField: "X-Decision-Version") == nil)
            #expect(trackerReq.value(forHTTPHeaderField: "X-Tracking-Version") == nil)
            #expect(trackerReq.value(forHTTPHeaderField: "Accept-Language") == nil)
            #expect(trackerReq.value(forHTTPHeaderField: "Authorization") == nil)
            let userAgent = trackerReq.value(forHTTPHeaderField: "User-Agent") ?? ""
            #expect(!userAgent.contains("AdMoaiSDK"))
            #expect(trackerReq.httpShouldHandleCookies == false)
            // E32: cache bypass + no conditional revalidation headers.
            #expect(trackerReq.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
            #expect(trackerReq.value(forHTTPHeaderField: "If-None-Match") == nil)
            #expect(trackerReq.value(forHTTPHeaderField: "If-Modified-Since") == nil)

            let canonicalReq = try #require(requests(to: "api.mock.admoai.com").first)
            #expect(canonicalReq.value(forHTTPHeaderField: "X-Tracking-Version") == "2025-11-01")
            #expect(canonicalReq.value(forHTTPHeaderField: "Accept-Language") == "en")
        }

        // A12 + E30 (wire): a macro tracker is discarded end-to-end; a clean sibling fires
        @Test
        func testMacroURLIsDiscardedNeverFiredMutated() async throws {
            MockURLProtocol.reset()
            let sdk = makeSDK()
            let tracking = try trackingJSON(
                trackers: """
                    [{"trackerId": "tpt_macro", "eventType": "impression", "url": "https://agency.example/imp?cb=%%CACHEBUSTER%%"},
                     {"trackerId": "tpt_ok", "eventType": "impression", "url": "https://agency.example/clean"}]
                    """)
            sdk.fireImpression(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(2))
            #expect(!(await MockURLProtocol.waitForRequests(3, timeout: 0.5)))
            let urls = requests(to: "agency.example").compactMap { $0.url?.absoluteString }
            #expect(urls == ["https://agency.example/clean"])
        }

        // E29: a Set-Cookie from a tracker response is not persisted and not re-sent
        @Test
        func testTrackerCookiesAreNeverPersisted() async throws {
            MockURLProtocol.reset(
                stub: MockURLProtocol.Stub(
                    statusCode: 200,
                    body: Data(),
                    headers: ["Set-Cookie": "session=abc123; Path=/"]
                ))
            let dispatcher = ThirdPartyTrackerDispatcher(
                protocolClasses: [MockURLProtocol.self],
                logger: MockURLProtocol.config().logger
            )
            dispatcher.dispatch(
                [tracker(url: "https://agency.example/imp")], event: .impression)
            #expect(await MockURLProtocol.waitForRequests(1))
            dispatcher.dispatch(
                [tracker(url: "https://agency.example/imp")], event: .impression)
            #expect(await MockURLProtocol.waitForRequests(2))
            let second = try #require(MockURLProtocol.capturedRequests.last)
            #expect(second.value(forHTTPHeaderField: "Cookie") == nil)
        }

        // E33: a connection-refused tracker never affects its sibling
        @Test
        func testConnectionErrorIsolatedFromSiblings() async throws {
            MockURLProtocol.reset(
                stub: MockURLProtocol.Stub(errorHosts: ["refused.example"]))
            let dispatcher = ThirdPartyTrackerDispatcher(
                protocolClasses: [MockURLProtocol.self],
                logger: MockURLProtocol.config().logger
            )
            dispatcher.dispatch(
                [
                    tracker(id: "tpt_1", url: "https://refused.example/a"),
                    tracker(id: "tpt_2", url: "https://agency.example/b"),
                ], event: .impression)
            // Both attempts happen (the error host is still a completed attempt) and
            // the healthy sibling is unaffected.
            #expect(await MockURLProtocol.waitForRequests(2))
            #expect(!(await MockURLProtocol.waitForRequests(3, timeout: 0.5)))
            let hosts = MockURLProtocol.capturedRequests.compactMap { $0.url?.host }.sorted()
            #expect(hosts == ["agency.example", "refused.example"])
        }

        // E31: a 3xx from a tracker is terminal — the redirect target is never requested
        @Test
        func testTrackerRedirectIsTerminal() async throws {
            MockURLProtocol.reset(
                stub: MockURLProtocol.Stub(
                    statusCode: 302,
                    body: Data(),
                    headers: ["Location": "https://redirect-target.example/next"]
                ))
            let dispatcher = ThirdPartyTrackerDispatcher(
                protocolClasses: [MockURLProtocol.self],
                logger: MockURLProtocol.config().logger
            )
            dispatcher.dispatch(
                [tracker(url: "https://agency.example/imp")], event: .impression)
            #expect(await MockURLProtocol.waitForRequests(1))
            // Give a follow-up (which would be a bug) time to appear, then assert it did not.
            #expect(!(await MockURLProtocol.waitForRequests(2, timeout: 0.5)))
            let hosts = MockURLProtocol.capturedRequests.compactMap { $0.url?.host }
            #expect(hosts == ["agency.example"])
        }

        // E34: a 500 from a tracker is a completed attempt — no retry
        @Test
        func testTrackerServerErrorIsNeverRetried() async throws {
            MockURLProtocol.reset(
                stub: MockURLProtocol.Stub(statusCode: 500, body: Data(), headers: [:]))
            let dispatcher = ThirdPartyTrackerDispatcher(
                protocolClasses: [MockURLProtocol.self],
                logger: MockURLProtocol.config().logger
            )
            dispatcher.dispatch(
                [tracker(url: "https://agency.example/imp")], event: .impression)
            #expect(await MockURLProtocol.waitForRequests(1))
            #expect(!(await MockURLProtocol.waitForRequests(2, timeout: 0.5)))
        }

        // E33: a failing tracker never affects siblings or the canonical beacon
        @Test
        func testFailureIsolationAcrossSiblings() async throws {
            // The stub returns 500 for EVERY request: all three dispatches still happen.
            MockURLProtocol.reset(
                stub: MockURLProtocol.Stub(statusCode: 500, body: Data(), headers: [:]))
            let sdk = makeSDK()
            let tracking = try trackingJSON(
                trackers: """
                    [{"trackerId": "tpt_1", "eventType": "impression", "url": "https://agency.example/a"},
                     {"trackerId": "tpt_2", "eventType": "impression", "url": "https://agency.example/b"}]
                    """)
            sdk.fireImpression(tracking: tracking)
            #expect(await MockURLProtocol.waitForRequests(3))
            #expect(requests(to: "agency.example").count == 2)
            #expect(requests(to: "api.mock.admoai.com").count == 1)
        }
    }
}
