import AdMoai
import Foundation
import OSLog

// Harness for the Journey Ads live E2E runner.
//
// Black-box by design: every assertion is made against what a customer's app can observe —
// the SDK result and the `/decision` transport. Engine internals (Redis runtime state,
// decoded tracking-token identity, billing dedupe and totals, reporting, concurrency) are
// out of scope and owned by adhub's Go service-layer tests. Asserting them from an SDK is
// impossible; pretending otherwise produces false confidence.
//
// The design decisions here were earned on the Android runner and re-earned on Flutter; each
// exists because the naive alternative produced a wrong or useless result. See README.md.

// MARK: - Environment

/// Base URL of the locally-running decision-engine. No trailing slash.
let e2eBaseURL: String = {
    let raw = ProcessInfo.processInfo.environment["ADMOAI_JOURNEY_E2E_BASE_URL"]
        ?? "http://127.0.0.1:8080"
    var trimmed = raw
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    return trimmed
}()

/// The Journey-capable API version. A wrong version is a hard gate: the engine silently
/// ignores Journey fields and serves normal ads, with no error to notice.
let e2eAPIVersion = ProcessInfo.processInfo.environment["ADMOAI_JOURNEY_E2E_VERSION"]
    ?? "2025-11-01"

/// The locale the runner requests. Pinned because a creative without a variant in the
/// requested locale does not resolve — including the hand-built §K fixture, which is `en` only.
let e2eLanguage = "en"

let e2eReportPath = "build/journey-e2e/report.json"

// MARK: - Outcomes

enum Outcome: String {
    case pass = "PASS"
    case fail = "FAIL"
    case skip = "SKIP"
}

struct ScenarioResult {
    let id: String
    let title: String
    let outcome: Outcome
    /// Failure message, or the reason a scenario was skipped.
    let detail: String?
    /// Observations recorded while the scenario ran. Kept in the report so a later round can
    /// diff what the engine actually returned, not just pass/fail.
    let notes: [String]

    var json: [String: Any] {
        var out: [String: Any] = ["id": id, "title": title, "outcome": outcome.rawValue]
        if let detail = detail { out["detail"] = detail }
        if !notes.isEmpty { out["notes"] = notes }
        return out
    }
}

/// Thrown by a scenario body when the fixture it needs was never seeded.
///
/// A missing fixture is an environment fact, not a defect, so it must SKIP rather than FAIL —
/// otherwise a `db-reset` reads as a regression.
struct SkipScenario: Error {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

/// Aborts the whole run: the environment is unusable, so every scenario would fail for the
/// same reason. Reported once, with a diagnosis, as exit 2.
struct PreflightAbort: Error {
    let diagnosis: String
    let recipe: String?
    init(_ diagnosis: String, recipe: String? = nil) {
        self.diagnosis = diagnosis
        self.recipe = recipe
    }
}

/// A failed claim inside a scenario. Reads as a claim in the report rather than a matcher.
struct ClaimFailed: Error {
    let claim: String
}

/// Asserts a claim about observable behaviour.
func check(_ condition: Bool, _ claim: String) throws {
    if !condition { throw ClaimFailed(claim: claim) }
}

// MARK: - Report

final class E2eReport {
    private(set) var results: [ScenarioResult] = []
    var preflightDiagnosis: String?
    var preflightRecipe: String?

    var passed: Int { results.filter { $0.outcome == .pass }.count }
    var failed: Int { results.filter { $0.outcome == .fail }.count }
    var skipped: Int { results.filter { $0.outcome == .skip }.count }

    func add(_ result: ScenarioResult) {
        results.append(result)
        let label = result.outcome.rawValue.padding(toLength: 4, withPad: " ", startingAt: 0)
        let id = result.id.padding(toLength: 7, withPad: " ", startingAt: 0)
        print("\(label) \(id) \(result.title)")
        for note in result.notes { print("          · \(note)") }
        if let detail = result.detail { print("          → \(detail)") }
    }

    /// Exit-code contract, matching the Android runner:
    /// 0 = pass (a documented SKIP is allowed), 1 = a scenario FAILED,
    /// 2 = preflight aborted / environment unusable.
    var exitCode: Int32 {
        if preflightDiagnosis != nil { return 2 }
        return failed > 0 ? 1 : 0
    }

    func write() {
        var preflight: [String: Any] = ["aborted": preflightDiagnosis != nil]
        if let diagnosis = preflightDiagnosis {
            preflight["diagnosis"] = diagnosis
            if let recipe = preflightRecipe { preflight["recipe"] = recipe }
        }
        let payload: [String: Any] = [
            "baseUrl": e2eBaseURL,
            "apiVersion": e2eAPIVersion,
            "preflight": preflight,
            "summary": [
                "passed": passed, "failed": failed, "skipped": skipped, "total": results.count,
            ],
            "exitCode": Int(exitCode),
            "scenarios": results.map(\.json),
        ]

        let url = URL(fileURLWithPath: e2eReportPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        else {
            print("WARNING: could not serialize the report")
            return
        }
        try? data.write(to: url)
    }

    func printSummary() {
        print("")
        if let diagnosis = preflightDiagnosis {
            print("PREFLIGHT ABORTED — the environment is unusable, not the SDK.")
            print("  \(diagnosis)")
            if let recipe = preflightRecipe { print("  fix: \(recipe)") }
        }
        print(
            "Journey E2E: \(passed) passed, \(failed) failed, \(skipped) skipped "
                + "(\(results.count) total)")
        print("Report: \(e2eReportPath)   (exit \(exitCode))")
        if skipped > 0 {
            print("")
            print(
                "SKIPPED scenarios are NOT failures, but they are also NOT coverage. "
                    + "Before signing off, confirm every SKIP is deliberate:")
            for result in results where result.outcome == .skip {
                print("  \(result.id): \(result.detail ?? "no reason recorded")")
            }
        }
    }
}

let report = E2eReport()

// MARK: - Recording transport

/// Records every outbound request URL while forwarding to the real network.
///
/// Lets a scenario assert that a tracking URL was fired **byte-identical** while still
/// exercising real HTTP, which a mock-only check cannot do. Installed on the SDK's
/// `sessionConfiguration`, so it sees both the decision POSTs and the fire-and-forget
/// tracking GETs — the latter being otherwise unobservable.
///
/// Forwarding uses a session built WITHOUT this protocol class, so a forwarded request cannot
/// re-enter and recurse.
final class RecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _sent: [String] = []

    /// Every URL the SDK put on the wire, in order, exactly as the SDK passed it.
    static var sent: [String] {
        lock.lock(); defer { lock.unlock() }
        return _sent
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        _sent = []
    }

    private static func record(_ url: String) {
        lock.lock(); defer { lock.unlock() }
        _sent.append(url)
    }

    /// Plain session used to actually perform requests. Deliberately does not include
    /// `RecordingURLProtocol` in its `protocolClasses`.
    private static let passthrough: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    // Named `forwardTask` because `URLProtocol` already declares a `task` property.
    private var forwardTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url?.absoluteString { RecordingURLProtocol.record(url) }

        forwardTask = RecordingURLProtocol.passthrough.dataTask(with: request) {
            [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            if let response = response {
                self.client?.urlProtocol(
                    self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data = data { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        forwardTask?.resume()
    }

    override func stopLoading() {
        forwardTask?.cancel()
        forwardTask = nil
    }
}

// MARK: - Driver

/// One SDK instance configured against the local engine, driven through its real public API.
struct Driver {
    var sdk: AdMoai
}

/// Builds a driver over the real public entry point.
///
/// `apiVersion` is passed through so a scenario can prove the version gate by omitting it.
func newDriver(apiVersion: String? = e2eAPIVersion, sessionId: String? = nil) -> Driver {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.protocolClasses = [RecordingURLProtocol.self]

    let sdk = AdMoai(
        config: SDKConfig(
            baseUrl: e2eBaseURL,
            apiVersion: apiVersion,
            defaultLanguage: e2eLanguage,
            sessionConfiguration: configuration
        ),
        sessionId: sessionId
    )
    return Driver(sdk: sdk)
}

// MARK: - Unique ids

private let idLock = NSLock()
private var idCounter = 0

private func nextId() -> Int {
    idLock.lock(); defer { idLock.unlock() }
    idCounter += 1
    return idCounter
}

/// A session id unique to this scenario **and this run**.
///
/// Uniqueness per run is what makes the suite re-runnable with no reseed and no Redis flush:
/// journey runtime-state keys and `fc_journey:` cap keys can never collide across runs.
/// Without it the suite is a one-shot.
func freshSession(_ tag: String) -> String {
    "e2e_\(tag)_\(UInt64(Date().timeIntervalSince1970 * 1_000_000))_\(nextId())"
}

/// A user id unique to this scenario and run — required for the frequency-cap scenarios,
/// whose Redis sorted-set keys are per user + deal.
func freshUser(_ tag: String) -> String {
    "e2e_user_\(tag)_\(UInt64(Date().timeIntervalSince1970 * 1_000_000))_\(nextId())"
}

// MARK: - Decisions

/// The observable result of one `/decision` call.
struct Served {
    let decisions: [Decision]
    let statusCode: Int
    let rawBody: String?

    func decision(for placement: String) -> Decision? {
        decisions.first { $0.placement == placement }
    }

    /// The first creative on `placement`, or `nil` on a no-ad.
    func creative(for placement: String) -> Creative? {
        guard let decision = decision(for: placement), !decision.isNoAd else { return nil }
        return decision.creatives?.first
    }

    func isNoAd(for placement: String) -> Bool {
        guard let decision = decision(for: placement) else { return true }
        return decision.isNoAd
    }
}

/// Issues a decision request through the SDK.
///
/// `configure` receives the builder so a scenario can add a user id or targeting. The
/// parameter is deliberately not named anything that could collide with a builder method: on
/// Android an identically-motivated helper took a lambda named `build`, which bound to the
/// builder's own `build()` inside the receiver scope and silently dropped every caller's
/// `setUserId`/targeting. Requests went out with no user and no targeting, so the frequency
/// cap never applied and targeted deals were excluded — and it looked exactly like an engine
/// bug. Swift has no receiver-lambda scope to shadow, and `S1` proves the forwarding anyway.
func decide(
    _ driver: Driver,
    placements: [String],
    sessionId: String? = nil,
    opt: JourneyOpt? = nil,
    configure: ((DecisionRequestBuilder) throws -> Void)? = nil
) async throws -> Served {
    let builder = driver.sdk.createRequestBuilder()
    for placement in placements { _ = builder.addPlacement(key: placement) }
    if let sessionId = sessionId { _ = builder.setSessionId(sessionId) }
    if let opt = opt { _ = builder.setJourneyOpt(opt) }
    try configure?(builder)

    let response = try await driver.sdk.requestAds(builder.build())
    return Served(
        decisions: response.body.data ?? [],
        statusCode: response.response.statusCode,
        rawBody: response.rawBody
    )
}

// MARK: - Tracking helpers

/// `true` when `url` meets the tracking transport contract: absolute, path `/v1/tracking`,
/// carrying a non-empty opaque `?e=` token.
func isTrackingURL(_ url: String?) -> Bool {
    guard let url = url, let parsed = URL(string: url) else { return false }
    guard let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        return false
    }
    guard parsed.host != nil, parsed.path.hasPrefix("/v1/tracking") else { return false }
    return !(trackingToken(url) ?? "").isEmpty
}

/// Extracts the opaque `e` query parameter without decoding it.
///
/// Read straight off the raw query rather than through `URLComponents.queryItems`, which
/// percent-decodes — the token must be compared as the engine minted it.
func trackingToken(_ url: String) -> String? {
    guard let query = URL(string: url)?.query else { return nil }
    for pair in query.split(separator: "&") where pair.hasPrefix("e=") {
        return String(pair.dropFirst(2))
    }
    return nil
}

/// Rewrites an engine-minted tracking URL onto the configured base URL.
///
/// The local engine mints production-shaped `https://` URLs while serving plaintext on
/// `:8080`, so firing one verbatim fails the TLS handshake locally. That is an environment
/// artifact, not a defect. Scheme, host and port are normalized; the opaque `?e=` token is
/// left untouched — rewriting it would invalidate the very thing under test.
func normalizeForLocalIngestion(_ url: String) -> String {
    guard let minted = URL(string: url), let target = URL(string: e2eBaseURL) else { return url }
    var rebuilt = "\(target.scheme ?? "http")://\(target.host ?? "127.0.0.1")"
    if let port = target.port { rebuilt += ":\(port)" }
    rebuilt += minted.path
    if let query = minted.query { rebuilt += "?\(query)" }
    return rebuilt
}

/// Waits for fire-and-forget tracking to reach the transport.
///
/// Tracking returns void by contract (T3), so there is no completion to await — the runner
/// has to give the dispatched task a moment and then assert on what was recorded.
func waitForFires(_ count: Int, timeout: TimeInterval = 5.0) async -> [String] {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let fired = RecordingURLProtocol.sent.filter { $0.contains("/v1/tracking") }
        if fired.count >= count { return fired }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return RecordingURLProtocol.sent.filter { $0.contains("/v1/tracking") }
}

/// Sleeps for `seconds` of real wall-clock time (used only by the TTL scenarios).
func sleepSeconds(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

// MARK: - Scenario runner

/// Runs one scenario, recording its real PASS/FAIL/SKIP outcome.
///
/// A scenario that throws `SkipScenario` is recorded SKIP and does not fail the run; any other
/// error is a FAIL carrying the message.
func scenario(
    _ id: String,
    _ title: String,
    _ body: (inout [String]) async throws -> Void
) async {
    if let diagnosis = report.preflightDiagnosis {
        report.add(
            ScenarioResult(
                id: id, title: title, outcome: .skip,
                detail: "preflight aborted: \(diagnosis)", notes: []))
        return
    }

    var notes: [String] = []
    do {
        try await body(&notes)
        report.add(ScenarioResult(id: id, title: title, outcome: .pass, detail: nil, notes: notes))
    } catch let skip as SkipScenario {
        report.add(
            ScenarioResult(
                id: id, title: title, outcome: .skip, detail: skip.reason, notes: notes))
    } catch let claim as ClaimFailed {
        report.add(
            ScenarioResult(
                id: id, title: title, outcome: .fail,
                detail: "expected: \(claim.claim)", notes: notes))
    } catch {
        report.add(
            ScenarioResult(
                id: id, title: title, outcome: .fail,
                detail: "\(error)", notes: notes))
    }
}
