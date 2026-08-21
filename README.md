# Admoai iOS SDK


The AdMoai iOS SDK is a lightweight wrapper around the Decision Engine API, enabling iOS applications to request, render, and track native and video advertisements with advanced targeting capabilities.

[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platform-iOS%2014%2B%20%7C%20macOS%2011%2B-blue.svg)](https://developer.apple.com)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)



## Features

- **Native Ads** – Multiple template types (wide, image+text, text-only, carousel)
- **Video Ads** – JSON, VAST Tag, and VAST XML delivery methods
- **Journey Ads** – Single-advertiser experiences spanning a session. Read
  [Journey Ads](#journey-ads) before integrating: it is the one feature that
  requires the same `sessionId` on **every** call
- **Rich Targeting** – Geo, location, and custom key-value targeting
- **Format Filter** – Request native-only, video-only, or any format
- **User Consent** – GDPR compliance with consent management
- **Event Tracking** – Impressions, clicks, video quartiles, and custom events
- **SwiftUI Ready** – Native Swift async/await integration
- **Per-Request Control** – Override user/device data collection per request

## Requirements

- **iOS** 14.0+
- **Swift** 5.9+
- **Xcode** 15.0+

## Installation

### Swift Package Manager

#### Using Xcode UI

In Xcode, go to File > Add Package Dependencies, enter `https://github.com/admoai/admoai-ios.git` in the search field, select version, and click "Add Package".

#### Using Package.swift

Add the following dependency to your `Package.swift`:

<!-- x-release-please-start-version -->
```swift
dependencies: [
    .package(url: "https://github.com/admoai/admoai-ios.git", from: "1.5.0")
]
```
<!-- x-release-please-end-version -->

Then run `swift package resolve` to download and integrate the package.

---

## Quick Start

### 1. Initialize the SDK

```swift

// Initialize SDK with base URL and optional configurations
let config = SDKConfig(
    baseUrl: "https://api.admoai.com",
    apiVersion: "2025-11-01",        // Recommended: gates Journey Ads, video, POI targeting and more
    defaultLanguage: "en"            // Optional: default language for requests
)

var sdk = AdMoai(config: config)
```

### 2. Configure User Settings (Optional)

```swift
sdk.setUserConfig(
    id: "user_123",
    ip: "203.0.113.1",
    timezone: TimeZone.current.identifier,
    consent: User.Consent(gdpr: true)
)

// Device and app info are auto-populated by default
// You can also manually configure them:
sdk.setDeviceConfig(model: "iPhone", os: "iOS", osVersion: "17.0")
sdk.setAppConfig(name: "MyApp", version: "1.0.0")
```

### 3. Build and Send a Request

```swift
let request = sdk.createRequestBuilder()
    .addPlacement(key: "home", format: .native)
    .addPlacement(key: "promotions", format: .video)
    .addGeoTargeting(2643743)  // London
    .addCustomTargeting(key: "category", value: "news")
    .build()

// Request ads (async/await)
let response = try await sdk.requestAds(request)

response.body.data?.forEach { adData in
    adData.creatives?.forEach { creative in
        // Render creative
    }
}
```

### 4. Extract Content

```swift
let headline = creative.contents.getContent(key: "headline")?.value.description
let posterImage = creative.contents.getContent(key: "poster_image")?.value.description
let videoAsset = creative.contents.getContent(key: "video_asset")?.value.description
```

### 5. Track Events

```swift
// Impressions
sdk.fireImpression(tracking: creative.tracking)

// Clicks
sdk.fireClick(tracking: creative.tracking)

// Video quartiles
sdk.fireVideoEvent(tracking: creative.tracking, key: "start")           // 0%
sdk.fireVideoEvent(tracking: creative.tracking, key: "first_quartile")  // 25%
sdk.fireVideoEvent(tracking: creative.tracking, key: "midpoint")        // 50%
sdk.fireVideoEvent(tracking: creative.tracking, key: "third_quartile")  // 75%
sdk.fireVideoEvent(tracking: creative.tracking, key: "complete")        // 98%
sdk.fireVideoEvent(tracking: creative.tracking, key: "skip")            // on skip

// Custom events
sdk.fireCustomEvent(tracking: creative.tracking, key: "companionOpened")
```

The SDK never fires anything on its own — every beacon above fires only when you call it.

`fireClick` **records** the click. It does not navigate, and it returns nothing to open — sending
the user somewhere is a separate step your app owns. See [Handling an ad click](#handling-an-ad-click).

### 6. Clean Up on Logout

```swift
sdk.clearUserConfig()
sdk.clearDeviceConfig()
sdk.clearAppConfig()
```

---

## Configuration Reference

### SDKConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `baseUrl` | String | Required | Decision Engine API endpoint |
| `apiVersion` | String? | `nil` | Engine API version. `"2025-11-01"` gates Journey Ads, video ads, POI / destination targeting, mid-flight campaign changes, Open Measurement and the format filter |
| `defaultLanguage` | String? | `nil` | Default language for requests |
| `logger` | Logger | SDK default | Custom logger instance |
| `sessionConfiguration` | URLSessionConfiguration | SDK default | Custom URL session configuration |

### Format

| Value | Description |
|-------|-------------|
| `.native` | Request native ads only |
| `.video` | Request video ads only |
| `nil` | Request any format (default, recommended) |

> **Note**: Format filter requires `apiVersion = "2025-11-01"` or later.

---

## Video Ad Support

The SDK supports three video delivery methods:

| Delivery | Response Field | Tracking |
|----------|----------------|----------|
| **JSON** | `video_asset` content key | SDK methods (`fireVideoEvent`) |
| **VAST Tag** | `vast.tagUrl` | IMA SDK automatic or manual HTTP |
| **VAST XML** | `vast.xmlBase64` | Manual HTTP GET |

### Detecting Video Ads

```swift
// Check delivery method
let isVideo = creative.delivery == "json" || 
              creative.delivery == "vast_tag" || 
              creative.delivery == "vast_xml"

// Or use helper methods
creative.isJsonDelivery()
creative.isVastTagDelivery()
creative.isVastXmlDelivery()

// Get video URL (JSON delivery)
let videoUrl = creative.contents.getContent(key: "video_asset")?.value.description

// Get VAST tag URL (with optional media type/delivery params)
let vastTagUrl = creative.getVastTagUrl()
let vastTagUrlWithParams = creative.getVastTagUrl(mediaType: "video/mp4", mediaDelivery: "progressive")

// Get VAST XML (Base64 encoded, with optional modifications)
let vastXmlBase64 = creative.getVastXmlBase64()
let vastXmlModified = creative.getVastXmlBase64(mediaType: "video/mp4", mediaDelivery: "streaming")
```


## Journey Ads

A **Journey Ad** is a single-advertiser experience that follows one user across several
screens of a session (e.g. pre-ride → in-ride → post-ride), sold as one commercial deal. Instead
of an independent decision per placement, one advertiser holds the journey: the engine walks the
user through an ordered set of **stages**, keeps progress server-side, and suppresses competing
ads on the placements it owns until the journey ends.

> **Read this section before integrating.** Journey Ads is the first Admoai feature where a
> *sequence* of calls behaves differently from a set of unrelated ones, so it is the first that
> puts an obligation on **every** call: carry the same `sessionId` for the whole of a user's
> session. The SDK cannot do that for you. Get it wrong and journeys silently never progress.

**Minimum engine version:** set `SDKConfig.apiVersion = "2025-11-01"`. Without it the engine
**silently** ignores Journey fields and serves ordinary ads — no error, no warning from the
server — and Journey completion tracking will not record.

`2025-11-01` is not only about Journey Ads. It gates several capabilities, so unless you have a
specific reason not to, set it: **Journey Ads**, **video ads**, **POI / destination targeting**,
**mid-flight campaign changes**, **Open Measurement** support, and the **format filter**.

<!-- MIRRORED SECTION START — this Journey Ads guide is duplicated in admoai-ios, admoai-android
     (sdk/README.md) and admoai-flutter. Prose must stay equivalent in all three; only the code
     samples differ. Change all three together. -->

### Why your integration matters commercially

A Journey Ad is **one advertiser buying one user's activity as a single deal**, usually priced
**CPT** (cost per trip) — the advertiser pays once for the whole journey, not per impression. In
exchange, competing ads are suppressed on the placements the journey owns.

That moves real commercial weight into your app:

| If your app… | Consequence |
|---|---|
| Sends a different `sessionId` per screen | The journey restarts at stage 1 forever. The advertiser's multi-screen story never happens and the campaign under-delivers. |
| Never fires the completion beacon (on `custom_event` deals) | The journey never completes, so **CPT revenue is never recorded**. |
| Fills a journey-owned slot with a different advertiser's ad when the journey returns no ad | Breaks the single-brand exclusivity the advertiser paid for. |
| Uses journey metadata (stage keys, node ids) to drive app logic or layout | Breaks silently the moment someone edits the campaign. |

**None of this raises an error at request time.** Requests succeed, ads appear, and the problem
only shows up later in reporting — which is why the checklist and the checks at the end of this
section matter more than usual.

### What the SDK does, and never does

| The SDK does | The SDK never does |
|---|---|
| Forwards your `sessionId` and `journeyOpt` on the request | Generate, rotate, or persist a `sessionId` |
| Exposes read-only Journey metadata off the served creative | Run a journey state machine or infer the current stage |
| Fires the exact tracking URLs the engine returned, verbatim, when you call it | Fire anything automatically, or rebuild/parse a tracking URL |
| Reports a no-ad faithfully | Substitute another ad when a journey withholds one |

Everything else is **server-owned**: eligibility, which stage serves next, the
`journeyInstanceId`, takeover protection, frequency capping, runtime-state TTL, completion, and
billing. If you find yourself writing journey logic in your app, something has gone wrong.

### The one rule: the same session id on every call

```swift
let config = SDKConfig(baseUrl: "https://api.admoai.com", apiVersion: "2025-11-01")

// One sticky, publisher-owned session id, inherited by every request builder.
var sdk = AdMoai(config: config, sessionId: "trip-9f3c-2025")
```

Two ways to get this wrong, both of which fail quietly:

| Mistake | What happens |
|---|---|
| A **different** `sessionId` per screen | Every call looks like a new session, so the journey restarts at stage 1 forever and never progresses. |
| **No** `sessionId` at all | Journeys never activate. Ordinary ads keep serving — a safe default, but the feature is simply off. |

### What a session actually is

The most common mistake is reaching for something identity-shaped — a login, a user id, an app
launch. **A session is one activity, not one user and not one app run.** Define it as the thing
that starts and finishes in your product, because that is the unit the advertiser is buying.

Examples, **not prescriptions** — pick the equivalent in your own product:

| Product | One `sessionId` = | Starts | Ends |
|---|---|---|---|
| Ride-hailing | one ride | user opens the booking flow | ride completed or cancelled |
| Delivery | one order | checkout begins | order delivered |
| Micromobility | one trip | unlock | lock / trip ends |

Two consequences worth internalising:

- **Login is usually the wrong boundary.** A user who takes three rides today should produce
  three `sessionId` values, not one — otherwise all three collapse into a single journey.
- **Concurrent activities need separate ids.** If your product allows two live orders at once,
  give each its own `sessionId` (a per-request override is the simplest way). One id for both
  makes them share one journey and one stage pointer.

### The `sessionId` contract

- **You own it.** The SDK never generates, rotates, or persists it. It is whatever your app uses
  to mean "one activity" — see above.
- **It is sticky.** The value on `AdMoai` is inherited by every builder from
  `createRequestBuilder()`, and rebuilding never mints a new one.
- **It can be overridden per request**, and cleared per request, without disturbing the sticky
  value:
  ```swift
  let request = sdk.createRequestBuilder()
      .addPlacement(key: "home")
      .setSessionId("just-this-request")   // overrides for this request only
      // .clearSessionId()                 // or omits it for this request only
      .build()
  ```
- **Rotate it when a new business session begins** — app launch after a real break, login,
  logout, or when the activity the journey describes has ended (the trip finished, the order was
  delivered). Rotating is explicit:
  ```swift
  sdk.setSessionId("trip-a17d-2025")
  ```
- **Do not rotate it per screen, per request, or on every app foreground.** That is the first
  failure mode above.
- **Limits:** trimmed before sending; blank becomes absent; must be ≤ **256 UTF-8 bytes**. An
  over-long or blank value silently disables Journey while the request still succeeds as a
  normal ad. The SDK logs a PII-safe reason token only — never the value.
- **It is PII and it is not a user id.** Do not put an email, phone number, or account id in it.
  Use an opaque, rotating value.

### `journeyOpt` — three states, and the trap

```swift
let request = sdk.createRequestBuilder()
    .addPlacement(key: "home")
    .setJourneyOpt(.optIn)     // or .optOut, or omit entirely
    .build()
```

| State | Wire value | Meaning |
|---|---|---|
| `.optIn` | `"in"` | Journeys may serve. |
| `.optOut` | `"out"` | Journeys are suppressed, and an active journey is **ended**. |
| omitted | *(absent)* | **Permissive** — journeys may serve, and an active journey continues. |

> **The single most likely misreading:** omitting `journeyOpt` is **not** the same as
> `.optOut`. Omitting it is permissive and behaves much like opting in. If you mean "no
> journeys for this user", you must send `.optOut` explicitly. Sending a `sessionId` with
> `journeyOpt` omitted is enough to start a journey.

**Opt-out ends rather than pauses.** It closes the active instance; it does not suspend it.
Opting back in later starts a **new** journey with a new `journeyInstanceId` — the previous one
never resumes. A journey that has **completed** is likewise terminal.

> **The exception to "omitted is permissive".** Once a session has explicitly opted out, that
> refusal is remembered. Later requests that simply **omit** `journeyOpt` do **not** re-enable
> journeys for it — the session must **re-consent with an explicit `.optIn`**. So if you wire a
> consent toggle, sending `.optOut` when it is off and *nothing* when it is on will leave journeys
> permanently disabled for that session. Send `.optIn` explicitly when the user opts back in.

### Reading Journey metadata (read-only)

```swift
if creative.isJourneyAd {
    let dealId          = creative.journeyDealId
    let instanceId      = creative.journeyInstanceId       // constant for one journey
    let definitionKey   = creative.journeyDefinitionKey
    let stageId         = creative.journeyStageId
    let stageKey        = creative.journeyStageKey
    let stageNodeId     = creative.journeyStageNodeId
    let sessionId       = creative.journeySessionId        // echoed back by the engine
    let optStatus       = creative.journeyOptStatus        // .optIn / .optOut / nil (unknown)
    let pricing         = creative.journeyPricingModel     // e.g. "cpt"
    let fallbackBilling = creative.journeyFallbackBillingMode
    let isCompletion    = creative.isJourneyCompletion
    let hasBeacon       = creative.hasCompletionUrl
}
```

On an ordinary ad every one of these is `nil` / `false` — never a crash, never a default object.
Unknown, missing, or wrong-typed fields from a future engine version decode to `nil` rather than
throwing.

`creative.metadata?.impId` carries the **render-level attribution key**, minted per served creative
and present on every Journey serve (`nil` on normal ads). Use it to reconcile a specific render
against reporting. It is not a substitute for the tracking token — the encrypted `e=` token stays
authoritative server-side — and the SDK derives nothing from it. `metadata` also carries
`skipOffsetSeconds` and `endCardMode` for video creatives.

> **Do not branch your UI on stage keys or node ids.** They are engine-owned identifiers that
> can change when someone edits the campaign, and your app will not be redeployed when they do.
> Render from `contents` and `template`, exactly as you do for a normal ad.

### Completion — two mutually exclusive modes

Which of the two applies is **configured per campaign in the Ad Manager** by Admoai ad-ops; the
engine reads that configuration and applies it in the ad response. You do not choose, but you must
handle both, and they are **additive** to the normal impression, never a replacement.

**`custom_event`** — the creative carries a completion beacon. **Completion, and therefore CPT
revenue, is recorded only when you fire it.** If you never fire it, the journey never bills.

> **Do not hard-code the completion key.** The key is **campaign-specific** — it is the event name
> the Admoai ad operator configured for this deal, so it differs between campaigns and is not a
> fixed string you can rely on. Read it from `creative.tracking.completions`, which carries exactly
> one entry when the deal uses `custom_event`. Passing a key that is not in that list logs a
> warning and fires **nothing** — no error, no completion, no revenue.

```swift
// Read the key the engine returned; never invent it locally.
if let completion = creative.tracking.completions?.first {
    // Fire ONCE, when the action the deal is paying for actually happens
    // (ride booked, order placed) — not on render.
    sdk.fireCompletion(tracking: creative.tracking, key: completion.key)
}
```

Which **app action** should trigger it is a commercial decision, not something the SDK can tell
you. Get it from your Admoai contact before you ship — see [Before you ship](#before-you-ship).

**`final_stage`** — the engine marks completion itself, at decision time. There is **nothing to
fire**.

```swift
if creative.isJourneyCompletion {
    // Already recorded server-side. Fire only the normal impression.
}
```

`isJourneyCompletion` and `hasCompletionUrl` are mutually exclusive. Completion is **idempotent
server-side**, so firing twice will not double-charge the advertiser — but still fire **once**:
repeated callbacks add confusing analytics rows and make debugging harder. Fire the normal
impression in both modes; the completion beacon is additional, never a replacement.

### No-ad is correct behaviour, not a failure

A placement a journey owns may return **no ad** rather than a competing brand. That is takeover
protection working.

```swift
if decision.isNoAd {
    // Collapse the slot. Render nothing, or your own non-ad UI. Fire no tracking.
}
```

- **Do not** substitute another ad or fall back to a different network on that surface.
- **Do not** immediately retry the same placement in a loop. Collapse the slot and carry on;
  request again when your app naturally reaches its next ad opportunity. A later request may well
  serve — the answer depends on placement, stage, time and campaign state.
- `decision.isNoAd` is `true` for takeover-protected empties *and* ordinary no-fill. The
  distinction is deliberate server-side detail the SDK does not expose, and treating them
  differently is not something your app can or should do.

See [Why a journey can stop serving](#why-a-journey-can-stop-serving) for the reasons behind a
no-ad — worth reading before reporting one as an SDK bug.

### Worked example 1 — one session across three screens

```swift
final class AdSession {
    // One id for the whole trip, rotated only when a new trip begins.
    private var sdk = AdMoai(
        config: SDKConfig(baseUrl: "https://api.admoai.com", apiVersion: "2025-11-01"),
        sessionId: "trip-\(UUID().uuidString)"
    )

    func newTrip() {
        sdk.setSessionId("trip-\(UUID().uuidString)")
    }

    func ad(for placement: String) async throws -> Creative? {
        // No setSessionId here — the sticky value is inherited, which is the point.
        let request = sdk.createRequestBuilder()
            .addPlacement(key: placement)
            .setJourneyOpt(.optIn)
            .build()
        let creative = try await sdk.requestAds(request).body.data?.first?.creatives?.first

        if let creative = creative {
            sdk.fireImpression(tracking: creative.tracking)
            if creative.hasCompletionUrl, tripFinished {
                sdk.fireCompletion(tracking: creative.tracking, key: "journey_complete")
            }
        }
        return creative
    }

    private var tripFinished = false
}

// vehicleSelection → journey → rideSummary all share one sessionId, so the engine can
// advance the journey one stage at a time.
```

### Worked example 2 — personalisation opt-out

The user has turned off personalised advertising, but you still want to serve ordinary ads.

```swift
let opt: JourneyOpt = userAllowsPersonalisation ? .optIn : .optOut

let request = sdk.createRequestBuilder()
    .addPlacement(key: "home")
    .setJourneyOpt(opt)   // NOT "omit it" — omitting is permissive
    .build()
```

Under `.optOut` the engine serves normal, non-journey ads and closes any active journey. If the
user turns personalisation back on, the next `.optIn` starts a **new** journey.

### Video: the VAST double-count rule

For `vast_tag` and `vast_xml` delivery, the impression, quartile, and click beacons live **inside
the VAST document** and belong to your player. The SDK surfaces the VAST payload and
deliberately exposes **no** video-event beacons for these modes.

```swift
if creative.isVastTagDelivery() || creative.isVastXmlDelivery() {
    // Hand creative.getVastTagUrl() / getVastXmlBase64() to your player.
    // Do NOT also call fireVideoEvent — the player's own beacons already cover it.
}
if creative.isJsonDelivery() {
    // JSON delivery is the opposite: the engine owns the beacons, so you must fire them.
    sdk.fireVideoEvent(tracking: creative.tracking, key: "start")
}
```

### Common mistakes

| Mistake | Consequence | Do this instead |
|---|---|---|
| A new `sessionId` per screen or per request | The journey restarts at stage 1 forever and never progresses | One id per activity, rotated only when the activity ends |
| Reusing a user id, account id or login as the `sessionId` | Every activity by that user collapses into a single journey | Mint an opaque id per activity |
| No `sessionId` at all | Journeys never activate; the feature is silently off (ordinary ads still serve) | Set it once via `AdMoai(config:sessionId:)` |
| Omitting `journeyOpt` to mean "no journeys" | Permissive — journeys still serve, and an active one continues | Send `.optOut` explicitly |
| Expecting opt-out to pause a journey | The instance is **closed**; a later opt-in starts a brand-new one | Treat opt-out as terminal |
| Sending `.optOut`, then omitting `journeyOpt` to re-enable | A stored opt-out persists, so journeys stay off for that session | Send `.optIn` explicitly to re-consent |
| Missing or older `apiVersion` | Journey fields are ignored silently, and completions do not record | Set `2025-11-01` |
| Not firing the `custom_event` completion beacon | The journey never completes and CPT never bills | Fire it once when the agreed action happens |
| Hard-coding the completion key | The key is campaign-specific; a wrong key fires **nothing** and only logs a warning | Read it from `creative.tracking``.completions` |
| Firing a completion on a `final_stage` deal | Nothing to fire; the call is a no-op | Check `isJourneyCompletion` and fire only the impression |
| Firing the completion on render instead of on the action | Completions and CPT revenue are reported for journeys that never delivered the outcome | Fire on the real user action |
| Filling a journey-owned slot with another ad when the journey returns no ad | Breaks the single-brand takeover the advertiser paid for | Collapse the slot |
| Immediately re-requesting the same placement in a loop after a no-ad | Wasted calls; a placement the journey is holding will not free up mid-loop | Collapse, then request again at your next natural ad opportunity |
| Treating a repeated `journeyStageKey` as a bug | One stage can own several surfaces, so it legitimately repeats | Use `journeyStageNodeId` for the no-repeat rule |
| Using journey metadata to drive app logic or layout | Breaks silently the moment someone edits the campaign | Render from `contents` / `template` |
| Rebuilding or appending to a tracking URL | Invalidates the encrypted token; attribution is lost | Fire the string verbatim |
| Firing SDK video events for VAST delivery | Every event counts twice | Let the player's VAST beacons do it |

### Two self-checks that catch most integration bugs

**1. The instance id must stay constant across one session.**

```swift
if let instance = creative.journeyInstanceId {
    print("journey instance: \(instance)")   // must be IDENTICAL on every screen of a session
}
```
If it changes between screens, your `sessionId` is changing when it should not.

**2. The stage NODE id must never repeat within one instance.**

```swift
print("stage: \(creative.journeyStageKey ?? "none")  node: \(creative.journeyStageNodeId ?? "none")")
```

- **`journeyStageNodeId` must not repeat** while the same `journeyInstanceId` is active. Each node
  serves at most once per journey. A repeat means something is being re-requested unexpectedly.
- **`journeyStageKey` MAY repeat** — that is not a bug. One stage can own several surfaces, and the
  engine will serve another unserved node from a stage it has already served without advancing.
  Do not treat a repeated stage key as an error.
- What *is* a red flag: the stage key stuck on the **first** stage across a whole session with a
  **changing instance id** — that means every call is starting a new journey, i.e. a `sessionId`
  problem.

### How long a journey stays alive

A journey's server-side progress has an **idle expiry**, configured by the Admoai ad operator **per
journey definition** — not per campaign, and not by your app. It defaults to **24 hours** and can be
set to anything from minutes to days.

Two things follow, and the second surprises people:

- **The clock runs from the last activity, not from the start.** Every serve refreshes it, so an
  active journey does not expire mid-use.
- **After the idle window, the journey is gone — even if your `sessionId` never changed.** The next
  request starts a **new** journey at stage 1 with a new `journeyInstanceId`. An unchanged
  `sessionId` is not enough to keep a journey alive.

Pick the window to match how long your activity realistically pauses. *As an example only:* a
delivery product whose orders complete within a couple of hours has no reason to keep state for a
day. Agree the value with your Admoai contact — there is no universally correct number.

### Why a journey can stop serving

**Frequency capping** decides whether a **new** journey may start. It is set per deal by Admoai
ad-ops, as "X times per Y period". There is **no default — if it is not configured, no cap
applies.** Two properties matter to you:

- It **never interrupts a journey already in progress.** A cap filling up mid-journey cannot cut
  the user off.
- It is scoped per **user + deal**, so it only applies when you send a **user id**. Without one,
  journey frequency capping cannot apply.

**Edge cases — uncommon, but they explain a journey that stops mid-session.** An active journey can
end early if the deal's **budget** runs out, its **pacing** limit is reached, an **event cap** is
hit, or it falls outside its **parting** window (the times of day and days of week the campaign is
allowed to serve). Add the idle expiry above, a **mandatory stage** with nothing servable on the
requested placement, and an explicit **opt-out**, and you have the full list.

Your app's response is identical in every case: collapse the slot and carry on. The distinction
only matters when someone asks ad-ops why delivery stopped.

### How your integration shows up in reporting

Journey reporting is computed from the events your app fires and the session boundaries you chose,
so these numbers are only as good as the integration. What a publisher and an advertiser will be
looking at:

| Metric | What it is | What your app affects |
|---|---|---|
| **Journeys started** | How many journeys began | Your session boundaries. A `sessionId` per screen inflates this; one per login collapses many activities into one. |
| **Completions** | Journeys that reached the finish | Firing the completion beacon on `custom_event` deals. Ad-ops chooses which stages must be served for a journey to count as finished — any combination — and that is reconciled against billing. |
| **Avg duration** | Average time between a journey's first and last event | Whether the journey actually progresses. A restarting journey reports many short ones instead of one real one. |
| **Avg attention time** | Estimated time the ad was on screen: average duration × an attention percentage set on the **journey definition** | Same as duration. This is **estimated from configuration, not measured viewability** — it is not Open Measurement and never affects billing. |
| **CTR** | Clicks ÷ impressions, counted per event | Firing impressions and clicks. |
| **Journey CTR** | Journeys clicked at least once ÷ journeys started | Each journey counts **once** however many times it was clicked, and completion is irrelevant. It reads **higher** than CTR because a journey spans several placements — that is expected, not a bug. |

### Before you ship

**Get these from your Admoai contact.** Guessing any of them produces an integration that looks
fine and reports wrongly:

| What | Why you need it |
|---|---|
| Placement keys owned by the journey | Which of your surfaces participate |
| The billable app action | Which real user action fires completion |
| Completion mode (`custom_event` or `final_stage`) | Whether you fire anything at all |
| Idle expiry for the definition | How long a paused activity survives |
| Video delivery mode (JSON or VAST) | Who owns the video beacons |
| Whether a user id is expected | Frequency capping needs one |

**Then check your own integration:**

- [ ] `apiVersion = "2025-11-01"` is set.
- [ ] One `sessionId` per **activity** (see [What a session actually is](#what-a-session-actually-is)), not per screen and not per login.
- [ ] `journeyInstanceId` is constant across one activity; `journeyStageNodeId` never repeats.
- [ ] Completion key is read from `creative.tracking.completions`, never hard-coded.
- [ ] Completion fires **once**, on the agreed action — not on render.
- [ ] Normal impression still fires on journey serves.
- [ ] A journey no-ad collapses the slot; no substitute ad, no retry loop.
- [ ] Consent toggle sends an explicit `.optIn` to re-enable, not an omitted field.
- [ ] Nothing fires automatically; VAST beacons left to the player.
- [ ] UI renders from `contents` / `template`, never from journey metadata.

### Glossary

For product and ops readers.

| Term | Meaning |
|---|---|
| **Journey** | One advertiser's multi-screen experience across a single user activity. |
| **Journey definition** | The reusable template: ordered stages, and the idle-expiry setting. |
| **Journey deal** | A campaign bought against a definition: pricing, budget, caps, flight dates. |
| **Instance** (`journeyInstanceId`) | One concrete run of a deal for one session. The unit reporting and billing reconcile on. |
| **Stage** | One ordered step of a journey. May own several surfaces. |
| **Stage node** | One placement + template within a stage. Serves at most once per instance. |
| **Takeover protection** | Suppression of competing ads on placements a journey owns. |
| **CPT** | Cost per trip — the advertiser pays once per journey, not per impression. |
| **Completion** | The moment the journey is considered fulfilled; what CPT bills on. |
| **Parting** | The times of day / days of week a campaign may serve. |
| **Pacing** | Spreading delivery over the flight instead of spending at once. |

### Questions publishers ask

**We do not implement `sessionId` at all. Can we still request ads?**
Yes. Everything works exactly as before — only Journey Ads are ineligible. Journeys never activate,
ordinary ads keep serving. It is a valid, safe default.

**Is `apiVersion` only about Journey Ads?**
No. `2025-11-01` also gates video ads, the format filter, mid-flight campaign changes and Open
Measurement support. Journey Ads are one of several reasons to set it — set it unless you have a
specific reason not to.

**Two users share a device. Same `sessionId`?**
No. A session is one activity by one user. On account switch, rotate it.

**The app was killed mid-activity. Reuse the id or rotate?**
Reuse it if the activity is still the same one — that is the whole point of it being yours to
persist. Rotate only when the activity itself ends.

**Our `sessionId` never changed, but the journey restarted at stage 1. Why?**
Almost certainly the idle expiry — see
[How long a journey stays alive](#how-long-a-journey-stays-alive).

**How do we tell the completion beacon apart from our own template custom events?**
They are separate lists. Your template's events are in `tracking.custom` and unchanged. The journey
completion beacon is the single entry in `tracking.completions`, fired with `fireCompletion`.

**We fired the completion twice. Did we double-charge the advertiser?**
No — completion is idempotent server-side. Still fire once; duplicates only clutter analytics.

**We never fire it. What happens?**
On a `custom_event` deal the journey never completes and **CPT revenue is never recorded**. Nothing
errors. This is the most expensive mistake on this page.

**The user opted out, then we stopped sending `journeyOpt`. Why no journeys?**
A stored opt-out is remembered and an omitted field does not clear it. Send an explicit `.optIn`.

**A journey stopped serving mid-session and we never opted out.**
See [Why a journey can stop serving](#why-a-journey-can-stop-serving).

<!-- MIRRORED SECTION END -->

---

## Sample App

For a complete example implementation, check out the [demo app](Examples/Demo/README.md).

---

## Event Tracking

**The SDK never fires a beacon automatically.** Every tracking call below happens only when your
app makes it — the SDK has no view lifecycle hooks, no visibility detection, and no player
integration. Firing at the right moment is the publisher's responsibility.

All tracking methods are **fire-and-forget**: they return `Void`, dispatch on the SDK's own
session, and never throw into the caller. Failures are logged, not surfaced — so there is no
return value to branch on and nothing to `await`.

The URLs are opaque (`…/v1/tracking?e=<encrypted token>`) and are fired **verbatim**. Never
parse, rebuild, or append to them: the attribution identity lives inside the token.

### Available Methods

```swift
// Impressions (fire when the ad is actually displayed)
sdk.fireImpression(tracking: trackingInfo, key: "default")

// Clicks (fire on user tap)
sdk.fireClick(tracking: trackingInfo, key: "default")

// Video events (JSON delivery only — for VAST the player owns the beacons)
sdk.fireVideoEvent(tracking: trackingInfo, key: "start")

// Custom events
sdk.fireCustomEvent(tracking: trackingInfo, key: "companionOpened")

// Journey completion (custom_event completion deals only — see Journey Ads)
sdk.fireCompletion(tracking: trackingInfo, key: "journey_complete")

// Escape hatch: fire a server-provided URL directly, when you already hold the string
sdk.fireTracking(url: someServerProvidedUrl)
```

> `fireCustom(tracking:key:)` is the former name of `fireCustomEvent(tracking:key:)`. It still
> works but is deprecated; all three Admoai SDKs now use `fireCustomEvent`.

### Handling an ad click

A tap on an ad is **two independent actions**, and your app performs both:

```swift
// The tracking key and the destination key travel together: they are both per-template, and
// for a carousel both are per-slide ("slide2" pairs with "urlSlide2"). See the table below.
func handleAdClick(creative: Creative, trackingKey: String, destinationKey: String) {
    // 1. Record the click — once.
    sdk.fireClick(tracking: creative.tracking, key: trackingKey)

    // 2. Navigate, separately: the destination is a content field of the creative.
    guard let raw = creative.contents.getContent(key: destinationKey)?.value.description,
        let url = URL(string: raw), let scheme = url.scheme?.lowercased()
    else { return }  // no destination is a normal case — the click is already recorded

    if scheme == "http" || scheme == "https" {
        UIApplication.shared.open(url)   // external web page
    } else {
        router.handle(url)               // your own scheme — keep it in-app
    }
}
```

**Never navigate to a tracking URL.** `tracking.clicks[].url` is a measurement endpoint. It
happens to answer with a redirect, which makes "just open the click URL" look like it works —
until it doesn't:

| | Tracker URL (`tracking.clicks[].url`) | Destination (creative content field) |
|---|---|---|
| Purpose | Records that a click happened | Where the user should land |
| Shape | `…/v1/tracking?e=<encrypted token>` | The advertiser's own URL |
| Who calls it | `sdk.fireClick(...)`, once | Your app, once |

Opening the tracker yourself **on top of** calling `fireClick` counts the click twice and inflates
the campaign's numbers. And if you hand that URL to a deeplink router or an in-app browser, what
your app receives is an opaque tracking token, not the advertiser's page.

#### Destination keys, per template

Content keys match **verbatim** — `getContent(key:)` does no case folding, so `destinationURL`
finds nothing when the template declares `destinationUrl`.

| Template | Destination key |
|---|---|
| `standard`, `imageWithText`, `wideImageOnly`, Journey | `destinationUrl` |
| `wideWithCompanion` (companion CTA) | `clickThroughUrl` |
| `carousel3Slides` | `urlSlide1`, `urlSlide2`, `urlSlide3` |
| video templates (companion end card) | `companionDestinationUrl` |
| `textOnly` | *none — the template declares no destination* |

For a carousel, pair each slide's tracking key with **that same slide's** destination: tapping
slide 2 fires `slide2` and opens `urlSlide2`.

A template with no destination, or a creative that omits the field, is a normal case rather than
an error: fire the click tracker as usual and stay where you are.

`textOnly` goes one step further — it declares no destination **and** its creatives carry no
clicks tracker, so `fireClick` has nothing to send either. A tap on it is a complete no-op. Keep
the handler wired anyway: whether a tracker exists is per-creative, not per-template, and
`fireClick` is safe to call when there is none.

#### Same-app deeplinks

Check the scheme before you open anything. `http`/`https` belongs to the system browser; your own
scheme belongs to your router — passing it to `UIApplication.shared.open` sends your user out of
the app and back in, losing the navigation state you already had.

See `Examples/Demo/Demo/ClickHandling/AdClickResolver.swift` for a worked implementation.

### Tracking Keys

Each tracking type supports multiple keys. Use `"default"` for standard events, or the custom
keys defined in your campaign configuration. A key that does not exist fires nothing — it is a
safe no-op, not an error.

---

### Video Tracking Events

**Important**: Always fire the **impression** event first when the ad is displayed, then fire video-specific events as playback progresses.

| Event | When to Fire | Key |
|-------|--------------|-----|
| **Impression** | Ad displayed (before playback) | `default` |
| Start | Video begins playing (0%) | `start` |
| First Quartile | 25% progress | `first_quartile` |
| Midpoint | 50% progress | `midpoint` |
| Third Quartile | 75% progress | `third_quartile` |
| Complete | Video ends (98%) | `complete` |
| Skip | User skips | `skip` |

**Manual tracking** works with any delivery method:

```swift
// 1. Fire impression first (when ad is displayed)
sdk.fireImpression(tracking: creative.tracking)

// 2. Fire video events as playback progresses
sdk.fireVideoEvent(tracking: creative.tracking, key: "start")
sdk.fireVideoEvent(tracking: creative.tracking, key: "first_quartile")
sdk.fireVideoEvent(tracking: creative.tracking, key: "midpoint")
sdk.fireVideoEvent(tracking: creative.tracking, key: "third_quartile")
sdk.fireVideoEvent(tracking: creative.tracking, key: "complete")
sdk.fireVideoEvent(tracking: creative.tracking, key: "skip")  // if user skips
```

- **JSON delivery**: Tracking URLs are in the response—easiest to use with SDK methods
- **VAST Tag/XML**: Requires fetching the tag URL or decoding Base64 XML to extract tracking URLs, then firing HTTP GET beacons manually

> **Note**: Admoai is OM-compatible and passes verification metadata through VAST `<AdVerifications>` tags. See the [Open Measurement Integration](#open-measurement-integration) section below for implementation guidance.

### Video Helper Methods

```swift
// Skippable ad detection
let isSkippable = creative.isSkippable()
let skipOffset = creative.getSkipOffset()  // String?, e.g. "5" or "00:00:05"
```

Both read the engine-owned `creative.metadata` first (`metadata?.isSkippable`,
`metadata?.skipOffsetSeconds`), then fall back to the creative's content fields — accepting either
`is_skippable`/`skip_offset` or the camelCase spellings, because the template field names are
author-controlled. For a typed value read `creative.metadata?.skipOffsetSeconds` (`Int?`) directly;
`getSkipOffset()` returns a `String?` for backwards compatibility.

---

## Request Builder

The `DecisionRequestBuilder` provides a fluent API:

```swift
let request = sdk.createRequestBuilder()
    // Placements
    .addPlacement(key: "home")
    .addPlacement(key: "promotions", format: .video)
    
    // User overrides (per-request)
    .setUserId("user_123")
    .setUserIp("203.0.113.1")
    .setUserTimezone("America/New_York")
    .setUserConsent(User.Consent(gdpr: true))
    
    // Targeting
    .addGeoTargeting(2643743)
    .addLocationTargeting(latitude: 37.7749, longitude: -122.4194)
    .addCustomTargeting(key: "category", value: "news")
    
    // Data collection
    .disableAppCollection()
    .disableDeviceCollection()
    
    .build()
```

`clearAll()` resets a builder for reuse: it drops placements, targeting and user, stops automatic
app and device collection, and clears `journeyOpt`. It deliberately **keeps** the sticky
`sessionId` — that is session-scoped state, not per-request state, so a journey survives a builder
reset. Call `clearSessionId()` to drop it explicitly.

---

## Response Structure

```
APIResponse<DecisionResponse>
├── response: HTTPURLResponse
├── body: APIResponseBody<DecisionResponse>
│   ├── success: Bool
│   ├── data: [Decision]?
│   │   └── Decision
│   │       ├── placement: String
│   │       └── creatives: [Creative]?
│   │           └── Creative
│   │               ├── contents: [Content]         // Key-value pairs
│   │               ├── advertiser: Advertiser
│   │               ├── template: Template?         // {key, style}
│   │               ├── tracking: Tracking
│   │               │   ├── impressions: [TrackingItem]?
│   │               │   ├── clicks: [TrackingItem]?
│   │               │   ├── custom: [TrackingItem]?
│   │               │   ├── videoEvents: [TrackingItem]?   // JSON delivery only
│   │               │   └── completions: [TrackingItem]?   // Journey custom_event deals only
│   │               ├── metadata: Metadata?
│   │               ├── delivery: String?           // "json", "vast_tag", "vast_xml"
│   │               ├── vast: VastData?             // {tagUrl} or {xmlBase64}
│   │               ├── journey: CreativeJourney?   // Journey serves only — see Journey Ads
│   │               └── verificationScriptResources: [VerificationScriptResource]?  // OM verification data
│   ├── errors: [AdMoaiError]?
│   └── warnings: [AdMoaiWarning]?
└── rawBody: String?
```

---

## Default Configuration Helpers

Auto-populate device and app information:

```swift
// Reset to system defaults (auto-detected)
sdk.resetDeviceConfig()  // Device info (model, OS, manufacturer, etc.)
sdk.resetAppConfig()     // App info (name, version, identifier, etc.)

// Clear all config
sdk.clearDeviceConfig()
sdk.clearAppConfig()
```

---

## Thread Safety

The SDK is designed for concurrent use:

- Configuration changes are handled through struct value semantics
- All network calls use async/await with proper concurrency
- URLSession handles connection pooling automatically

---

## Open Measurement Integration

Admoai is **OM-compatible** and passes Open Measurement verification metadata through VAST `<AdVerifications>` tags. This section explains how publishers can implement Open Measurement viewability and verification measurement in their apps.

### Roles and Responsibilities

**What Admoai does:**
- Acts as a strict ad server / decision engine
- Includes `<AdVerifications>` tags in VAST responses
- Provides verification metadata via SDK helper methods
- Documents OM integration patterns

**What Admoai does NOT do:**
- Ship an OM SDK or namespaced OM build
- Act as the "OM integration partner" in the trust chain
- Provide IAB OM certification

**What you (the Publisher) must do:**
- Own the OM integration in your app
- Obtain and use your own IAB namespace
- Integrate the IAB OM SDK or OM-compatible video player
- Manage OM session lifecycle (create, start, track events, finish)

> **Important**: Admoai stays out of the OM trust chain. Your app is the OM integration partner and uses your own IAB namespace for all measurements.

---

### Do I Need My Own IAB Namespace?

**Short answer:** No namespace = verification still works, but the SDK owns OM. Namespace = you own OM.

**Detailed explanation:**

You do **not** need your own IAB OM namespace if you use an OM-certified SDK like Google IMA (Path B). In that case, verification vendors (IAS, DoubleVerify, Moat, etc.) will still receive all required measurement data, but the OM integration partner will be the SDK provider (e.g., Google), not your app.

Creating your own IAB OM namespace is **only required** if you want to implement Open Measurement directly (e.g., using AVPlayer as shown in Path A) and retain full control and ownership of the OM session lifecycle. This gives you complete flexibility over the video player UI and behavior.

**In summary:**
- **Path A (Native OM SDK)**: Requires your own IAB namespace → You own the OM integration
- **Path B (Google IMA SDK)**: No namespace needed → Google owns the OM integration
- **Path C (JW Player)**: No namespace needed → JW Player owns the OM integration

> If you choose Path A and want full control, proceed to Step 1 below. If you choose Path B or C, skip to their respective implementation sections.

---

### Step 1: Get Your IAB Namespace (Path A Only)

If you're implementing Path A (Native OM SDK), you need to obtain your own namespaced OM SDK from IAB Tech Lab:

1. **Visit the IAB Tech Lab website**: Go to [https://iabtechlab.com/standards/open-measurement-sdk/](https://iabtechlab.com/standards/open-measurement-sdk/)
2. **Click "Download OM SDK"**: This will take you to the compliance portal
3. **Sign in or register**: Create an account if you don't have one already
4. **Navigate to "Open Measurement SDK" section**: Find the SDK download area in your account dashboard
5. **Add a namespace**: Create a unique namespace identifier for your organization (e.g., `com.yourcompany-omid`)
   - Use a simple, recognizable name that represents your organization
   - This namespace identifies you as the OM integration partner
6. **Click "Build iOS"**: Generate the iOS SDK with your namespace
7. **Download from iOS tab**: Download the framework (e.g., `OMSDK_Yournamespace.xcframework`)
8. **Add to your Xcode project**: Drag the framework into your project and ensure it's embedded

> **Critical**: Your namespace will follow you throughout the OM trust chain. All verification vendors (IAS, DoubleVerify, Moat, etc.) will see your namespace as the OM integration partner, not Admoai.

---

### Step 2: Choose Your Implementation Path

Admoai is OM-compatible and works with any OM integration approach. We recommend the Native OM SDK for maximum flexibility, but you have multiple options:

| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| **Path A: Native OM SDK** (Recommended) | Full control, better UX, custom UI | More engineering effort | Publishers wanting complete control over video UX |
| **Path B: Google IMA SDK** | OM handled automatically, less code | Less control, IMA watermarks | Publishers prioritizing speed over customization |
| **Path C: JW Player** | Commercial support, OM built-in | License cost, vendor lock-in | Publishers wanting commercial-grade video player with support |

---

### Path A: Native OM SDK Integration (Recommended for Best UX)

Use this approach for full control over video playback and custom UI.

#### 1. Add the IAB OM SDK to your project

After downloading the namespaced OM SDK framework from IAB:

1. Drag `OMSDK_Yournamespace.xcframework` into your Xcode project
2. Ensure it's added to your target's "Frameworks, Libraries, and Embedded Content"
3. Set the framework to "Embed & Sign"

#### 2. Extract verification resources from Admoai

```swift
import AdMoai
import OMSDK_Yournamespace  // Your IAB namespace

// Get creative from Admoai SDK
if let creative = response.body.data?.first?.creatives?.first {
    // Check if OM verification is available
    if creative.hasOMVerification() {
        let verificationResources = creative.getVerificationResources()
        // Proceed with OM session creation
    }
}
```

#### 3. Create and start OM session

```swift
import AVFoundation
import OMSDK_Yournamespace

class VideoAdPlayer {
    
    private var omAdSession: OMIDAdSession?
    private var omAdEvents: OMIDAdEvents?
    private var omMediaEvents: OMIDMediaEvents?
    
    func setupOMSession(creative: Creative, playerView: UIView) {
        guard creative.hasOMVerification() else { return }
        
        // 1. Activate OM SDK (once per app lifecycle)
        OMIDSDK.activate()
        
        // 2. Create Partner (your company info)
        guard let partner = OMIDPartner(name: "YourCompany", versionString: "1.0.0") else {
            return
        }
        
        // 3. Extract verification scripts from Admoai
        guard let verificationResources = creative.getVerificationResources() else {
            return
        }
        
        var verificationScripts: [OMIDVerificationScriptResource] = []
        for resource in verificationResources {
            if let url = URL(string: resource.scriptUrl),
               let script = OMIDVerificationScriptResource(
                   url: url,
                   vendorKey: resource.vendorKey,
                   parameters: resource.verificationParameters
               ) {
                verificationScripts.append(script)
            }
        }
        
        // 4. Create AdSessionContext
        guard let context = try? OMIDAdSessionContext(
            partner: partner,
            script: OMIDSDK.shared().scriptContent,
            resources: verificationScripts,
            contentUrl: nil,
            customReferenceIdentifier: nil
        ) else {
            return
        }
        
        // 5. Create AdSessionConfiguration
        let config = OMIDAdSessionConfiguration(
            creativeType: .video,
            impressionType: .beginToRender,
            impressionOwner: .nativeOwner,
            mediaEventsOwner: .nativeOwner,
            isolateVerificationScripts: false
        )
        
        // 6. Create AdSession
        guard let session = try? OMIDAdSession(configuration: config, adSessionContext: context) else {
            return
        }
        omAdSession = session
        
        // 7. Register video view
        omAdSession?.mainAdView = playerView
        
        // 8. Create event trackers
        omAdEvents = try? OMIDAdEvents(adSession: session)
        omMediaEvents = try? OMIDMediaEvents(adSession: session)
        
        // 9. Start session
        try? omAdSession?.start()
        
        // 10. Fire loaded event
        let vastProperties = OMIDVASTProperties(
            autoPlay: true,
            position: .standalone
        )
        try? omAdEvents?.loaded(with: vastProperties)
    }
    
    func onVideoStarted(duration: TimeInterval, volume: Float) {
        try? omMediaEvents?.start(duration: duration, mediaPlayerVolume: volume)
        try? omAdEvents?.impressionOccurred()
    }
    
    func onVideoProgress(currentTime: TimeInterval, duration: TimeInterval) {
        let progress = currentTime / duration
        
        if progress >= 0.25 && !firstQuartileFired {
            try? omMediaEvents?.firstQuartile()
            firstQuartileFired = true
        } else if progress >= 0.5 && !midpointFired {
            try? omMediaEvents?.midpoint()
            midpointFired = true
        } else if progress >= 0.75 && !thirdQuartileFired {
            try? omMediaEvents?.thirdQuartile()
            thirdQuartileFired = true
        }
    }
    
    func onVideoCompleted() {
        try? omMediaEvents?.complete()
        omAdSession?.finish()
    }
    
    func onVideoSkipped() {
        try? omMediaEvents?.skipped()
        omAdSession?.finish()
    }
    
    func cleanup() {
        omAdSession?.finish()
        omAdSession = nil
        omAdEvents = nil
        omMediaEvents = nil
    }
    
    private var firstQuartileFired = false
    private var midpointFired = false
    private var thirdQuartileFired = false
}
```

#### 4. Integrate with AVPlayer

```swift
import AVFoundation
import UIKit

class VideoAdViewController: UIViewController {
    
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var videoAdPlayer: VideoAdPlayer?
    private var timeObserver: Any?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Get creative from Admoai SDK
        guard let creative = getCreativeFromAdmoai() else { return }
        
        // Setup video URL (VAST or JSON delivery)
        let videoUrl: URL?
        
        if creative.isVastTagDelivery() {
            // Fetch and parse VAST XML to get MediaFile URL
            videoUrl = fetchVastAndExtractMediaUrl(creative.vast?.tagUrl)
        } else if creative.isVastXmlDelivery() {
            // Decode Base64 VAST XML and extract MediaFile URL
            videoUrl = parseVastXmlAndExtractMediaUrl(creative.vast?.xmlBase64)
        } else {
            // JSON delivery: direct video URL
            if let urlString = creative.contents.getContent(key: "video_asset")?.value.description {
                videoUrl = URL(string: urlString)
            } else {
                videoUrl = nil
            }
        }
        
        guard let url = videoUrl else { return }
        
        // Setup AVPlayer
        player = AVPlayer(url: url)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = view.bounds
        playerLayer?.videoGravity = .resizeAspect
        
        if let layer = playerLayer {
            view.layer.addSublayer(layer)
        }
        
        // Setup OM session
        videoAdPlayer = VideoAdPlayer()
        videoAdPlayer?.setupOMSession(creative: creative, playerView: view)
        
        // Observe playback state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem
        )
        
        // Track video progress
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self = self,
                  let duration = self.player?.currentItem?.duration else { return }
            
            let currentTime = CMTimeGetSeconds(time)
            let totalDuration = CMTimeGetSeconds(duration)
            
            if currentTime > 0 && !self.hasStarted {
                self.videoAdPlayer?.onVideoStarted(duration: totalDuration, volume: 1.0)
                self.hasStarted = true
            }
            
            self.videoAdPlayer?.onVideoProgress(currentTime: currentTime, duration: totalDuration)
        }
        
        // Start playback
        player?.play()
    }
    
    @objc private func playerDidFinishPlaying() {
        videoAdPlayer?.onVideoCompleted()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        videoAdPlayer?.cleanup()
        player?.pause()
    }
    
    private var hasStarted = false
}
```

---

### Path B: Google IMA SDK (Convenience Path)

Use this approach if you want OM handled automatically with less code, at the cost of less UI control.

#### 1. Add dependencies

```swift
// Using CocoaPods - add to your Podfile:
pod 'GoogleAds-IMA-iOS-SDK', '~> 3.19'

// Or using Swift Package Manager:
dependencies: [
    .package(url: "https://github.com/googleads/swift-package-manager-google-interactive-media-ads-ios.git", from: "3.19.0")
]
```

#### 2. Setup IMA with OM support

```swift
import UIKit
import GoogleInteractiveMediaAds
import AVFoundation

class VideoAdViewController: UIViewController {
    
    private var adsLoader: IMAAdsLoader?
    private var adsManager: IMAAdsManager?
    private var contentPlayer: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Get creative from Admoai SDK
        guard let creative = getCreativeFromAdmoai() else { return }
        
        // Setup content player
        setupContentPlayer()
        
        // Setup IMA with OM enabled
        let settings = IMASettings()
        settings.enableOMIDSupport = true  // Enable OM in IMA
        
        adsLoader = IMAAdsLoader(settings: settings)
        adsLoader?.delegate = self
        
        // Get VAST tag URL from Admoai creative
        guard let vastTagUrl = creative.vast?.tagUrl else { return }
        
        // Request ads
        let request = IMAAdsRequest(
            adTagUrl: vastTagUrl,
            adDisplayContainer: IMAAdDisplayContainer(
                adContainer: view,
                viewController: self
            ),
            contentPlayhead: nil,
            userContext: nil
        )
        
        adsLoader?.requestAds(with: request)
    }
    
    private func setupContentPlayer() {
        contentPlayer = AVPlayer()
        playerLayer = AVPlayerLayer(player: contentPlayer)
        playerLayer?.frame = view.bounds
        
        if let layer = playerLayer {
            view.layer.addSublayer(layer)
        }
    }
}

extension VideoAdViewController: IMAAdsLoaderDelegate {
    func adsLoader(_ loader: IMAAdsLoader, adsLoadedWith adsLoadedData: IMAAdsLoadedData) {
        adsManager = adsLoadedData.adsManager
        adsManager?.delegate = self
        adsManager?.initialize(with: nil)
    }
    
    func adsLoader(_ loader: IMAAdsLoader, failedWith adErrorData: IMAAdLoadingErrorData) {
        print("Ad loading failed: \(adErrorData.adError.message ?? "")")
        contentPlayer?.play()
    }
}

extension VideoAdViewController: IMAAdsManagerDelegate {
    func adsManager(_ adsManager: IMAAdsManager, didReceive event: IMAAdEvent) {
        switch event.type {
        case .LOADED:
            adsManager.start()
        case .COMPLETE, .SKIPPED:
            contentPlayer?.play()
        default:
            break
        }
    }
    
    func adsManager(_ adsManager: IMAAdsManager, didReceive error: IMAAdError) {
        print("Ad error: \(error.message ?? "")")
        contentPlayer?.play()
    }
}
```

> **Note on Google IMA**: Google IMA automatically handles OM session creation when `enableOMIDSupport = true` and VAST includes `<AdVerifications>` tags. However, you get less control over UI (IMA shows watermarks, "Learn More" buttons, and default skip buttons). For custom video UX, use Path A.

---

### Accessing Admoai's Verification Metadata

Regardless of which path you choose, Admoai provides helper methods to access OM verification data:

```swift
// Check if creative has OM verification
if creative.hasOMVerification() {
    let resources = creative.getVerificationResources()
    
    resources?.forEach { resource in
        print("Vendor: \(resource.vendorKey)")           // e.g., "company.com-omid"
        print("Script URL: \(resource.scriptUrl)")       // e.g., "https://verification.ias.com/..."
        print("Parameters: \(resource.verificationParameters)")  // e.g., "anId=123&advId=789"
    }
}
```

#### VerificationScriptResource Properties

| Property | Type | Description |
|----------|------|-------------|
| `vendorKey` | String | Vendor identifier (e.g., "ias", "doubleverify", "moat") |
| `scriptUrl` | String | URL to verification JavaScript that OM SDK will load |
| `verificationParameters` | String | Query parameters for verification session |

---

### VAST `<AdVerifications>` Handling

When you use VAST Tag or VAST XML delivery, Admoai includes `<AdVerifications>` in the VAST response:

```xml
<VAST version="4.2">
  <Ad>
    <InLine>
      <AdVerifications>
        <Verification vendor="company.com-omid">
          <JavaScriptResource apiFramework="omid" browserOptional="true">
            <![CDATA[https://verification.ias.com/omid_verification.js]]>
          </JavaScriptResource>
          <VerificationParameters>
            <![CDATA[anId=123&advId=789&creativeId=456]]>
          </VerificationParameters>
        </Verification>
      </AdVerifications>
      <!-- Linear creative, tracking, media files, etc. -->
    </InLine>
  </Ad>
</VAST>
```

- **Path A (Native OM SDK)**: Parse VAST yourself, extract `<AdVerifications>`, map to OM SDK `OMIDVerificationScriptResource` objects
- **Path B (Google IMA SDK)**: IMA automatically parses `<AdVerifications>` and creates OM sessions

---

### Testing Your OM Integration

**Use OM SDK validation**: The IAB OM SDK includes validation modes to verify your integration

---

### Summary

- **Admoai is OM-compatible**: We pass verification metadata via VAST `<AdVerifications>` and SDK helpers
- **Publishers own OM integration**: Publisher's app is the OM integration partner with your own IAB namespace
- **Three paths available**: Native OM SDK (full control), Google IMA SDK (convenience), or JW Player (commercial)
- **Admoai stays out of the trust chain**: We're a strict ad server; you're responsible for OM implementation

---

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details on:

- How to submit Pull Requests
- Commit message conventions (Conventional Commits)
- Code style and testing requirements
- Development workflow

## Documentation

For detailed documentation, please visit:
- [API Documentation](https://docs.admoai.com)

---

## Support

- **Email**: support@admoai.com

---

## License

Copyright 2025 Admoai Inc. All rights reserved.
