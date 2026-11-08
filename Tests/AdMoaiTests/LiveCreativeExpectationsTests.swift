import Foundation
import ManifestExpectations
import Testing

@testable import AdMoai

/// The live manifest's schemaVersion 4 `expect.creative` keys (@admoai/sdk-scenarios 1.4.0,
/// ST1-ST12): each key passes on a matching creative and fails on a mismatching one, and a key
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
}
