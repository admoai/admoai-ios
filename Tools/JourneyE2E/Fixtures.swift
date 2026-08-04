import Foundation

// Fixture coordinates.
//
// Every value here is a fact about the seeded decision-engine, not a preference. They are
// grouped in one file so a seed change has exactly one place to land.

// MARK: - The shipped demo journey

// §B is bound to this rather than a dedicated `sdk_e2e_*` placement, which is why preflight
// proves its ownership before anything runs: unrelated engine QA once left a UI-created
// journey owning `vehicleSelection`, which read as four SDK regressions.
let demoDefinition = "ride_hailing_journey"
let demoStage1Placement = "vehicleSelection"  // pre_ride, node 1
let demoStage1PlacementB = "search"  // pre_ride, node 2 (multi-node)
let demoStage2Placement = "journey"  // in_ride
let demoStage3Placement = "rideSummary"  // post_ride
let demoStage1Key = "pre_ride"
let demoStage2Key = "in_ride"
let demoStage3Key = "post_ride"

// MARK: - Dedicated seeded fixtures

// Each lives on its own `sdk_e2e_*` placement so priority tie-breaks can never mask the
// fixture under test.

let multiNodePlacements = [
    "sdk_e2e_multinode_a",
    "sdk_e2e_multinode_b",
    "sdk_e2e_multinode_c",
]

/// CPT deal with `custom_event` completion (`journey_complete` beacon) and fallback
/// `no_charge`. Its `standard` template carries a `destinationUrl`, so it also drives the
/// click-URL guard.
let cptCustomEventPlacement = "sdk_e2e_cpt_completion"
let cptCustomEventKey = "journey_complete"

/// Exact seeded values. Asserting the precise fallback mode matters: a non-blank check passes
/// on any wrong value, which is how a wrong billing mode ships unnoticed.
let cptPricingModel = "cpt"
let cptCustomEventFallback = "no_charge"
let cptFinalStageFallback = "bill_per_stage"

/// CPT deal with `final_stage` completion pointing at the "complete" stage.
let cptFinalEarlyPlacement = "sdk_e2e_cpt_final_early"
let cptFinalCompletePlacement = "sdk_e2e_cpt_final_complete"

/// Frequency-capped journey: cap = 2 new instances per day, with a second node in the stage
/// so continuation can be told apart from admission.
let freqCapPlacement = "sdk_e2e_frequency_cap"
let freqCapLaterPlacement = "sdk_e2e_frequency_cap_later"
let freqCapAmount = 2

/// Two-stage journey whose FIRST stage is `mandatory`.
let mandatoryEarlyPlacement = "sdk_e2e_mandatory_early"
let mandatoryLaterPlacement = "sdk_e2e_mandatory_later"

/// Two OPTIONAL stages on distinct placements — the contrast case to the mandatory hold.
let optSkipEarlyPlacement = "sdk_e2e_optskip_early"
let optSkipLaterPlacement = "sdk_e2e_optskip_later"

// MARK: - Targeting fixtures (NYC, 5000 m inclusive radius)

let targetGeoPlacement = "sdk_e2e_target_geo"
let targetLocationPlacement = "sdk_e2e_target_location"
let targetDestinationPlacement = "sdk_e2e_target_destination"
let nycLatitude = 40.7128
let nycLongitude = -74.006
let nycGeonameId = 5128581

/// A REAL geoname that simply does not match. `geoname_id = 1` is absent from the engine's
/// geoname set entirely, which makes the engine ERROR rather than cleanly not-match — so a
/// negative targeting case must use a real value.
let londonGeonameId = 2643743
let londonLatitude = 51.5074
let londonLongitude = -0.1278

/// The deal's `dest_min_confidence`. A request at or above it matches.
let destinationThreshold = 0.7

// MARK: - TTL

/// Journeys seeded with `runtime_state_ttl_seconds = 5`, applied verbatim as a Redis `EX`.
/// Short enough to wait out in a test.
let shortTtlPlacement = "sdk_e2e_short_ttl"
let shortTtlSeconds = 5.0

// MARK: - Video (one placement per delivery mode)

let videoJsonPlacement = "sdk_e2e_video_json"
let videoVastTagPlacement = "sdk_e2e_video_vast_tag"
let videoVastXmlPlacement = "sdk_e2e_video_vast_xml"

// MARK: - The hand-built wizard fixture (§K)

// Authored in the Ad Manager UI, NOT seeded, so `make db-reset` destroys it and §K then
// SKIPs. Snapshot and rebuild recipe: Tests/AdMoaiTests/E2E/Fixtures/README.md.
let wizardDefinition = "scooter_journey"
/// Public-id prefix for a Journey deal. §K deliberately asserts the SHAPE of the deal id, not a
/// literal value: the fixture is authored in the UI and destroyed by `make db-reset`, so every
/// rebuild mints a fresh ULID. Pinning one made the scenario fail on the first legitimate rebuild
/// while the fixture itself was correct — the identity that actually matters is
/// `wizardDefinition`, which the publisher controls and which is asserted alongside this.
let wizardDealPrefix = "jad_"
let wizardStage1 = "pre_ride"
let wizardStage2 = "post_ride"
let wizardStage3 = "summary_ride"
let wizardPlacement1 = "promotions"
let wizardPlacement2 = "waiting"
let wizardPlacement3 = "poi"
