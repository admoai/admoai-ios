import AdMoai
import Foundation

// The `expect.creative` keys of the shared scenario manifest (@admoai/sdk-scenarios), as one
// pure function over a decoded creative. Lives in its own library target so the live runner
// (`journey-e2e`, an executable) and `swift test` execute the very same code: the runner proves it
// against a real engine, the unit tests prove its pass and fail paths offline.
//
// schemaVersion 4 added five keys (ST1-ST12) with exactly the semantics of the fixture-scenario
// keys of the same name (FixtureScenariosTests): `metadata`, `templateKey`, `contentKeys`,
// `styleIn`, `journeyStageKey`. A key this file does not know is a failure, never ignored: a
// runner that skipped a key would report green for a claim it never checked.

public enum LiveCreativeExpectations {
    /// The five keys schemaVersion 4 added.
    public static let standardFormatKeys: Set<String> = [
        "metadata", "templateKey", "contentKeys", "styleIn", "journeyStageKey",
    ]

    /// Every key under `expect.creative` the live runner understands: the ones it has always
    /// had (the fields of the runner's `ManifestCreative`) plus the five above.
    public static let knownKeys: Set<String> = standardFormatKeys.union([
        "requireMetadata", "requireAdvertiser", "requireTemplate", "requireContents", "journey",
        "formatEquals", "deliveryEquals", "priorityIn", "impressions", "clicksAtLeast",
        "matchedPointsAtLeast", "matchedPointsEquals", "matchedPointsNone",
        "matchedPointsNearestFirst", "matchedPointsWellFormed", "matchedPointsHaveBeacons",
        "matchedPointsHaveClickUrl", "videoEventCount", "videoEventKeys", "requireVastTagUrl",
        "requireVastXmlDecodes", "metadataIsSkippable", "skipOffsetSecondsEquals",
        "helperIsSkippable", "helperSkipOffsetEquals", "endCardModeEquals",
    ])

    /// The keys a `metadata` expectation may name.
    public static let metadataKeys = [
        "effectiveStandardFormatKey", "effectiveStandardFormatVersion", "templateSource", "assetContext",
    ]

    /// Keys of `expect` this runner does not know. Non-empty means the scenario cannot be judged.
    public static func unknownKeys(in expect: [String: Any]) -> [String] {
        expect.keys.filter { !knownKeys.contains($0) }.sorted()
    }

    /// Checks the five schemaVersion 4 keys present in `expect` against the served creative and
    /// returns one message per failed claim (empty = all hold).
    public static func failures(expect: [String: Any], creative: Creative) -> [String] {
        var out: [String] = []
        if let value = expect["metadata"] {
            out += metadataFailures(value, creative.metadata)
        }
        if let value = expect["templateKey"] {
            let actual = creative.template?.key
            if actual != value as? String || !(value is String) {
                out.append("templateKey is \(describe(value)) (got \(describe(actual)))")
            }
        }
        if let value = expect["contentKeys"] {
            guard let wanted = value as? [String] else {
                out.append("contentKeys is a list of strings (got \(value))")
                return out
            }
            // Slides and matched points are asserted through their own fields, so they are not
            // plain contents (same exclusion as the fixture interpreter).
            let plain = Set(creative.contents.map(\.key)).subtracting(["slides", "matched_points"])
            if plain != Set(wanted) {
                out.append("contentKeys is exactly \(wanted.sorted()) (got \(plain.sorted()))")
            }
        }
        if let value = expect["styleIn"] {
            guard let allowed = value as? [String], !allowed.isEmpty else {
                out.append("styleIn is a non-empty list of strings (got \(value))")
                return out
            }
            let style = creative.template?.style
            if !allowed.contains(style ?? "\u{0}") {
                out.append("template.style is one of \(allowed) (got \(describe(style)))")
            }
        }
        if let value = expect["journeyStageKey"] {
            if expect["journey"] as? Bool != true {
                out.append("journeyStageKey needs \"journey\": true beside it")
            }
            let actual = creative.journey?.stageKey
            if actual != value as? String || !(value is String) {
                out.append("journey.stageKey is \(describe(value)) (got \(describe(actual)))")
            }
        }
        return out
    }

    private static func metadataFailures(_ value: Any, _ metadata: Metadata?) -> [String] {
        guard let wanted = value as? [String: Any] else {
            return ["metadata is an object (got \(value))"]
        }
        var out: [String] = []
        for (key, expected) in wanted.sorted(by: { $0.key < $1.key }) {
            let actual: Any?
            switch key {
            case "effectiveStandardFormatKey": actual = metadata?.effectiveStandardFormatKey
            case "effectiveStandardFormatVersion": actual = metadata?.effectiveStandardFormatVersion
            case "templateSource": actual = metadata?.templateSource
            case "assetContext": actual = metadata?.assetContext
            default:
                out.append("metadata expectation names unknown key \(key) (known: \(metadataKeys))")
                continue
            }
            if expected is NSNull {
                if actual != nil { out.append("metadata.\(key) is absent (got \(describe(actual)))") }
            } else if !equal(expected, actual) {
                out.append("metadata.\(key) is \(describe(expected)) (got \(describe(actual)))")
            }
        }
        return out
    }

    private static func equal(_ expected: Any, _ actual: Any?) -> Bool {
        switch (expected, actual) {
        case let (e as String, a as String): return e == a
        case let (e as Int, a as Int): return e == a
        default: return false
        }
    }

    private static func describe(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "absent" }
        return "\(value)"
    }
}
