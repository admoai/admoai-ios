# Journey Ads — live E2E runner

Drives the **real** SDK against a **locally-running, seeded decision-engine** and asserts only
what a customer's app can observe: the SDK result and the `/decision` transport.

It exists because unit tests can only prove the SDK parses fixtures *we* wrote. They cannot
prove the SDK and the engine agree — and Journey Ads is the first feature where a *sequence* of
calls behaves differently from a set of unrelated ones, so a silent disagreement means journeys
never progress or completions never bill.

## Running it

```bash
Tools/journey_e2e.sh                                     # recommended
swift run journey-e2e                                    # directly
ADMOAI_JOURNEY_E2E_BASE_URL=http://127.0.0.1:8080 Tools/journey_e2e.sh
```

| Variable | Default |
|---|---|
| `ADMOAI_JOURNEY_E2E_BASE_URL` | `http://127.0.0.1:8080` |
| `ADMOAI_JOURNEY_E2E_VERSION` | `2025-11-01` |

Exit codes: **0** pass (a documented SKIP is allowed) · **1** a scenario FAILED · **2** preflight
aborted, the environment is unusable. Report: `build/journey-e2e/report.json`.

**Engine requirements** (boot is owner-operated — `make start` from the adhub root): reachable
on `X-Decision-Version: 2025-11-01`, Statsig `is_journey_ads_enabled = true` (**default off**),
Redis up, a 32-char `TRACKING_KEY`, mock seeds loaded (they load only into an **empty** DB), and
VAST env vars for §G.

## Why an executable target and not a test target

`swift test` runs every test target in the package, so a live suite living there would have to
be held back by an environment-variable gate — and a gate that is mis-set turns a live suite
into either a broken CI run or, worse, a silently skipped one that still reports green.

As an `.executableTarget` that is deliberately **not** a package product:

- `swift test` stays hermetic and offline **by construction** — it cannot pick this up.
- `swift build` still compiles it, so the runner cannot rot silently against SDK changes.
- Consumers depending on the `AdMoai` library never build it.
- Exit codes 0/1/2 are the process's own, so no report post-processing is needed to recover them.

## Design decisions — copy these, they were earned

Each exists because the naive alternative produced a wrong or useless result.

1. **Black-box only.** SDK result + `/decision` transport. Engine internals — Redis keys,
   decoded token identity, billing dedupe and totals, reporting, concurrency — are **out of
   scope by design** and owned by adhub's Go tests. Asserting them from an SDK is impossible;
   pretending otherwise produces false confidence.
2. **Every no-ad assertion needs a competing normal ad as a positive control.** Without one,
   "no ad" is indistinguishable from "empty placement" and the test proves nothing.
3. **Controls send no session at all.** Omitting `journeyOpt` while sending a session is
   effectively **opt-in**, so such a control starts its own journey, holds the surface, and can
   never serve the competing ad. That mistake cost the Android round a day.
4. **Dedicated placements per fixture.** `sdk_e2e_*` fixtures sit on their own placements so
   priority tie-breaks cannot mask the fixture under test.
5. **A unique session id per scenario per run, and a unique user id for cap scenarios.** This
   is what makes the suite **re-runnable with no reseed and no Redis flush** — runtime-state and
   `fc_journey:` keys can never collide across runs. It is the difference between a usable gate
   and a one-shot.
6. **Missing fixture ⇒ SKIP, not FAIL.** A fixture that was never seeded is an environment
   fact, not a defect. The summary then lists every SKIP, because a SKIP is not coverage.
7. **Environment problems abort in preflight with a precise diagnosis (exit 2)**, not as N
   assertion failures. Preflight checks connectivity (naming `make start` as the fix), that a
   journey serves *at all* (catching gate-off / Redis-down / seeds-missing, which otherwise look
   like normal ads), *and* that the demo placement is owned by the expected definition — that
   last check turns four cryptic failures into one line naming the offending definition.
8. **A machine-readable report**, so a later round can diff scenario-by-scenario after an
   engine change instead of re-reading console output.
9. **A self-check scenario (`S1`) proves the runner forwards user id and targeting.** The
   Android runner's worst bug was a config-lambda parameter shadowing `build()`, silently
   dropping every caller's user and targeting — which looked exactly like an engine bug.

## Scenario groups

| Group | Covers |
|---|---|
| §Self-check | `S1` the runner's own config forwarding, proven on the wire |
| §K wizard parity | `K1`–`K4` the platform-authored fixture — **runs first**, see below |
| §A request forwarding | `A1` no session ⇒ no journey · `A3` wire shape + version header · `A4` sticky/override/clear |
| §B progression | `B1`–`B7` stages, multi-node, repeat ⇒ no-ad, stable instance, metadata coherence |
| §C opt-in/out | `C1` opt-out before start · `C2/C3` opt-out closes, later opt-in mints a NEW instance |
| §D tracking | `D1` transport shape · `D5` click URL · `D2` verbatim + retry-identical · `D4` no-ad fires nothing · `D6` the engine accepts a token it minted |
| §E frequency cap | `E1` deterministic new-entry gating · `E2` the cap never blocks continuation |
| §H CPT/completion | `H1/H2` exact pricing + fallback · `H5` `custom_event` beacon · `H3` `final_stage` inline, no beacon · `H4` takeover ends |
| §J stages/targeting | `J1` mandatory holds · `J5` optional skips · `J2`/`J3`/`J4` targeting both directions |
| §F TTL | `F1` expiry restarts · `F2` a new node refreshes the TTL |
| §G video | `G1` JSON delivery + beacons · `G2` VAST exposes payload, surfaces NO VAST-owned beacons |

## The §K trap — read before signing off

`§K` is driven by `scooter_journey`, built **by hand in the Ad Manager**. That is the whole
point: every other fixture is written by the Go mock seed, which encodes what the engine
*expects*, so no seeded fixture can catch a mismatch between what the platform **writes** and
what the engine **reads**. Both real bugs of the Android rounds (adhub #2459, #2483) lived in
exactly that seam, and **both survived a fully green suite**.

Because it is hand-built, **`make db-reset` destroys it** and `§K` then **SKIPs** — and the
summary still reads "0 failed" and looks green.

**Confirm §K is PASS, not SKIP, before signing off.** Snapshot and rebuild recipe:
`Tests/AdMoaiTests/E2E/Fixtures/README.md`.

## Out of scope

Owned by adhub's Go service-layer tests: billing and reporting interpretation, CPT accounting,
completion dedupe and charge counts, decoded tracking-token identity, Redis runtime-state
internals, concurrency and atomicity, mid-flight mutation semantics.

Not SDK-observable at all: **per-node pricing overrides** — the response's `pricingModel`
always comes from the deal default; the override is propagated separately to billing.

Needs seed data first: **verification / Open Measurement inheritance on journey serves** (adhub
#2383). The SDK models `verificationScriptResources`, but the mock seed inserts no verification
rows, so a live journey serve returns `null` and there is nothing to assert.

Needs a different harness than a headless runner: **UIKit/SwiftUI lifecycle duplication** and
**real AVPlayer playback callbacks**. This suite proves the SDK *exposes* delivery data and does
*not* auto-fire; it cannot drive real playback.

## Local scheme quirk

The engine mints production-shaped `https://` tracking URLs while serving plaintext on `:8080`,
so firing one verbatim fails the TLS handshake **locally**. That is an environment artifact, not
a defect — and it doubles as proof of T3 (fire-and-forget never throws into the caller). `D6`
normalizes scheme/host/port onto the configured base URL and leaves the `?e=` token untouched;
rewriting the token would invalidate the very thing under test.
