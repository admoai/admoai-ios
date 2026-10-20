import AdMoai
import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Shared manifest interpreter

//
// Executes `scenarios.json`, the cross-SDK scenario manifest. The manifest is the single
// definition of each declarative scenario; this file is only the Swift interpreter for it.
//
// Why a manifest at all: the 37 hand-written journey scenarios exist three times, once per
// language, and they had ALREADY drifted — Android's K1 asserted less than iOS's and Flutter's,
// which is why a pinned-ULID bug failed on only two of the three suites. Every scenario added by
// hand is three more chances to diverge. Here a scenario is added once, as data, and all three
// SDKs execute the same claims.
//
// Scope: declarative scenarios only — build a request, assert the outcome. Anything procedural
// (log capture, concurrency interleaving, retry semantics, TTL sleeps) stays hand-written,
// because that genuinely differs per platform.

// MARK: Manifest model

struct Manifest: Decodable {
    let schemaVersion: Int
    let scenarios: [ManifestScenario]
}

struct ManifestScenario: Decodable {
    let id: String
    let title: String
    let request: ManifestRequest
    let expect: ManifestExpect
    /// Sponsored Pin: the point-tracking calls an app makes on the served pins (adhub#4410).
    var pinTracking: ManifestPinTracking?
}

struct ManifestRequest: Decodable {
    let placements: [ManifestPlacement]
    var custom: [ManifestCustom]?
    var session: String?
    var journeyOpt: String?
    /// Absent = the suite default. `"none"` = send no version header at all.
    var apiVersion: String?
    /// Sponsored Pin: a radius or a bounds search (epic #3138).
    var distance: ManifestDistance?
}

/// One Sponsored Pin search, declared once in the shared manifest and expressed by each SDK
/// through its own idiom for the two shapes.
struct ManifestDistance: Decodable {
    let latitude: Double
    let longitude: Double
    var radius: Double?
    var bounds: ManifestBounds?
    var limit: Int?
}

struct ManifestBounds: Decodable {
    let north: Double
    let south: Double
    let east: Double
    let west: Double
}

struct ManifestPlacement: Decodable {
    let key: String
    var count: Int?
    var format: String?
    var advertiserId: String?
    var templateId: String?
}

struct ManifestCustom: Decodable {
    let key: String
    let value: String
}

struct ManifestExpect: Decodable {
    /// served | noAd | error
    let outcome: String
    var decisions: Int?
    var creativesAtMost: Int?
    var creativesDistinct: Bool?
    var decisionsMatchRequest: Bool?
    var error: ManifestError?
    var creative: ManifestCreative?
}

struct ManifestError: Decodable {
    /// validation | local
    let kind: String
    var status: Int?
    var code: Int?
}

struct ManifestCreative: Decodable {
    var requireMetadata: Bool?
    var requireAdvertiser: Bool?
    var requireTemplate: Bool?
    var requireContents: Bool?
    var journey: Bool?
    var formatEquals: String?
    var deliveryEquals: String?
    var priorityIn: [String]?
    var impressions: String?
    var clicksAtLeast: Int?
    // --- Sponsored Pin ---
    var matchedPointsAtLeast: Int?
    var matchedPointsEquals: Int?
    var matchedPointsNone: Bool?
    var matchedPointsNearestFirst: Bool?
    var matchedPointsWellFormed: Bool?
    var matchedPointsHaveBeacons: Bool?
    var matchedPointsHaveClickUrl: Bool?
    var videoEventCount: Int?
    var videoEventKeys: [String]?
    var requireVastTagUrl: Bool?
    var requireVastXmlDecodes: Bool?
    var metadataIsSkippable: Bool?
    var skipOffsetSecondsEquals: Int?
    var helperIsSkippable: Bool?
    var helperSkipOffsetEquals: String?
    var endCardModeEquals: String?
}

// MARK: Loading

/// Loads the manifest from beside the runner sources.
///
/// Resolved relative to `#filePath` rather than a bundle: this is an SPM `executableTarget`, not a
/// test target, so there is no resource bundle to read from and no `Bundle.module`.
func loadManifest() throws -> Manifest {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("scenarios.json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Manifest.self, from: data)
}

// MARK: Execution

/// Runs every manifest scenario through the SDK's real public API.
func manifestGroup() async {
    let manifest: Manifest
    do {
        manifest = try loadManifest()
    } catch {
        await scenario("MANIFEST", "the shared scenario manifest loads") { _ in
            throw ClaimFailed(claim: "scenarios.json is readable and valid: \(error)")
        }
        return
    }

    for entry in manifest.scenarios {
        await scenario(entry.id, entry.title) { notes in
            try await runManifestScenario(entry, &notes)
        }
    }
}

private func runManifestScenario(_ entry: ManifestScenario, _ notes: inout [String]) async throws {
    // "none" means: build a driver with no apiVersion, so no version header is sent.
    let driver: Driver = switch entry.request.apiVersion {
    case .some("none"): newDriver(apiVersion: nil)
    case let .some(version): newDriver(apiVersion: version)
    case nil: newDriver()
    }

    let builder = driver.sdk.createRequestBuilder()
    for placement in entry.request.placements {
        _ = builder.addPlacement(
            key: placement.key,
            count: placement.count,
            format: placement.format.flatMap(Format.init(rawValue:)),
            advertiserId: placement.advertiserId,
            templateId: placement.templateId
        )
    }
    for custom in entry.request.custom ?? [] {
        _ = builder.addCustomTargeting(key: custom.key, value: custom.value)
    }
    if entry.request.session != nil {
        _ = builder.setSessionId(freshSession(entry.id.lowercased()))
    }
    if let opt = entry.request.journeyOpt {
        _ = builder.setJourneyOpt(opt == "in" ? .optIn : .optOut)
    }
    if let d = entry.request.distance {
        if let b = d.bounds {
            _ = try builder.setDistanceTargeting(
                latitude: d.latitude, longitude: d.longitude,
                bounds: DistanceBounds(north: b.north, south: b.south, east: b.east, west: b.west),
                limit: d.limit
            )
        } else if let r = d.radius {
            _ = try builder.setDistanceTargeting(
                latitude: d.latitude, longitude: d.longitude, radius: r, limit: d.limit
            )
        }
    }

    let request = builder.build()

    // --- error outcomes -------------------------------------------------------------------
    if entry.expect.outcome == "error" {
        guard let expected = entry.expect.error else {
            throw ClaimFailed(claim: "manifest scenario declares outcome=error but no error block")
        }
        do {
            _ = try await driver.sdk.requestAds(request)
            throw ClaimFailed(claim: "the request is rejected (it succeeded instead)")
        } catch let claim as ClaimFailed {
            throw claim
        } catch let sdkError as SDKError {
            try check(
                expected.kind == "local",
                "a local SDK error is expected for this scenario (got \(sdkError))"
            )
            notes.append("rejected locally as \(sdkError), no network call")
            return
        } catch let apiError as APIError {
            try check(expected.kind != "local", "the SDK rejects this before any network call")
            guard case let .validationError(errors) = apiError else {
                throw ClaimFailed(
                    claim: "a validation error is raised (got \(apiError.description))"
                )
            }
            if let code = expected.code {
                try check(
                    errors.contains { $0.code == code },
                    "the engine error code is \(code) (got \(errors.map(\.code)))"
                )
            }
            notes.append("rejected with \(errors.map { "[\($0.code)] \($0.message)" }.joined())")
            return
        }
    }

    // --- served / no-ad outcomes ----------------------------------------------------------
    let served = try await decideManifest(driver, request)

    if let expected = entry.expect.decisions {
        try check(
            served.decisions.count == expected,
            "the response carries \(expected) decision(s) (got \(served.decisions.count))"
        )
    }
    if entry.expect.decisionsMatchRequest == true {
        let requested = entry.request.placements.map(\.key)
        let returned = served.decisions.map(\.placement)
        try check(
            Set(requested) == Set(returned),
            "every requested placement is keyed back: \(requested) vs \(returned)"
        )
    }

    guard let decision = served.decisions.first else {
        throw ClaimFailed(claim: "at least one decision is returned")
    }
    let creatives = decision.creatives ?? []

    if entry.expect.outcome == "noAd" {
        try check(decision.isNoAd, "the decision is a clean no-ad (got \(creatives.count) creatives)")
        try check(!decision.hasCreative, "hasCreative is false")
        notes.append("no-ad on \(decision.placement), nothing exposed to fire")
        return
    }

    try check(decision.hasCreative, "a creative is served on \(decision.placement)")

    if let atMost = entry.expect.creativesAtMost {
        try check(
            creatives.count <= atMost,
            "at most \(atMost) creatives are returned (got \(creatives.count))"
        )
        notes.append("returned \(creatives.count) creative(s)")
    }
    if entry.expect.creativesDistinct == true, creatives.count > 1 {
        let ids = creatives.compactMap { $0.metadata?.creativeId }
        try check(Set(ids).count == ids.count, "the returned creatives are distinct (got \(ids))")
    }

    if let expectations = entry.expect.creative {
        try assertCreative(creatives[0], expectations, &notes)
    }
    if let pinTracking = entry.pinTracking {
        try await runPinTracking(pinTracking, driver, request, creatives[0], &notes)
    }
}

// MARK: Creative assertions

private func assertCreative(
    _ creative: Creative, _ expect: ManifestCreative, _ notes: inout [String]
) throws {
    if expect.requireMetadata == true {
        guard let metadata = creative.metadata else {
            throw ClaimFailed(claim: "the creative carries a metadata block")
        }
        for (label, value) in [
            ("adId", metadata.adId), ("creativeId", metadata.creativeId),
            ("placementId", metadata.placementId), ("templateId", metadata.templateId),
        ] {
            try check(!value.isEmpty, "metadata.\(label) is non-empty")
        }
        notes.append("metadata: ad=\(metadata.adId) creative=\(metadata.creativeId)")
    }
    if let allowed = expect.priorityIn, let metadata = creative.metadata {
        try check(
            allowed.contains(metadata.priority.rawValue),
            "priority is one of \(allowed) (got \(metadata.priority.rawValue))"
        )
    }
    if expect.requireAdvertiser == true {
        let advertiser = creative.advertiser
        try check(!(advertiser.name ?? "").isEmpty, "advertiser.name is non-empty")
        try check(!(advertiser.legalName ?? "").isEmpty, "advertiser.legalName is non-empty")
        try check(!(advertiser.logoUrl ?? "").isEmpty, "advertiser.logoUrl is non-empty")
    }
    if expect.requireTemplate == true {
        try check(!(creative.template?.key ?? "").isEmpty, "template.key is non-empty")
    }
    if expect.requireContents == true {
        try check(creative.contents.hasContents(), "the creative carries content fields")
        notes.append("\(creative.contents.count) content field(s)")
    }
    if let wantsJourney = expect.journey {
        try check(
            creative.isJourneyAd == wantsJourney,
            "isJourneyAd is \(wantsJourney) (got \(creative.isJourneyAd))"
        )
    }
    if let format = expect.formatEquals {
        try check(
            creative.metadata?.format == format,
            "metadata.format is \"\(format)\" (got \(creative.metadata?.format ?? "nil"))"
        )
    }
    if let delivery = expect.deliveryEquals {
        try check(
            creative.delivery == delivery,
            "delivery is \"\(delivery)\" (got \(creative.delivery ?? "nil"))"
        )
    }

    // --- Sponsored Pin ------------------------------------------------------------------
    let points = creative.matchedPoints
    if let atLeast = expect.matchedPointsAtLeast {
        try check(
            points.count >= atLeast,
            "the creative carries at least \(atLeast) matched point(s) (got \(points.count))"
        )
    }
    if let exactly = expect.matchedPointsEquals {
        try check(
            points.count == exactly,
            "the creative carries exactly \(exactly) matched point(s) (got \(points.count))"
        )
    }
    if expect.matchedPointsNone == true {
        try check(points.isEmpty, "the creative carries NO matched points (got \(points.count))")
    }
    if expect.matchedPointsNearestFirst == true {
        var ordered = true
        for i in 1 ..< max(points.count, 1) where points[i - 1].distance > points[i].distance {
            ordered = false
        }
        try check(ordered, "matched points are ordered nearest first")
    }
    if expect.matchedPointsWellFormed == true {
        try check(!points.isEmpty, "there are matched points to inspect")
        for p in points {
            try check(!p.id.isEmpty, "point id is non-empty")
            try check(
                p.id.hasPrefix("advertiser_location_"),
                "point id is an Advertiser Location public id (got \(p.id))"
            )
            try check(!p.name.isEmpty, "point \(p.id) has a name")
            try check(p.distance >= 0, "point \(p.name) has a non-negative distance")
        }
    }
    if expect.matchedPointsHaveBeacons == true {
        try check(!points.isEmpty, "there are matched points to inspect")
        var seen = Set<String>()
        for p in points {
            guard let t = p.tracking else {
                try check(false, "point \(p.name) carries tracking")
                continue
            }
            try check(!(t.views ?? []).isEmpty, "point \(p.name) has a view beacon")
            try check(!(t.taps ?? []).isEmpty, "point \(p.name) has a tap beacon")
            try check(!(t.clicks ?? []).isEmpty, "point \(p.name) has a click beacon")
            // A shared beacon would attribute every shop's numbers to whichever one the
            // signed token happens to name.
            for item in t.views ?? [] {
                try check(
                    seen.insert(item.url).inserted,
                    "point \(p.name) has its own view beacon, not a shared one"
                )
            }
        }
    }
    if expect.matchedPointsHaveClickUrl == true {
        for p in points {
            try check(
                !(p.clickUrl ?? "").isEmpty,
                "point \(p.name) carries a resolved destination"
            )
        }
    }
    switch expect.impressions {
    case "required":
        try check(
            !(creative.tracking.impressions ?? []).isEmpty, "an impression URL is exposed"
        )
    case "forbidden":
        try check(
            (creative.tracking.impressions ?? []).isEmpty,
            "NO engine-side impression URL is exposed (VAST owns it; both would double-count)"
        )
    default: break
    }
    if let atLeast = expect.clicksAtLeast {
        let clicks = creative.tracking.clicks ?? []
        try check(
            clicks.count >= atLeast,
            "at least \(atLeast) click URL(s) exposed (got \(clicks.count))"
        )
    }
    if let count = expect.videoEventCount {
        let events = creative.tracking.videoEvents ?? []
        try check(
            events.count == count,
            "exactly \(count) video event URL(s) exposed (got \(events.count): \(events.map(\.key)))"
        )
    }
    if let keys = expect.videoEventKeys {
        let actual = Set((creative.tracking.videoEvents ?? []).map(\.key))
        try check(
            Set(keys).isSubset(of: actual),
            "video events include \(keys) (got \(actual.sorted()))"
        )
    }
    if expect.requireVastTagUrl == true {
        let tag = creative.getVastTagUrl()
        try check(!(tag ?? "").isEmpty, "a VAST tag URL is exposed")
        try check(creative.isVastTagDelivery(), "isVastTagDelivery() agrees with the delivery mode")
    }
    if expect.requireVastXmlDecodes == true {
        guard let base64 = creative.getVastXmlBase64(), let data = Data(base64Encoded: base64),
              let xml = String(data: data, encoding: .utf8)
        else {
            throw ClaimFailed(claim: "vast.xmlBase64 decodes to UTF-8 text")
        }
        try check(xml.contains("<VAST"), "the decoded payload is a VAST document")
        try check(creative.isVastXmlDelivery(), "isVastXmlDelivery() agrees with the delivery mode")
    }
    if let skippable = expect.metadataIsSkippable {
        try check(
            creative.metadata?.isSkippable == skippable,
            "metadata.isSkippable is \(skippable) (got \(String(describing: creative.metadata?.isSkippable)))"
        )
    }
    if let seconds = expect.skipOffsetSecondsEquals {
        try check(
            creative.metadata?.skipOffsetSeconds == seconds,
            "metadata.skipOffsetSeconds is \(seconds) (got \(String(describing: creative.metadata?.skipOffsetSeconds)))"
        )
    }
    if let skippable = expect.helperIsSkippable {
        // Proves the helper reads ENGINE metadata rather than falling through to content fields —
        // the Wave 2 fix, which no live scenario exercised until now.
        try check(
            creative.isSkippable() == skippable,
            "isSkippable() is \(skippable) (got \(creative.isSkippable()))"
        )
    }
    if let offset = expect.helperSkipOffsetEquals {
        try check(
            creative.getSkipOffset() == offset,
            "getSkipOffset() is \"\(offset)\" (got \(creative.getSkipOffset() ?? "nil"))"
        )
    }
    if let mode = expect.endCardModeEquals {
        try check(
            creative.metadata?.endCardMode == mode,
            "metadata.endCardMode is \"\(mode)\" (got \(creative.metadata?.endCardMode ?? "nil"))"
        )
    }
}

/// Issues a prebuilt request. Mirrors `decide` but takes the request already built, because the
/// interpreter assembles it from manifest data rather than from named arguments.
// MARK: Sponsored Pin tracking (adhub#4410)

//
// `pinTracking` replays what a map does with the pins it was served, through the SDK's real
// point-tracking calls, and asserts what actually reached the engine. The semantics are the
// manifest's, so all three interpreters implement them identically:
//
// - Steps run in order against the pins of the CURRENT response — the first creative of the
//   first decision. `{"newResponse": true}` sends the scenario's request again and makes its pins
//   current.
// - `{"views": "all"}` → `trackPointViews(all)`; `{"views": {"from": a, "to": b}}` →
//   `trackPointViews(pins[a..<b])`; `{"view": i}` → `trackPointView(pins[i])`; `{"tap": i}` and
//   `{"click": i}` → `trackPointTap` / `trackPointClick` on `pins[i]`.
// - Expected beacons are derived from the steps: every view URL of every pin a view step named,
//   once; every tap/click URL, once per call naming it. The runner waits for that many tracking
//   GETs, then a further 1.5 s so a duplicate arriving late is still caught.
// - `viewsOncePerResponse`: each expected view URL was sent exactly once, and no view URL of a
//   pin the app never showed was sent. `interactionsEveryCall`: each tap/click URL was sent once
//   per call. `newResponseHasNewViewUrls`: no view URL repeats across responses.
//   `engineAcceptsEveryBeacon`: the engine answered every tracking GET with a status below 400.
//   Always: the total number of tracking GETs equals the expected total — nothing stray.

struct ManifestPinTracking: Decodable {
    let steps: [ManifestPinStep]
    let expect: ManifestPinExpect
}

struct ManifestPinStep: Decodable {
    enum Views {
        case all
        case range(from: Int, to: Int)
    }

    var views: Views?
    var view: Int?
    var tap: Int?
    var click: Int?
    var newResponse: Bool?

    private enum CodingKeys: String, CodingKey { case views, view, tap, click, newResponse }
    private struct Range: Decodable {
        let from: Int
        let to: Int
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let all = try? c.decode(String.self, forKey: .views) {
            guard all == "all" else {
                throw DecodingError.dataCorruptedError(
                    forKey: .views, in: c, debugDescription: "views is \"all\" or {from, to}"
                )
            }
            views = .all
        } else if let range = try c.decodeIfPresent(Range.self, forKey: .views) {
            views = .range(from: range.from, to: range.to)
        }
        view = try c.decodeIfPresent(Int.self, forKey: .view)
        tap = try c.decodeIfPresent(Int.self, forKey: .tap)
        click = try c.decodeIfPresent(Int.self, forKey: .click)
        newResponse = try c.decodeIfPresent(Bool.self, forKey: .newResponse)
    }
}

struct ManifestPinExpect: Decodable {
    var viewsOncePerResponse: Bool?
    var interactionsEveryCall: Bool?
    var newResponseHasNewViewUrls: Bool?
    var engineAcceptsEveryBeacon: Bool?
}

private func runPinTracking(
    _ pin: ManifestPinTracking, _ driver: Driver, _ request: DecisionRequest,
    _ first: Creative, _ notes: inout [String]
) async throws {
    var responses: [[MatchedPoint]] = [first.matchedPoints]
    var expectedViews = Set<String>()
    var expectedInteractions: [String: Int] = [:]

    func pick(_ i: Int) throws -> MatchedPoint {
        let pins = responses[responses.count - 1]
        try check(i < pins.count, "the response carries a pin at index \(i) (got \(pins.count))")
        return pins[i]
    }

    RecordingURLProtocol.clear()
    for step in pin.steps {
        if step.newResponse == true {
            let served = try await decideManifest(driver, request)
            let pins = served.decisions.first?.creatives?.first?.matchedPoints ?? []
            try check(!pins.isEmpty, "the new decision response carries pins")
            responses.append(pins)
        }
        if let views = step.views {
            let pins = responses[responses.count - 1]
            let slice: [MatchedPoint]
            switch views {
            case .all:
                slice = pins
            case let .range(from, to):
                try check(to <= pins.count, "the response carries \(to) pins (got \(pins.count))")
                slice = Array(pins[from ..< to])
            }
            driver.sdk.trackPointViews(slice)
            for p in slice {
                expectedViews.formUnion((p.tracking?.views ?? []).map(\.url))
            }
        }
        if let i = step.view {
            let p = try pick(i)
            driver.sdk.trackPointView(p)
            expectedViews.formUnion((p.tracking?.views ?? []).map(\.url))
        }
        if let i = step.tap {
            let p = try pick(i)
            driver.sdk.trackPointTap(p)
            for item in p.tracking?.taps ?? [] {
                expectedInteractions[item.url, default: 0] += 1
            }
        }
        if let i = step.click {
            let p = try pick(i)
            driver.sdk.trackPointClick(p)
            for item in p.tracking?.clicks ?? [] {
                expectedInteractions[item.url, default: 0] += 1
            }
        }
    }

    let expectedTotal = expectedViews.count + expectedInteractions.values.reduce(0, +)
    try check(expectedTotal > 0, "the steps name at least one beacon to send")
    _ = await waitForFires(expectedTotal, timeout: 10)
    await sleepSeconds(1.5)
    let sent = RecordingURLProtocol.sent.filter { $0.contains("/v1/tracking") }
    let counts = sent.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }

    if pin.expect.viewsOncePerResponse == true {
        let everyViewURL = Set(responses.flatMap { $0 }.flatMap { ($0.tracking?.views ?? []).map(\.url) })
        for url in expectedViews {
            try check(counts[url] == 1, "a shown pin's view beacon is sent exactly once (got \(counts[url] ?? 0))")
        }
        let unexpected = Set(sent).intersection(everyViewURL).subtracting(expectedViews)
        try check(unexpected.isEmpty, "no view beacon is sent for a pin the app never showed (got \(unexpected.count))")
    }
    if pin.expect.interactionsEveryCall == true {
        for (url, times) in expectedInteractions {
            try check(
                counts[url] == times,
                "a tap/click beacon is sent on every call: \(times) (got \(counts[url] ?? 0))"
            )
        }
    }
    try check(
        sent.count == expectedTotal,
        "exactly \(expectedTotal) tracking GETs reach the engine, nothing stray (got \(sent.count))"
    )
    if pin.expect.newResponseHasNewViewUrls == true {
        try check(responses.count >= 2, "the steps fetched a second response")
        let perResponse = responses.map { Set($0.flatMap { ($0.tracking?.views ?? []).map(\.url) }) }
        for i in perResponse.indices {
            for j in perResponse.indices where j > i {
                try check(
                    perResponse[i].isDisjoint(with: perResponse[j]),
                    "a new response mints new view URLs for the same pins"
                )
            }
        }
    }
    if pin.expect.engineAcceptsEveryBeacon == true {
        let deadline = Date().addingTimeInterval(10)
        var answers = RecordingURLProtocol.answered.filter { $0.url.contains("/v1/tracking") }
        while answers.count < sent.count, Date() < deadline {
            await sleepSeconds(0.05)
            answers = RecordingURLProtocol.answered.filter { $0.url.contains("/v1/tracking") }
        }
        try check(answers.count == sent.count, "the engine answered every beacon (\(answers.count)/\(sent.count))")
        let rejected = answers.filter { !(200 ..< 400).contains($0.status) }
        try check(rejected.isEmpty, "the engine accepts every beacon (rejected: \(rejected.map(\.status)))")
    }
    notes.append(
        "\(responses.count) response(s), \(responses.map(\.count)) pins: \(expectedViews.count) view GET(s), "
            + "\(expectedInteractions.values.reduce(0, +)) tap/click GET(s), \(sent.count) sent in total"
    )
}

private func decideManifest(_ driver: Driver, _ request: DecisionRequest) async throws -> Served {
    let response = try await driver.sdk.requestAds(request)
    return Served(
        decisions: response.body.data ?? [],
        statusCode: response.response.statusCode,
        rawBody: response.rawBody
    )
}

// MARK: - §U wire shape (hand-written: needs the built request, not a served response)

//
// Procedural rather than manifest-driven: these assert what the SDK PUTS ON THE WIRE, which the
// declarative interpreter never inspects. `getHttpRequest` builds the body and headers without
// sending, so the whole group is offline and deterministic.

func wireShapeGroup() async {
    await scenario("U1", "the canonical request body uses the engine's canonical key names") { notes in
        let driver = newDriver()
        let builder = driver.sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .setUserId("u-1")
            .addGeoTargeting(5_128_581)
            .addLocationTargeting(latitude: 40.7, longitude: -74.0)
        _ = try builder.addDestinationTargeting(latitude: 41.0, longitude: -73.0, minConfidence: 0.8)
        let body = try bodyString(driver, builder.build())

        // `minConfidence` is canonical; `min_confidence` is a back-compat alias the engine keeps
        // only for already-fielded SDKs. A new version must not emit the alias.
        try check(body.contains("\"minConfidence\""), "destination uses the canonical camelCase key")
        try check(!body.contains("min_confidence"), "the legacy snake_case alias is NOT emitted")
        try check(body.contains("\"placements\""), "placements are present")
        try check(body.contains("\"latitude\"") && body.contains("\"longitude\""), "coordinates are present")
        notes.append("body keys verified against the engine's canonical contract")
    }

    await scenario("U2", "decision headers carry version, language and the SDK User-Agent") { notes in
        let driver = newDriver()
        let request = driver.sdk.createRequestBuilder().addPlacement(key: "home").build()
        let http = try driver.sdk.getHttpRequest(request)
        let headers = http.headers ?? [:]

        try check(headers["X-Decision-Version"] == e2eAPIVersion, "X-Decision-Version is \(e2eAPIVersion)")
        try check(headers["Accept-Language"] == e2eLanguage, "Accept-Language is \(e2eLanguage)")
        try check(
            (headers["User-Agent"] ?? "").hasPrefix("AdMoaiSDK/"),
            "a User-Agent identifying the SDK is sent (got \(headers["User-Agent"] ?? "nil"))"
        )
        try check(headers["Content-Type"] == "application/json", "Content-Type is application/json")
        notes.append("headers: \(headers.keys.sorted().joined(separator: ", "))")
    }

    await scenario("U3", "omitted optional fields are absent from the body, not sent as null") { notes in
        let driver = newDriver()
        let request = driver.sdk.createRequestBuilder().addPlacement(key: "home").build()
        let body = try bodyString(driver, request)

        // A tolerant engine accepts nulls, but emitting them makes every payload larger and
        // muddies "the publisher did not set this" versus "the publisher cleared this".
        try check(!body.contains("\"format\""), "an unset placement format is omitted entirely")
        try check(!body.contains("\"count\""), "an unset count is omitted entirely")
        try check(!body.contains("null"), "no explicit nulls are emitted anywhere in the body")
        notes.append("no nulls, no unset optional keys")
    }

    await scenario("U4", "disabling app and device collection removes those blocks from the wire") { notes in
        let driver = newDriver()
        let request = driver.sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .disableAppCollection()
            .disableDeviceCollection()
            .build()
        let body = try bodyString(driver, request)

        try check(!body.contains("\"app\""), "the app block is absent")
        try check(!body.contains("\"device\""), "the device block is absent")
        notes.append("app and device omitted on request")
    }

    await scenario("U5", "Journey context reaches the wire as top-level camelCase") { notes in
        let driver = newDriver()
        let session = freshSession("u5")
        let request = driver.sdk.createRequestBuilder()
            .addPlacement(key: "home")
            .setSessionId(session)
            .setJourneyOpt(.optIn)
            .build()
        let body = try bodyString(driver, request)

        try check(body.contains("\"sessionId\":\"\(session)\""), "sessionId is top-level camelCase")
        try check(body.contains("\"journeyOpt\":\"in\""), "journeyOpt serializes to the wire literal \"in\"")
        notes.append("journey context verified on the wire")
    }
}

private func bodyString(_ driver: Driver, _ request: DecisionRequest) throws -> String {
    let http = try driver.sdk.getHttpRequest(request)
    guard let data = http.body, let text = String(data: data, encoding: .utf8) else {
        throw ClaimFailed(claim: "the built request carries a UTF-8 JSON body")
    }
    return text
}
