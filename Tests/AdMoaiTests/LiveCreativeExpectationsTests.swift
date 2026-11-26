@testable import AdMoai
import Foundation
import ManifestExpectations
import Testing

/// The live manifest's schemaVersion 4 and 5 `expect.creative` keys and `slideTracking` helpers
/// (@admoai/sdk-scenarios 1.4.0 and 1.5.0, ST1-ST19): each key passes on a matching creative and fails on a mismatching
/// one, and a key
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
        if let template {
            wire["template"] = template
        }
        if let journey {
            wire["journey"] = journey
        }
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
        #expect(failures(["metadata": ["templateSource": NSNull(), "effectiveStandardFormatKey": NSNull()]], bare)
            .isEmpty)
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
        #expect(try failures(["templateKey": "card"], creative(template: nil)).count == 1)
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
        #expect(
            try failures(["styleIn": ["default"]], creative(template: ["key": "card"])).count == 1,
            "no style is not listed"
        )
    }

    @Test func journeyStageKeyPassesAndFails() throws {
        let c = try creative(journey: ["stageKey": "pick"])
        #expect(failures(["journey": true, "journeyStageKey": "pick"], c).isEmpty)
        #expect(failures(["journey": true, "journeyStageKey": "other"], c).count == 1)
        #expect(try failures(["journey": true, "journeyStageKey": "pick"], creative()).count == 1, "not a journey ad")
        #expect(failures(["journeyStageKey": "pick"], c).count == 1, "needs journey: true")
    }

    @Test func aKeyNobodyExecutesIsRefusedNotIgnored() {
        #expect(LiveCreativeExpectations.unknownKeys(in: ["templateKey": "card", "futureKey": 1]) == ["futureKey"])
        #expect(LiveCreativeExpectations.unknownKeys(in: ["metadata": [:], "styleIn": [], "formatEquals": "x"]).isEmpty)
    }

    // MARK: schemaVersion 5: slides, clickKeys, slideTracking

    private func slideWire(_ id: String, _ position: Int, contents: [String] = ["image"],
                           clicks: [String] = ["default"]) -> JSON
    {
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
            "contents": [[
                "key": "slides",
                "value": slides ?? [slideWire("s1", 1), slideWire("s2", 2)],
                "type": "slides",
            ]],
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
        #expect(
            !failures(["slides": [slideExpect("s1", 1), slideExpect("s2", 2), slideExpect("s3", 3)]], c).isEmpty,
            "a listed slide that is missing"
        )
        #expect(
            !failures(["slides": [slideExpect("s1", 1), slideExpect("s2", 2, clicks: [])]], c).isEmpty,
            "an extra served click key"
        )
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
        let some = try carousel(clicks: [
            ["key": "default", "url": "https://e.test/c"],
            ["key": "extra", "url": "https://e.test/e"],
        ])
        #expect(failures(["clickKeys": ["extra", "default"]], some).isEmpty, "order is not asserted")
        #expect(failures(["clickKeys": [String]()], some).count == 1, "an extra served key fails")
    }

    @Test func beaconsAreTiedToTheirStepAndCompareAsASetWithinIt() throws {
        let c = try carousel()
        let view = "https://e.test/v1/tracking/view/s2"
        let click = "https://e.test/v1/tracking/click/s2/default"
        let tap: [JSON] = [["slideClick": 2]]
        let viewThenTap: [JSON] = [["slideView": 2], ["slideClick": 2]]
        let pair: [JSON] = [["slide": 2, "view": "slide_view"], ["slide": 2, "click": "default"]]
        func failures(_ steps: [JSON], _ observed: [[String]], _ expected: [JSON] = pair) -> [String] {
            LiveCreativeExpectations.beaconFailures(
                expected: expected, steps: steps, dispatchedSteps: observed, creative: c
            )
        }
        #expect(LiveCreativeExpectations.beaconLabel(url: click, creative: c) == "slide 2 click default")
        #expect(failures(viewThenTap, [[view], [click]]).isEmpty, "two steps, each with its own beacon")
        #expect(failures(tap, [[view, click]]).isEmpty, "one tap, view then click")
        #expect(failures(tap, [[click, view]]).isEmpty, "one tap, transport order differs: still the same set")
        #expect(!failures(viewThenTap, [[], [view, click]]).isEmpty, "the view arrives on the tap, not the view step")
        #expect(!failures(viewThenTap, [[view, click], []]).isEmpty, "the click arrives on the view step")
        #expect(!failures(tap, [[view]]).isEmpty, "a missing beacon")
        #expect(!failures(tap, [[view, click, click]]).isEmpty, "a stray beacon")
        #expect(!failures(tap, [[view, view]]).isEmpty, "a duplicate in place of the click")
        #expect(!failures(tap, [[view, "https://e.test/other"]]).isEmpty, "an unknown URL")
        #expect(!failures(tap, [[view, click], []]).isEmpty, "one observed list per step")
        #expect(
            !failures([["slideView": 2]], [[view]], pair).isEmpty,
            "a beacon no step can produce fails the list"
        )
        #expect(failures([["fireClick": NSNull()]], [[]], []).isEmpty, "no beacons expected, none sent")
        #expect(!failures([["fireClick": NSNull()]], [[view]], []).isEmpty)

        // ST17 as the manifest spells it, against a regression where the standalone view sends
        // nothing and the first tap sends view and click: the counts match, the steps do not.
        let st17Steps: [JSON] = [["slideView": 2], ["slideClick": 2], ["slideClick": 2]]
        let st17: [JSON] = pair + [["slide": 2, "click": "default"]]
        #expect(failures(st17Steps, [[view], [click], [click]], st17).isEmpty)
        #expect(!failures(st17Steps, [[], [view, click], [click]], st17).isEmpty)
    }

    @Test func aRejectedOrUnansweredBeaconFailsTheAcceptanceCheck() {
        #expect(LiveCreativeExpectations.acceptanceFailures(sentCount: 2, answered: [("a", 204), ("b", 302)]).isEmpty)
        #expect(
            LiveCreativeExpectations.acceptanceFailures(sentCount: 2, answered: [("a", 204), ("b", 403)]).count == 1,
            "rejected"
        )
        #expect(
            LiveCreativeExpectations.acceptanceFailures(sentCount: 2, answered: [("a", 204), ("b", -1)]).count == 1,
            "transport error"
        )
        #expect(
            LiveCreativeExpectations.acceptanceFailures(sentCount: 2, answered: [("a", 204)]).count == 1,
            "unanswered"
        )
    }

    @Test func slideTrackingBlockNeedsSlidesAndRefusesUnknownKeys() {
        let block: JSON = [
            "steps": [["slideView": 1]],
            "expect": ["beacons": [JSON](), "engineAcceptsEveryBeacon": true],
        ]
        #expect(LiveCreativeExpectations.slideTrackingShapeFailures(block, creativeExpect: ["slides": [JSON]()])
            .isEmpty)
        #expect(LiveCreativeExpectations.slideTrackingShapeFailures(block, creativeExpect: [:]).count == 1)
        let thirdParty: JSON = [
            "steps": [["custom": "expand"]],
            "expect": ["beacons": [JSON](), "thirdPartyBeacons": ["x"]],
        ]
        #expect(LiveCreativeExpectations.slideTrackingShapeFailures(thirdParty, creativeExpect: ["slides": [JSON]()])
            .count == 2)
    }

    // MARK: interactiveExperience (schemaVersion 8)

    private func leadGenerationCreative(
        formId: String = "form_01", prefill: [String] = ["fullName", "email"],
        expiresAt: String = "2026-11-12T15:15:00Z",
        descriptor: Bool = true
    ) throws -> Creative {
        var wire: JSON = [
            "contents": [JSON](),
            "metadata": JSON(),
            "advertiser": ["name": "A"],
            "tracking": JSON(),
        ]
        if descriptor {
            wire["interactiveExperience"] = [
                "type": "lead_generation",
                "formId": formId,
                "preparedVersionId": "form_version_01",
                "formInstanceId": "form_instance_01",
                "launchUrl": "https://api.admoai.com/v1/interactive-experiences/form",
                "preparationToken": "tok.preparation",
                "expiresAt": expiresAt,
                "prefillAttributeKeys": prefill,
            ] as JSON
        }
        return try JSONDecoder().decode(Creative.self, from: JSONSerialization.data(withJSONObject: wire))
    }

    private let received = ISO8601DateFormatter().date(from: "2026-11-12T15:00:00Z")!
    private let goodLaunch = URL(string: "https://api.admoai.com/v1/interactive-experiences/form")!
    private let wantsLeadGeneration: JSON = ["type": "lead_generation", "prefillAttributeKeys": ["fullName", "email"]]

    private func ieFailures(
        _ expected: Any, _ creative: Creative, launch: URL? = URL(string: "https://api.admoai.com/v1/form")
    ) -> [String] {
        LiveCreativeExpectations.interactiveExperienceFailures(
            expected, creative: creative, launchURL: launch, receivedAt: received
        )
    }

    @Test func interactiveExperienceIsAKnownKey() {
        #expect(LiveCreativeExpectations.unknownKeys(in: ["interactiveExperience": false]).isEmpty)
    }

    @Test func interactiveExperiencePassesOnAWellFormedLeadGenerationDescriptor() throws {
        let c = try leadGenerationCreative()
        #expect(ieFailures(wantsLeadGeneration, c, launch: goodLaunch).isEmpty)
    }

    @Test func interactiveExperienceFalseHoldsOnlyWithoutADescriptor() throws {
        #expect(try ieFailures(false, leadGenerationCreative(descriptor: false)).isEmpty)
        #expect(try ieFailures(false, leadGenerationCreative()).count == 1)
    }

    @Test func interactiveExperienceObjectFailsWithoutADescriptor() throws {
        #expect(try ieFailures(wantsLeadGeneration, leadGenerationCreative(descriptor: false)).count == 1)
    }

    @Test func interactiveExperienceFailsOnWrongPrefillOrder() throws {
        let c = try leadGenerationCreative(prefill: ["email", "fullName"])
        #expect(ieFailures(wantsLeadGeneration, c, launch: goodLaunch).count == 1)
    }

    @Test func interactiveExperienceFailsOnABadIdPrefix() throws {
        let c = try leadGenerationCreative(formId: "frm_01")
        #expect(ieFailures(wantsLeadGeneration, c, launch: goodLaunch).count == 1)
    }

    @Test func interactiveExperienceFailsOnALaunchUrlThatIsNotCleanHttps() throws {
        let c = try leadGenerationCreative()
        for bad in [
            "https://api.admoai.com/form?token=x", "https://api.admoai.com/form#frag", "http://api.admoai.com/form",
        ] {
            #expect(ieFailures(wantsLeadGeneration, c, launch: URL(string: bad)).count == 1, "\(bad)")
        }
        #expect(ieFailures(wantsLeadGeneration, c, launch: nil).count == 1)
    }

    @Test func interactiveExperienceFailsWhenAlreadyExpired() throws {
        let c = try leadGenerationCreative(expiresAt: "2026-11-12T14:59:59Z")
        #expect(ieFailures(wantsLeadGeneration, c, launch: goodLaunch).count == 1)
    }

    @Test func interactiveExperienceRefusesUnknownInnerKeysAndOtherValues() throws {
        let c = try leadGenerationCreative()
        var withExtra = wantsLeadGeneration
        withExtra["launchUrl"] = "x"
        #expect(ieFailures(withExtra, c, launch: goodLaunch).count == 1)
        #expect(ieFailures(true, c, launch: goodLaunch).count == 1)
        #expect(ieFailures("lead_generation", c, launch: goodLaunch).count == 1)
    }
}
