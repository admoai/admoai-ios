import AdMoai
import Foundation

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
}

struct ManifestRequest: Decodable {
    let placements: [ManifestPlacement]
    var custom: [ManifestCustom]?
    var session: String?
    var journeyOpt: String?
    /// Absent = the suite default. `"none"` = send no version header at all.
    var apiVersion: String?
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
    let driver: Driver
    switch entry.request.apiVersion {
    case .some("none"): driver = newDriver(apiVersion: nil)
    case .some(let version): driver = newDriver(apiVersion: version)
    case nil: driver = newDriver()
    }

    let builder = driver.sdk.createRequestBuilder()
    for placement in entry.request.placements {
        _ = builder.addPlacement(
            key: placement.key,
            count: placement.count,
            format: placement.format.flatMap(Format.init(rawValue:)),
            advertiserId: placement.advertiserId,
            templateId: placement.templateId)
    }
    for custom in entry.request.custom ?? [] {
        _ = builder.addCustomTargeting(key: custom.key, value: custom.value)
    }
    if entry.request.session != nil { _ = builder.setSessionId(freshSession(entry.id.lowercased())) }
    if let opt = entry.request.journeyOpt {
        _ = builder.setJourneyOpt(opt == "in" ? .optIn : .optOut)
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
                "a local SDK error is expected for this scenario (got \(sdkError))")
            notes.append("rejected locally as \(sdkError), no network call")
            return
        } catch let apiError as APIError {
            try check(expected.kind != "local", "the SDK rejects this before any network call")
            guard case .validationError(let errors) = apiError else {
                throw ClaimFailed(
                    claim: "a validation error is raised (got \(apiError.description))")
            }
            if let code = expected.code {
                try check(
                    errors.contains { $0.code == code },
                    "the engine error code is \(code) (got \(errors.map(\.code)))")
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
            "the response carries \(expected) decision(s) (got \(served.decisions.count))")
    }
    if entry.expect.decisionsMatchRequest == true {
        let requested = entry.request.placements.map(\.key)
        let returned = served.decisions.map(\.placement)
        try check(
            Set(requested) == Set(returned),
            "every requested placement is keyed back: \(requested) vs \(returned)")
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
            "at most \(atMost) creatives are returned (got \(creatives.count))")
        notes.append("returned \(creatives.count) creative(s)")
    }
    if entry.expect.creativesDistinct == true, creatives.count > 1 {
        let ids = creatives.compactMap { $0.metadata?.creativeId }
        try check(Set(ids).count == ids.count, "the returned creatives are distinct (got \(ids))")
    }

    guard let expectations = entry.expect.creative else { return }
    try assertCreative(creatives[0], expectations, &notes)
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
            "priority is one of \(allowed) (got \(metadata.priority.rawValue))")
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
            "isJourneyAd is \(wantsJourney) (got \(creative.isJourneyAd))")
    }
    if let format = expect.formatEquals {
        try check(
            creative.metadata?.format == format,
            "metadata.format is \"\(format)\" (got \(creative.metadata?.format ?? "nil"))")
    }
    if let delivery = expect.deliveryEquals {
        try check(
            creative.delivery == delivery,
            "delivery is \"\(delivery)\" (got \(creative.delivery ?? "nil"))")
    }
    switch expect.impressions {
    case "required":
        try check(
            !(creative.tracking.impressions ?? []).isEmpty, "an impression URL is exposed")
    case "forbidden":
        try check(
            (creative.tracking.impressions ?? []).isEmpty,
            "NO engine-side impression URL is exposed (VAST owns it; both would double-count)")
    default: break
    }
    if let atLeast = expect.clicksAtLeast {
        let clicks = creative.tracking.clicks ?? []
        try check(
            clicks.count >= atLeast,
            "at least \(atLeast) click URL(s) exposed (got \(clicks.count))")
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
            "video events include \(keys) (got \(actual.sorted()))")
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
            "isSkippable() is \(skippable) (got \(creative.isSkippable()))")
    }
    if let offset = expect.helperSkipOffsetEquals {
        try check(
            creative.getSkipOffset() == offset,
            "getSkipOffset() is \"\(offset)\" (got \(creative.getSkipOffset() ?? "nil"))")
    }
    if let mode = expect.endCardModeEquals {
        try check(
            creative.metadata?.endCardMode == mode,
            "metadata.endCardMode is \"\(mode)\" (got \(creative.metadata?.endCardMode ?? "nil"))")
    }
}

/// Issues a prebuilt request. Mirrors `decide` but takes the request already built, because the
/// interpreter assembles it from manifest data rather than from named arguments.
private func decideManifest(_ driver: Driver, _ request: DecisionRequest) async throws -> Served {
    let response = try await driver.sdk.requestAds(request)
    return Served(
        decisions: response.body.data ?? [],
        statusCode: response.response.statusCode,
        rawBody: response.rawBody)
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
            .addGeoTargeting(5128581)
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
            "a User-Agent identifying the SDK is sent (got \(headers["User-Agent"] ?? "nil"))")
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
