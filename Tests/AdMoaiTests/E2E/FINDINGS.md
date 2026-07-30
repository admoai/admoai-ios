# Journey Ads — iOS parity & verification findings

Round completed **2026-07-30** against `admoai-ios@chore/tolerant-response-shell`, reference
implementation `admoai-android@test/journey-sdk-e2e-runner`, cross-checked against the Flutter
round (`admoai-flutter@chore/tolerant-response-shell`), engine `adhub@feat/journey-ads-e02-impl`
running locally.

## Result

| | |
|---|---|
| Static parity (Tier 1) | 1 divergence found and fixed; 1 naming difference resolved without a break |
| Offline suite (Tier 2) | **161 passed**, fully hermetic (`swift test`, ~2 s, live suites skipped) |
| Live E2E (Tier 3) | **37 passed, 0 failed, 0 skipped** — identical across **three consecutive runs with no reseed** |
| Wizard parity (§K) | **PASS, not SKIP** |
| Docs | Journey guide rewritten to all twelve required points; every documented symbol compile-checked |

## Static parity (Tier 1)

Every line of the platform-agnostic contract (R1–R9, P1–P5, T1–T8, C1–C3, N1–N2) was walked
against the source. iOS already satisfied all of it except one item. Notably, four of the five
divergences the Flutter round found were **already correct here**: `fireCompletion` warns without
an `apiVersion` (`Sources/AdMoai/AdMoai.swift:227`), `build()` warns when Journey context is set
without one (`Models/DecisionRequestBuilder.swift:445`), and `fireTracking` already required an
absolute `http(s)` URL with a host (`AdMoai.swift:172`).

### The one divergence — P2, and it was customer-visible

`isJourneyAd` was `journey != nil` (`Sources/AdMoai/Utils/JourneyHelper.swift:10`).

The Tolerant Reader decodes `"journey": {}` — or a block with every field retyped — into a
**non-nil** `CreativeJourney` whose every field is `nil`, because an empty keyed container decodes
fine and each field is `try?` (`Models/DecisionResponse.swift:63,103`). So an ordinary ad carrying
an empty or future-shaped `journey` block reported `isJourneyAd == true` while all thirteen
accessors returned `nil`, and a publisher branching on it would render Journey UI for a normal ad.

Fixed to require a non-blank `dealId` **or** `instanceId`, matching Android
(`JourneyHelper.kt:12`). The README had also stated "Normal ads have `creative.journey == nil`",
which tolerance makes false; corrected.

This is the same defect Flutter found (their D1), reached independently by the same reasoning: the
Tolerant Reader work that made the SDK future-proof is exactly what made a nil-check unsound.

### Naming difference, resolved without a break

Android exposes `fireCustomEvent`; iOS and Flutter shipped `fireCustom`. Flutter made
`fireCustomEvent` canonical with a deprecated alias, which left **iOS as the sole odd one out**.
Resolved here the same way: `fireCustomEvent` is canonical and `fireCustom` remains an
`@available(*, deprecated, renamed:)` forwarding alias, so no existing integration stops
compiling. All three SDKs now agree.

### Deliberate platform idiom, not defects

- Journey accessors are **computed properties** on iOS, **extension functions** in Kotlin,
  **getters** in Dart.
- `AdMoai` is an instance (a `struct` with `mutating` setters); Android's `Admoai` is a singleton.
- iOS warns about missing `apiVersion` at `build()` time rather than in `requestAds`. This is not
  the gap it looks like: `DecisionRequest.init` is internal, so the builder is the only path a
  publisher has, and the warning fires strictly earlier than Flutter's.
- iOS's `URL(string:)`-based firing preserves the server's string **byte-exactly**, including
  lowercase percent-escape hex and literal `+`/`=`. Flutter's `Uri` uppercases escape hex (their
  D5, benign because engine tokens are base64url). iOS needs no equivalent concession.

### Guards verified to bite

Each fix has a guard in `Tests/AdMoaiTests/JourneyParityTests.swift`, and each guard was checked
by reverting its fix individually. A guard that cannot fail is not a guard.

| Reverted | Failures |
|---|---|
| `isJourneyAd` back to `journey != nil` | 3 |
| `fireTracking`'s `http(s)` + host check removed | 1 |
| firing routed through a lossy `URLComponents` rebuild | 2 |
| `X-Decision-Version` no longer set on a decision | 2 |

One honest caveat: a *plain* `URLComponents(url:resolvingAgainstBaseURL:)?.url` round-trip is
lossless on this Foundation, so that particular refactor would not be caught. The guard catches
the lossy variant (rebuilding via `queryItems`), which is the one that actually mangles tokens.

## A pre-existing test-suite defect this work surfaced

`MockURLProtocol` keeps its captured requests and stub in `static` state, because `URLSession`
instantiates a `URLProtocol` itself and cannot be handed per-test context. Swift Testing runs
tests in parallel by default. `JourneyTrackingTests` was `@Suite(.serialized)`, which orders tests
*within* that suite — but does nothing about a sibling suite running alongside it.

Adding a second `MockURLProtocol`-driven suite exposed this immediately: eight failures, all
cross-talk, none of them real. Had the new suite happened not to assert on captures, the race
would have been latent and would have surfaced later as an intermittent CI failure that looks
like an SDK bug.

Fixed structurally rather than worked around: every `MockURLProtocol` consumer is now nested
under one `@Suite(.serialized) struct MockNetworkTests`, whose serialization applies to the whole
subtree (`Tests/AdMoaiTests/Support/MockNetworkTests.swift`). Suites that need no network
inspection use the new stateless `BlackHoleURLProtocol` instead and stay parallel.

## Live E2E verification (Tier 3)

`Tools/JourneyE2E`, an SPM `.executableTarget` (not a package product), driven by
`Tools/journey_e2e.sh`. Report at `build/journey-e2e/report.json`, committed here as
`report.json`.

**An executable target rather than a test target** is the load-bearing choice: `swift test` runs
every test target, so a live suite living there would need an env-var gate — and a mis-set gate
either breaks CI or, worse, silently skips while still reporting green. As an executable, the
hermetic suite stays offline **by construction**, `swift build` still compiles the runner so it
cannot rot, and exit codes 0/1/2 are the process's own.

All 37 scenarios pass. Notable results:

- **§K wizard parity — PASS.** The hand-built `scooter_journey` fixture
  (`jad_01KYSSB2ND61HZFP3KRG9NET3X`, deal id 17) was still present and active, so the
  platform→engine seam is genuinely verified rather than skipped. It serves `pre_ride` on
  `promotions` with exactly the config the wizard wrote (`cpt` / `bill_per_stage` / `final_stage`
  → `summary_ride`), holds one instance across `pre_ride → post_ride`, flips `isCompletion` with
  **no** beacon on `summary_ride`, does not re-serve a served node, and — the #2483 guard —
  **exposes a click URL (`clicks=1`) derived from the wizard's camelCase `urlSlide1..3` fields**.
- **§D6 ingestion — HTTP 202.** The engine accepts a token it minted itself, with only
  scheme/host/port normalized onto the local base URL and the `?e=` token untouched.
- **§H5 completion beacon** — the CPT billing trigger. Exposed, keyed `journey_complete`,
  `isCompletion` stays `false`, and `fireCompletion` dispatches exactly one byte-identical request.
- **§H1/H2 and §K1** assert the **exact** fallback billing mode (`no_charge` for the
  `custom_event` deal, `bill_per_stage` for both `final_stage` deals), not merely a non-blank
  value — a non-blank check passes on any wrong value.
- **§G2** confirms VAST tag/xml expose their payload and surface **zero** VAST-owned video-event
  beacons, so a publisher wiring up both cannot double-count. §G1 confirms the opposite for JSON
  delivery: six beacons exposed (`start`, quartiles, `complete`, `skip`).
- **§S1** proves the runner forwards `setUserId` and targeting to the wire. It exists because the
  Android runner's worst bug was a config-lambda parameter shadowing `build()`, silently dropping
  every caller's user and targeting — which looked exactly like an engine bug.
- **§D2 doubles as a T3 proof.** Locally the engine mints `https://` URLs while serving plaintext,
  so firing one verbatim fails the TLS handshake. The scenario completing at all is evidence that
  fire-and-forget failures never surface to the caller.

### Determinism

Three consecutive runs, no reseed, no Redis flush: identical scenario-by-scenario outcomes
(`37/0/0`, exit `0` each time). Session ids are unique per scenario per run and cap scenarios
additionally use unique user ids, so runtime-state and `fc_journey:` keys can never collide across
runs.

### Exit-code contract verified

Not assumed — exercised:

| Condition | Exit | Diagnosis |
|---|---|---|
| All pass | 0 | — |
| A deliberately impossible claim injected into §S1 | 1 | `FAIL S1`, 36 passed / 1 failed |
| Base URL pointed at a dead port | 2 | "cannot reach the decision-engine … fix: from the adhub root: `make start`" |
| `ADMOAI_JOURNEY_E2E_VERSION=2025-01-01` | 2 | "no journey served … the engine is silently serving normal ads", naming the Statsig gate, Redis, seeds and the version header |

The version-gate case is worth noting: with the wrong version the engine serves ordinary ads with
no error at all. Preflight is what turns that into one line instead of 37 confusing failures.

### Fixture snapshot

The wizard fixture is hand-built and one `make db-reset` from destruction, so it was captured
read-only **first**, before anything else was done, to `Fixtures/wizard_scooter_journey.json`
(rebuild recipe in `Fixtures/README.md`). The snapshot confirms the seam it exists to cover: all
four targeting envelopes are persisted with `"enabled": false` (the #2459 shape), and the creative
content is keyed by camelCase template fields (`destinationUrl`, `urlSlide1..3` — the #2483 shape).

The runner does **not** read the snapshot to make assertions; it asserts against what the SDK
observes from a live engine. The snapshot is documentation of the fixture's shape so a later round
can diff rather than guess.

## The live suite that proved nothing

`JourneyLiveIntegrationTests` hits the hosted `api.mock.admoai.com`, which **still predates the
Journey engine** — confirmed again this round: it rejects `sessionId`/`journeyOpt` with HTTP 400
`unknown field`. Two of its three tests handled that by returning early, so they reported green
while asserting nothing about the Journey contract.

This is a milder form of the Flutter round's central finding (a "live" suite that never made a
network call at all), and the same lesson: **an assertion that never executes is
indistinguishable from one that passes.** iOS's version did at least reach the network — the third
test confirms a normal ad serves and its impression records under `X-Tracking-Version` (2xx).

Fixed without pretending the deploy hold does not exist:

- every early exit now prints `DEPLOYMENT-PENDING: not verified this run — <what>`, naming the
  surface that went unverified, so a green run cannot be silently misread; and
- `ADMOAI_JOURNEY_REQUIRE_DEPLOYED=1` turns every such exit into a hard failure, so once the
  engine ships the suite becomes assertable without editing it. Verified: with the flag set
  against today's host, both Journey tests fail as intended.

The suite's docstring now states plainly that it is not the Journey gate, and points at
`Tools/JourneyE2E` as the thing that actually proves the contract.

## Documentation

The Journey guide was rewritten from ~85 lines covering roughly half the required material to all
twelve required points, most importantly the two most likely to cause a broken integration:

- **the omitted-vs-`optOut` permissive trap.** The old text listed `journeyOpt` as
  ".optIn / .optOut, or omit" with no hint that omitting is permissive. That is the single most
  likely misreading of the whole feature, and it is exactly what invalidated an Android control
  request for a day.
- **that `custom_event` completion only bills if the publisher fires the beacon.**

Defects found while auditing the rest of the README:

- **"The SDK fires tracking beacons via HTTP requests automatically."** It never fires anything
  automatically. Directly contradicted contract rule T4, at the top of the tracking section a
  publisher is most likely to read.
- `fireTracking` was absent from the tracking reference. (`fireCompletion` was present — unlike
  Android and Flutter, where it was missing.)
- Nothing stated that tracking is fire-and-forget and returns `Void`, so a publisher could
  reasonably have tried to branch on a result.
- The response-structure tree omitted `journey` and all five `Tracking` sub-lists, which made
  `completions` — the CPT billing trigger — undiscoverable from the docs. It also typed
  `template`, `metadata`, and `delivery` as non-optional when they are optional.
- No worked examples, no common-mistakes table, no self-checks, no VAST double-count rule, no
  guidance on when to rotate a `sessionId`, and no statement that it is PII and not a user id.

**Not** found on iOS, unlike the other two platforms: no documented API symbol that does not
exist, no wrong builder method names, no duplicated sections, and the published version in the
install snippet (`1.5.0`) already matches `Version.swift`. Reported as verified rather than
inflated into a finding.

Mechanical audit: fences balanced (34), no duplicate headings, every anchor resolves, no broken
relative links. And **every** API symbol the README shows a publisher is now compile-checked by
`Tests/AdMoaiTests/DocumentedAPITests.swift` — verified to bite: renaming `fireCustomEvent` in the
SDK makes the test target fail to compile.

`CHANGELOG.md` is deliberately left to release-please, which generates the 1.5.0 entry from the
conventional commits — so the absence of a 1.5.0 section there is intentional, not a stale doc.

## Out of scope, and why

Owned by adhub's Go service-layer tests — not assertable from any SDK: billing and reporting
interpretation, CPT accounting, completion dedupe and charge counts, decoded tracking-token
identity, Redis runtime-state internals, concurrency and atomicity, mid-flight mutation semantics.

Not SDK-observable at all: **per-node pricing overrides**. The response's `pricingModel` always
comes from the deal default; the override is propagated separately to billing.

Needs seed data before it can be asserted here: **verification / Open Measurement inheritance on
journey serves** (adhub #2383). The SDK models `verificationScriptResources`, but the mock seed
inserts no verification rows, so a live journey serve returns `null` and there is nothing to
assert.

### Follow-ups for this platform (flagged, not faked)

1. **UIKit / SwiftUI lifecycle duplication.** View reappearance, `onAppear` firing twice, `@State`
   re-creation, `Task` restarts, and retries must never duplicate a `/decision`, an impression, or
   a completion. A headless runner cannot drive this; it needs a UI test host. This is the iOS
   analogue of Android's Activity-recreation gap and Flutter's widget-rebuild gap.
2. **Real AVPlayer playback callbacks.** This suite proves the SDK *exposes* delivery data and
   does *not* auto-fire. Proving events fire correctly from an actual player's callbacks needs a
   real player.
3. **§B still depends on the shipped demo journey** on shared demo placements rather than a
   dedicated `sdk_e2e_*` fixture. Preflight diagnoses drift in one line, so this is no longer a
   correctness risk — but a dedicated 3-stage fixture would make the suite fully independent of
   demo data. Requires adhub seed work.
4. **Where the gate runs.** This is a local, manual pre-release check. Making it CI would require
   orchestrating engine + Redis + libSQL + seeds in CI.
5. **The hosted mock still predates the Journey engine.** Until `2025-11-01` deploys there, a
   publisher who sets a `sessionId` or `journeyOpt` against it gets HTTP 400 on *every* request.
   That is the standing reason this branch is held off `main`.

## Unasserted surfaces closed this round

Listed explicitly, because these are the ones that were invisible:

- `isJourneyAd` against a tolerant-decoded empty / retyped / blank-id `journey` block.
- `X-Decision-Version` present on a **journey** decision request. It had been asserted only in
  the live suite — which is gated off by default — and only for a plain request.
- Verbatim firing against a percent-escape-hostile URL, plus the token-alphabet assumption that
  makes it safe.
- `fireTracking`'s URL guard against non-`http(s)` schemes and hostless URLs.
- Every one of the 37 engine-facing scenarios: none of this existed for iOS before this round.
- Whether the "live" suite verified anything at all.
- Whether the documented API surface exists.
