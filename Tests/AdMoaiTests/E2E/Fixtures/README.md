# Wizard-parity fixture — `scooter_journey`

`wizard_scooter_journey.json` is a **read-only snapshot** of the one Journey fixture in
this suite that the Go mock seed did **not** create.

## Why a hand-built fixture exists at all

Every seeded fixture encodes what the **engine expects**, because the same repository
writes both the seed and the reader. So no seeded fixture can ever catch a mismatch
between what the **platform (Ad Manager) writes** and what the **engine reads** — and
both real bugs of the Android rounds lived in exactly that seam, and **both survived a
fully green suite**:

- **adhub #2459** — the wizard always persists a `{"enabled":bool,"payload":{…}}`
  targeting envelope, even when the toggle is off. The engine unwrapped it for
  geo/location/destination but passed `custom_targeting` through raw, so every
  wizard-created journey deal was dropped from every shortlist.
- **adhub #2483** — the platform creates template fields in **camelCase**
  (`destinationUrl`, `urlSlide1..3`) while the click resolver matched a hand-maintained
  **snake_case** list. `tracking.clicks` was `[]` on every journey serve for weeks.

This snapshot confirms both shapes are present in the fixture, so §K genuinely covers
that seam:

- all four targeting envelopes are persisted with `"enabled": false`,
- creative content is keyed by camelCase template fields (`destinationUrl`,
  `urlSlide1..3`, `headlineSlide1..3`, `ctaSlide1..3`).

## The trap

The fixture is authored in the UI, so **`make db-reset` destroys it**. The §K scenarios
then **SKIP** — and the summary still reads "0 failed" and looks green. **Confirm §K is
PASS, not SKIP, before signing off.**

Promoting it to a seed would make it reproducible but would destroy the property that
makes it valuable: it must be written by the platform, not by the seed.

## What the runner does and does not use this for

The runner asserts **only** against what the SDK observes from a live engine. It never
reads this file. The snapshot is documentation of the fixture's shape so a later round
can diff rather than guess.

## Re-capture

Requires the local stack up (libSQL HTTP on `:8081`). Issues `SELECT`s only.

```bash
python3 Tools/dump_wizard_fixture.py > Tests/AdMoaiTests/E2E/Fixtures/wizard_scooter_journey.json
```

## Rebuild recipe (if it is gone)

Captured state, 2026-07-30 — definition `scooter_journey` (id 18), deal
"nike scooter ride" (the deal public id is NOT pinned — every rebuild mints a new ULID):

| Setting | Value |
|---|---|
| Stages (in order) | `pre_ride` → `post_ride` → `summary_ride` |
| Active node placements | `promotions` → `waiting` → `poi` |
| Node templates | `carousel3Slides`, `carousel3Slides`, `imageWithText` |
| Pricing | CPT, value 1100 |
| Fallback billing | `bill_per_stage` |
| Completion | `final_stage` → the **last** stage (`summary_ride`) |
| Targeting | all four toggles **off** (envelopes still persisted) |
| Frequency cap | off |
| Parting | off (`"active": false`) |
| Locale | `en` only |
| Runtime-state TTL | 180 s |
| Deal status | `active`, open-ended flight (no `end_time`) |

Configuration rules that will bite you, learned the hard way:

- **Build the entire stage/node graph before activating any deal.** Activation
  auto-locks the definition (a DB invariant) and structural edits are then rejected.
- The deal must be **active** with a live flight window, and its locale must include the
  locale the runner requests (`en`) — a creative without an `en` variant will not resolve.
- Pick placements **no other active journey deal uses**, or priority masks the fixture.
- Choose a template with a **url-type field**, or there is no click destination to assert
  (that is the whole point of the #2483 guard).
- Leave frequency cap and parting **off** — both make runs non-deterministic (parting is
  wall-clock/timezone dependent).
- Fill **every** creative field, including the click destination URL.

The snapshot also records nodes with `status: "deleted"` on `home`/`menu`/`poi` — an
earlier draft of the same journey. They are inert; leave them out of a rebuild.
