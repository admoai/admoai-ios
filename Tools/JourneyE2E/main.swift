import AdMoai
import Foundation

// Journey Ads — live, SDK-driven E2E runner (iOS/Swift).
//
// Drives the **real** SDK against a **locally-running, seeded decision-engine** and asserts
// only what a customer's app can observe: the SDK result and the `/decision` transport. It is
// the Swift counterpart of the Android `JourneyE2eRunner` and the Flutter `journey_e2e_test`,
// and exists because unit tests can only prove the SDK parses fixtures we wrote ourselves —
// they cannot prove the SDK and the engine agree.
//
// NOT part of the hermetic gate. It is an executable target rather than a test target, so
// `swift test` stays offline and deterministic *by construction* rather than by an env-var
// gate that could be mis-set. Run it with:
//
//   Tools/journey_e2e.sh                      # wrapper: prints and forwards the exit code
//   swift run journey-e2e                     # directly
//
// Environment:
//   ADMOAI_JOURNEY_E2E_BASE_URL  default http://127.0.0.1:8080
//   ADMOAI_JOURNEY_E2E_VERSION   default 2025-11-01
//
// Requires: Statsig gate `is_journey_ads_enabled = true` (default OFF), Redis up, a 32-char
// TRACKING_KEY, mock seeds loaded into an empty DB, and VAST env vars for the video scenarios.
// Preflight proves the environment before asserting anything, so a broken environment is one
// diagnosis instead of N failures.
//
// See Tools/JourneyE2E/README.md for the design decisions and the SKIP-vs-FAIL contract.

// MARK: - Preflight

// Prove the environment is what we think it is.
//
// Android learned this the hard way: four scenarios "failed" for weeks of engine drift because
// local QA had left the demo deals inactive and a UI-created journey owned the shared
// placement. Not a regression. A preflight that names the offending definition turns four
// cryptic failures into one line.
func runPreflight() async {
    do {
        let driver = newDriver()

        // 1. Connectivity and version routing.
        let probe: Served
        do {
            probe = try await decide(driver, placements: [demoStage1Placement])
        } catch APIError.networkError(let underlying) {
            // The overwhelmingly most common failure, and the one whose fix is a single
            // command. Distinguished from "reachable but refusing" below because the two need
            // completely different actions.
            throw PreflightAbort(
                "cannot reach the decision-engine at \(e2eBaseURL) "
                    + "(\(underlying.localizedDescription))",
                recipe: "from the adhub root: `make start`")
        } catch {
            // Reachable but refusing the request — a different problem entirely, and one that
            // would otherwise read as "engine down".
            throw PreflightAbort(
                "the engine rejected a plain decision request: \(error)",
                recipe: "check the engine logs and that the seeded placement "
                    + "\"\(demoStage1Placement)\" exists in this database")
        }
        guard probe.statusCode == 200 else {
            throw PreflightAbort(
                "engine returned HTTP \(probe.statusCode) for a plain decision",
                recipe: "check the engine logs; `make start` from the adhub root")
        }

        // 2. Do journeys serve at all? Catches the Statsig gate being off, Redis being down,
        //    and seeds never having loaded — all of which make the engine silently serve normal
        //    ads with no error to notice.
        let journeyProbe = try await decide(
            driver, placements: [demoStage1Placement],
            sessionId: freshSession("preflight"), opt: .optIn)
        guard let creative = journeyProbe.creative(for: demoStage1Placement),
            creative.isJourneyAd
        else {
            throw PreflightAbort(
                "no journey served on \"\(demoStage1Placement)\" with a fresh session and "
                    + "journeyOpt=in — the engine is silently serving normal ads",
                recipe: "check: Statsig `is_journey_ads_enabled = true` (default OFF), Redis up, "
                    + "mock seeds loaded (they load only into an EMPTY db), and "
                    + "X-Decision-Version = \(e2eAPIVersion)")
        }

        // 3. Is the demo placement owned by the definition we expect? A UI-created journey
        //    holding it makes §B unrunnable in a way that looks like an SDK or engine regression.
        let owner = creative.journeyDefinitionKey
        guard owner == demoDefinition else {
            throw PreflightAbort(
                "\"\(demoStage1Placement)\" is owned by definition \"\(owner ?? "nil")\", "
                    + "expected \"\(demoDefinition)\" — local platform data is not a clean mock seed",
                recipe: "WARNING: `make db-reset` from the adhub root fixes this but DESTROYS "
                    + "all locally-created platform data, including the hand-built §K wizard "
                    + "fixture. Deactivate the offending journey deal in the Ad Manager instead "
                    + "if you need §K to keep passing.")
        }

        print(
            "preflight OK — journeys serve, \"\(demoStage1Placement)\" owned by "
                + "\"\(demoDefinition)\"")
        print("")
    } catch let abort as PreflightAbort {
        report.preflightDiagnosis = abort.diagnosis
        report.preflightRecipe = abort.recipe
        print("PREFLIGHT ABORT: \(abort.diagnosis)")
        if let recipe = abort.recipe { print("  fix: \(recipe)") }
        print("")
    } catch {
        report.preflightDiagnosis = "preflight itself failed: \(error)"
        print("PREFLIGHT ABORT: \(report.preflightDiagnosis!)")
        print("")
    }
}

// MARK: - Run

print("Journey E2E → \(e2eBaseURL)  (X-Decision-Version: \(e2eAPIVersion))")
print("")

await runPreflight()

// Guards the runner's own config forwarding before any scenario relies on it.
await selfCheckGroup()

// §K first, deliberately: it is the only platform-authored fixture, it cannot be recreated
// from code, and one `make db-reset` destroys it.
await wizardParityGroup()

await requestForwardingGroup()
await progressionGroup()
await optGroup()
await trackingGroup()
await frequencyCapGroup()
await completionGroup()
await targetingGroup()

// Shared cross-SDK manifest: normal ads, placement options, video delivery, the error
// contract and API-version regression. Defined once in scenarios.json and executed
// identically by all three SDKs — see ManifestRunner.swift.
await manifestGroup()
await wireShapeGroup()

// Last: the most setup-heavy groups. §F spends real wall-clock waiting out a 5-second
// runtime-state TTL.
await ttlGroup()
await videoGroup()

report.write()
report.printSummary()
exit(report.exitCode)
