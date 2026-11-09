import Foundation
import ManifestExpectations
import Testing

@testable import AdMoai

/// The live manifest's schemaVersion 4 and 5 `expect.creative` keys and `slideTracking` helpers
/// (@admoai/sdk-scenarios 1.4.0 and 1.5.0, ST1-ST19): each key passes on a matching creative and fails on a mismatching one, and a key
/// nobody executes is refused rather than ignored. The runner proves the same code against a
/// real engine; this proves its fail paths offline.
struct LiveCreativeExpectationsTests {
    private typealias JSON = [String: Any]

    private func creative(
        metadata: JSON = [:], template: JSON? = ["key": "card", "style": "default"],
        contents: [JSON] = [], journey: JSON? = nil
    ) throws -> Creative {
        var wire: JSON = [
            "contents": contents,
            "metadata": metadata,
            "advertiser": ["name": "A"],
            "tracking": [String: Any](),
        ]
        if let template { wire["template"] = template }
        if let journey { wire["journey"] = journey }
        return try JSONDecoder().decode(Creative.self, from: JSONSerialization.data(withJSONObject: wire))
    }

    private func failures(_ expect: JSON, _ creative: Creative) -> [String] {
        LiveCreativeExpectations.failures(expect: expect, creative: creative)
    }

    private let meta: JSON = [
        "effectiveStandardFormatKey": "card", "effectiveStandardFormatVersion": 1,
        "templateSource": "admoai_standard",
    ]

    @Test func metadataPassesWhenEveryListedKeyMatches() throws {
        let c = try creative(metadata: meta)
        let expect: JSON = ["metadata": [
            "effectiveStandardFormatKey": "card", "effectiveStandardFormatVersion": 1,
            "templateSource": "admoai_standard", "assetContext": NSNull(),
        ]]
        #expect(failures(expect, c).isEmpty)
    }

    @Test func metadataFailsOnAMismatchingValue() throws {
        let c = try creative(metadata: meta)
        #expect(failures(["metadata": ["effectiveStandardFormatKey": "carousel"]], c).count == 1)
        #expect(failures(["metadata": ["effectiveStandardFormatVersion": 2]], c).count == 1)
        #expect(failures(["metadata": ["templateSource": "based_on_standard"]], c).count == 1)
    }

    @Test func metadataNullMeansAbsentAndFailsWhenPresent() throws {
        let c = try creative(metadata: meta)
        #expect(failures(["metadata": ["templateSource": NSNull()]], c).count == 1)
        let bare = try creative()
        #expect(failures(["metadata": ["templateSource": NSNull(), "effectiveStandardFormatKey": NSNull()]], bare).isEmpty)
    }

    @Test func assetContextIsReadFromTheServedMetadata() throws {
        let c = try creative(metadata: meta.merging(["assetContext": "vehicle_marker"]) { $1 })
        let bare = try creative(metadata: meta)
        #expect(failures(["metadata": ["assetContext": "vehicle_marker"]], c).isEmpty)
        #expect(failures(["metadata": ["assetContext": "vehicle_marker"]], bare).count == 1)
        #expect(failures(["metadata": ["assetContext": NSNull()]], c).count == 1)
        #expect(failures(["metadata": ["assetContext": "other"]], c).count == 1)
    }

    @Test func metadataNamingAnUnknownKeyFails() throws {
        let c = try creative(metadata: meta)
        #expect(failures(["metadata": ["bogus": "x"]], c).count == 1)
        #expect(failures(["metadata": "card"], c).count == 1)
    }

    @Test func templateKeyPassesAndFails() throws {
        let c = try creative()
        #expect(failures(["templateKey": "card"], c).isEmpty)
        #expect(failures(["templateKey": "carousel"], c).count == 1)
        #expect(failures(["templateKey": "card"], try creative(template: nil)).count == 1)
    }

    @Test func contentKeysIsAnExactUnorderedSetWithoutSlidesOrMatchedPoints() throws {
        let c = try creative(contents: [
            ["key": "title", "value": "t", "type": "text"],
            ["key": "body", "value": "b", "type": "text"],
            ["key": "slides", "value": [Any](), "type": "slides"],
        ])
        #expect(failures(["contentKeys": ["body", "title"]], c).isEmpty)
        #expect(failures(["contentKeys": ["title"]], c).count == 1, "a missing key fails")
        #expect(failures(["contentKeys": ["title", "body", "cta"]], c).count == 1, "an extra expected key fails")
    }

    @Test func styleInPassesWhenTheServedStyleIsListed() throws {
        let c = try creative(template: ["key": "card", "style": "dark"])
        #expect(failures(["styleIn": ["default", "dark"]], c).isEmpty)
        #expect(failures(["styleIn": ["default", "light"]], c).count == 1)
        #expect(failures(["styleIn": [String]()], c).count == 1, "an empty list is invalid")
        #expect(failures(["styleIn": ["default"]], try creative(template: ["key": "card"])).count == 1, "no style is not listed")
    }

    @Test func journeyStageKeyPassesAndFails() throws {
        let c = try creative(journey: ["stageKey": "pick"])
        #expect(failures(["journey": true, "journeyStageKey": "pick"], c).isEmpty)
        #expect(failures(["journey": true, "journeyStageKey": "other"], c).count == 1)
        #expect(failures(["journey": true, "journeyStageKey": "pick"], try creative()).count == 1, "not a journey ad")
        #expect(failures(["journeyStageKey": "pick"], c).count == 1, "needs journey: true")
    }

    @Test func aKeyNobodyExecutesIsRefusedNotIgnored() {
        #expect(LiveCreativeExpectations.unknownKeys(in: ["templateKey": "card", "futureKey": 1]) == ["futureKey"])
        #expect(LiveCreativeExpectations.unknownKeys(in: ["metadata": [:], "styleIn": [], "formatEquals": "x"]).isEmpty)
    }

    // MARK: schemaVersion 5: slides, clickKeys, slideTracking

    private func slideWire(_ id: String, _ position: Int, contents: [String] = ["image"], clicks: [String] = ["default"]) -> JSON {
        [
            "slideId": id, "position": position,
            "contents": contents.map { ["key": $0, "value": "v", "type": "text"] },
            "tracking": [
                "views": [["key": "slide_view", "url": "https://e.test/v1/tracking/view/\(id)"]],
                "clicks": clicks.map { ["key": $0, "url": "https://e.test/v1/tracking/click/\(id)/\($0)"] },
            ],
        ]
    }

    private func carousel(slides: [JSON]? = nil, clicks: [JSON] = []) throws -> Creative {
        let wire: JSON = [
            "contents": [["key": "slides", "value": slides ?? [slideWire("s1", 1), slideWire("s2", 2)], "type": "slides"]],
            "advertiser": ["name": "A"],
            "tracking": ["clicks": clicks],
        ]
        return try JSONDecoder().decode(Creative.self, from: JSONSerialization.data(withJSONObject: wire))
    }

    private func slideExpect(_ id: String, _ position: Int, clicks: [String] = ["default"]) -> JSON {
        ["slideId": id, "position": position, "contentKeys": ["image"], "viewKeys": ["slide_view"], "clickKeys": clicks]
    }

    @Test func slidesPassWhenOrderAndEveryKeySetMatch() throws {
        let c = try carousel()
        #expect(failures(["slides": [slideExpect("s1", 1), slideExpect("s2", 2)]], c).isEmpty)
    }

    @Test func slidesFailOnWrongOrderMissingExtraOrWrongKeys() throws {
        let c = try carousel()
        #expect(!failures(["slides": [slideExpect("s2", 2), slideExpect("s1", 1)]], c).isEmpty, "wrong order")
        #expect(!failures(["slides": [slideExpect("s1", 1)]], c).isEmpty, "a served slide the manifest does not list")
        #expect(!failures(["slides": [slideExpect("s1", 1), slideExpect("s2", 2), slideExpect("s3", 3)]], c).isEmpty, "a listed slide that is missing")
        #expect(!failures(["slides": [slideExpect("s1", 1), slideExpect("s2", 2, clicks: [])]], c).isEmpty, "an extra served click key")
        var wrongView = slideExpect("s1", 1)
        wrongView["viewKeys"] = ["other"]
        #expect(!failures(["slides": [wrongView, slideExpect("s2", 2)]], c).isEmpty)
        var wrongContent = slideExpect("s1", 1)
        wrongContent["contentKeys"] = ["image", "headline"]
        #expect(!failures(["slides": [wrongContent, slideExpect("s2", 2)]], c).isEmpty)
        var unknown = slideExpect("s1", 1)
        unknown["bogus"] = 1
        #expect(!failures(["slides": [unknown, slideExpect("s2", 2)]], c).isEmpty, "an unknown slide key is refused")
    }

    @Test func clickKeysIsTheExactSetOfCreativeLevelClickKeys() throws {
        let none = try carousel()
        #expect(failures(["clickKeys": [String]()], none).isEmpty)
        #expect(failures(["clickKeys": ["default"]], none).count == 1, "a missing key fails")
        let some = try carousel(clicks: [["key": "default", "url": "https://e.test/c"], ["key": "extra", "url": "https://e.test/e"]])
        #expect(failures(["clickKeys": ["extra", "default"]], some).isEmpty, "order is not asserted")
        #expect(failures(["clickKeys": [String]()], some).count == 1, "an extra served key fails")
    }

    @Test func beaconsMapBackToSlideAndKeyAndCompareInOrder() throws {
        let c = try carousel()
        let view = "https://e.test/v1/tracking/view/s2"
        let click = "https://e.test/v1/tracking/click/s2/default"
        let expected: [JSON] = [["slide": 2, "view": "slide_view"], ["slide": 2, "click": "default"]]
        #expect(LiveCreativeExpectations.beaconLabel(url: click, creative: c) == "slide 2 click default")
        #expect(LiveCreativeExpectations.beaconFailures(expected: expected, dispatched: [view, click], creative: c).isEmpty)
        #expect(!LiveCreativeExpectations.beaconFailures(expected: expected, dispatched: [click, view], creative: c).isEmpty, "order mismatch")
        #expect(!LiveCreativeExpectations.beaconFailures(expected: expected, dispatched: [view], creative: c).isEmpty, "a missing beacon")
        #expect(!LiveCreativeExpectations.beaconFailures(expected: expected, dispatched: [view, click, click], creative: c).isEmpty, "a stray beacon")
        #expect(!LiveCreativeExpectations.beaconFailures(expected: expected, dispatched: [view, "https://e.test/other"], creative: c).isEmpty, "an unknown URL")
        #expect(LiveCreativeExpectations.beaconFailures(expected: [], dispatched: [], creative: c).isEmpty, "no beacons expected, none sent")
        #expect(!LiveCreativeExpectations.beaconFailures(expected: [], dispatched: [view], creative: c).isEmpty)
    }

    @Test func aRejectedOrUnansweredBeaconFailsTheAcceptanceCheck() {
        #expect(LiveCreativeExpectations.acceptanceFailures(sentCount: 2, answered: [("a", 204), ("b", 302)]).isEmpty)
        #expect(LiveCreativeExpectations.acceptanceFailures(sentCount: 2, answered: [("a", 204), ("b", 403)]).count == 1, "rejected")
        #expect(LiveCreativeExpectations.acceptanceFailures(sentCount: 2, answered: [("a", 204), ("b", -1)]).count == 1, "transport error")
        #expect(LiveCreativeExpectations.acceptanceFailures(sentCount: 2, answered: [("a", 204)]).count == 1, "unanswered")
    }

    @Test func slideTrackingBlockNeedsSlidesAndRefusesUnknownKeys() {
        let block: JSON = ["steps": [["slideView": 1]], "expect": ["beacons": [JSON](), "engineAcceptsEveryBeacon": true]]
        #expect(LiveCreativeExpectations.slideTrackingShapeFailures(block, creativeExpect: ["slides": [JSON]()]).isEmpty)
        #expect(LiveCreativeExpectations.slideTrackingShapeFailures(block, creativeExpect: [:]).count == 1)
        let thirdParty: JSON = ["steps": [["custom": "expand"]], "expect": ["beacons": [JSON](), "thirdPartyBeacons": ["x"]]]
        #expect(LiveCreativeExpectations.slideTrackingShapeFailures(thirdParty, creativeExpect: ["slides": [JSON]()]).count == 2)
    }
}
