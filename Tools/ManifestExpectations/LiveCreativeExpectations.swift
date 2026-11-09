import AdMoai
import Foundation

// The `expect.creative` keys of the shared scenario manifest (@admoai/sdk-scenarios), as one
// pure function over a decoded creative. Lives in its own library target so the live runner
// (`journey-e2e`, an executable) and `swift test` execute the very same code: the runner proves it
// against a real engine, the unit tests prove its pass and fail paths offline.
//
// schemaVersion 4 added five keys (ST1-ST12) with exactly the semantics of the fixture-scenario
// keys of the same name (FixtureScenariosTests): `metadata`, `templateKey`, `contentKeys`,
// `styleIn`, `journeyStageKey`. schemaVersion 5 added `slides` and `clickKeys` (same semantics as
// the fixture keys; FixtureScenariosTests calls `slideFailures` below, so there is one
// implementation) and the live `slideTracking` block: `beaconLabels` maps what the SDK
// dispatched back to {slide, view|click key} and `acceptanceFailures` is the "engine accepts
// every beacon" check shared with `pinTracking`. A key this file does not know is a failure,
// never ignored: a runner that skipped a key would report green for a claim it never checked.

public enum LiveCreativeExpectations {
    /// The five keys schemaVersion 4 added plus the two schemaVersion 5 added.
    public static let standardFormatKeys: Set<String> = [
        "metadata", "templateKey", "contentKeys", "styleIn", "journeyStageKey", "slides", "clickKeys",
    ]

    /// Keys of a live scenario's `slideTracking` block, of its steps, and of its `expect`.
    public static let slideTrackingKeys: Set<String> = ["steps", "expect"]
    public static let slideStepKeys: Set<String> = ["slideView", "slideClick", "fireClick"]
    public static let slideTrackingExpectKeys: Set<String> = ["beacons", "engineAcceptsEveryBeacon"]
    /// Keys of one element of `expect.creative.slides`.
    public static let slideKeys: Set<String> = ["slideId", "position", "contentKeys", "viewKeys", "clickKeys"]

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

    /// Checks the schemaVersion 4 and 5 keys present in `expect` against the served creative and
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
        if let value = expect["clickKeys"] {
            guard let wanted = value as? [String] else {
                out.append("clickKeys is a list of strings (got \(value))")
                return out
            }
            let actual = Set((creative.tracking.clicks ?? []).map(\.key))
            if actual != Set(wanted) {
                out.append("clickKeys is exactly \(wanted.sorted()) (got \(actual.sorted()))")
            }
        }
        if let value = expect["slides"] {
            guard let wanted = value as? [[String: Any]] else {
                out.append("slides is a list of objects (got \(value))")
                return out
            }
            out += slideFailures(wanted, creative.slides)
        }
        return out
    }

    /// `expect.slides`: the ordered, exact list of served slides. Each element's three key lists
    /// are exact sets. One message per failed claim; this is the one implementation (the fixture
    /// scenarios call it too).
    public static func slideFailures(_ expected: [[String: Any]], _ slides: [Slide]) -> [String] {
        var out: [String] = []
        if slides.count != expected.count {
            out.append("slide count is \(expected.count) (got \(slides.count))")
        }
        for (index, want) in expected.enumerated() where index < slides.count {
            let slide = slides[index]
            let label = "slide \(index + 1)"
            for key in want.keys.sorted() where !slideKeys.contains(key) {
                out.append("\(label): unknown slide expect key \(key)")
            }
            if slide.slideId != want["slideId"] as? String {
                out.append("\(label) slideId is \(describe(want["slideId"])) (got \(slide.slideId))")
            }
            if slide.position != want["position"] as? Int {
                out.append("\(label) position is \(describe(want["position"])) (got \(slide.position))")
            }
            let sets: [(String, Set<String>)] = [
                ("contentKeys", Set(slide.contents.map(\.key))),
                ("viewKeys", Set((slide.tracking?.views ?? []).map(\.key))),
                ("clickKeys", Set((slide.tracking?.clicks ?? []).map(\.key))),
            ]
            for (name, actual) in sets where actual != Set(want[name] as? [String] ?? []) {
                out
                    .append(
                        "\(label) \(name) is exactly \((want[name] as? [String] ?? []).sorted()) (got \(actual.sorted()))"
                    )
            }
        }
        return out
    }

    // MARK: slideTracking (live, schemaVersion 5)

    /// Names a dispatched tracking URL by what it is on `creative`: `slide 2 view slide_view` or
    /// `slide 2 click default`, or `unknown <url>` for a URL that is none of the slides' trackers.
    public static func beaconLabel(url: String, creative: Creative) -> String {
        for (index, slide) in creative.slides.enumerated() {
            if let item = slide.tracking?.views?.first(where: { $0.url == url }) {
                return "slide \(index + 1) view \(item.key)"
            }
            if let item = slide.tracking?.clicks?.first(where: { $0.url == url }) {
                return "slide \(index + 1) click \(item.key)"
            }
        }
        return "unknown \(url)"
    }

    /// The label of one expected beacon (`{slide, view}` / `{slide, click}`), or nil when it is
    /// not of that shape.
    public static func beaconLabel(expected beacon: [String: Any]) -> String? {
        guard let slide = beacon["slide"] as? Int else { return nil }
        if let key = beacon["view"] as? String {
            return "slide \(slide) view \(key)"
        }
        if let key = beacon["click"] as? String {
            return "slide \(slide) click \(key)"
        }
        return nil
    }

    /// `slideTracking.expect.beacons`: the exact list of first-party beacons the SDK dispatched,
    /// `dispatchedSteps` holding the tracking URLs observed during each of `steps`, in step order.
    ///
    /// The manifest lists the beacons as one ordered list, so each one is first tied to the step
    /// that can produce it, walking both in order: a `slideView` step owns at most one view of its
    /// slide, a `slideClick` step at most one view of its slide followed by at most one click of
    /// it, and a `fireClick` step no first-party slide beacon. A beacon no step can own fails the
    /// list. Each step's beacons are then compared as a multiset: the live runner sees requests as
    /// the transport starts loading them, which reflects transport order, not the order the SDK
    /// dispatched them in. The SDK's own dispatch order (view before click) is pinned offline by
    /// fixture F18 through the dispatch seam.
    public static func beaconFailures(
        expected: [[String: Any]], steps: [[String: Any]], dispatchedSteps: [[String]], creative: Creative
    ) -> [String] {
        var wanted: [(slide: Int, label: String, isView: Bool)] = []
        for beacon in expected {
            guard let label = beaconLabel(expected: beacon), let slide = beacon["slide"] as? Int else {
                return ["beacon \(beacon) is {slide, view} or {slide, click}"]
            }
            wanted.append((slide, label, beacon["view"] != nil))
        }
        guard dispatchedSteps.count == steps.count else {
            return ["beacons were observed for \(dispatchedSteps.count) step(s), the block has \(steps.count)"]
        }
        var perStep: [[String]] = []
        var next = 0
        for step in steps {
            var owned: [String] = []
            func take(slide: Int, view: Bool) {
                if next < wanted.count, wanted[next].slide == slide, wanted[next].isView == view {
                    owned.append(wanted[next].label)
                    next += 1
                }
            }
            if let n = step["slideView"] as? Int {
                take(slide: n, view: true)
            } else if let n = step["slideClick"] as? Int {
                take(slide: n, view: true)
                take(slide: n, view: false)
            }
            perStep.append(owned)
        }
        if next < wanted.count {
            return ["beacons \(wanted[next...].map(\.label)) belong to no step of \(steps)"]
        }
        let actualSteps = dispatchedSteps.map { $0.map { beaconLabel(url: $0, creative: creative) } }
        var out: [String] = []
        for (index, (want, got)) in zip(perStep, actualSteps).enumerated() where want.sorted() != got.sorted() {
            out.append("step \(index + 1) \(steps[index]) sends \(want) (got \(got)), compared as a set")
        }
        return out
    }

    /// `engineAcceptsEveryBeacon`: every beacon sent got an answer, and none below 200 or at 400
    /// and above (a click's 3xx is the engine recording it). The definition `pinTracking` uses.
    public static func acceptanceFailures(
        sentCount: Int, answered: [(url: String, status: Int)]
    ) -> [String] {
        var out: [String] = []
        if answered.count != sentCount {
            out.append("the engine answered every beacon (\(answered.count)/\(sentCount))")
        }
        let rejected = answered.filter { !(200 ..< 400).contains($0.status) }
        if !rejected.isEmpty {
            out.append("the engine accepts every beacon (rejected: \(rejected.map(\.status)))")
        }
        return out
    }

    /// Structural check of a live `slideTracking` block; every message is a refusal to judge.
    public static func slideTrackingShapeFailures(_ block: [String: Any], creativeExpect: [String: Any]) -> [String] {
        var out: [String] = []
        for key in block.keys.sorted() where !slideTrackingKeys.contains(key) {
            out.append("slideTracking names unknown key \(key)")
        }
        let inner = block["expect"] as? [String: Any] ?? [:]
        for key in inner.keys.sorted() where !slideTrackingExpectKeys.contains(key) {
            out.append("slideTracking.expect names unknown key \(key)")
        }
        for step in block["steps"] as? [[String: Any]] ?? [] {
            for key in step.keys.sorted() where !slideStepKeys.contains(key) {
                out.append("slideTracking step names unknown key \(key)")
            }
        }
        if creativeExpect["slides"] == nil {
            out.append("slideTracking needs expect.creative.slides")
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
                if actual != nil {
                    out.append("metadata.\(key) is absent (got \(describe(actual)))")
                }
            } else if !equal(expected, actual) {
                out.append("metadata.\(key) is \(describe(expected)) (got \(describe(actual)))")
            }
        }
        return out
    }

    private static func equal(_ expected: Any, _ actual: Any?) -> Bool {
        switch (expected, actual) {
        case let (e as String, a as String): e == a
        case let (e as Int, a as Int): e == a
        default: false
        }
    }

    private static func describe(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "absent" }
        return "\(value)"
    }
}
