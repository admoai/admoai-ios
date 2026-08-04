import AdMoai
import Foundation

// §D tracking transport, §E frequency cap, §H CPT/completion, §J mandatory/optional +
// targeting, §F runtime-state TTL, §G video delivery.

// MARK: - §D tracking transport (black-box)

// Identity lives inside the encrypted `?e=` token, which is server-owned. The SDK must not,
// and does not, parse it — so these assertions are about transport shape and byte-exact
// firing, never about token contents.

/// Serves the dedicated CPT fixture, whose `standard` template carries a `destinationUrl` — so
/// it exposes both an impression and a click beacon.
private func serveTrackable(_ driver: Driver, _ session: String) async throws -> Creative {
    let served = try await decide(
        driver, placements: [cptCustomEventPlacement], sessionId: session, opt: .optIn)
    guard let creative = served.creative(for: cptCustomEventPlacement), creative.isJourneyAd
    else {
        throw SkipScenario(
            "the seeded fixture did not serve on \"\(cptCustomEventPlacement)\" — is "
                + "`e2e_cpt_journey` present in this database?")
    }
    return creative
}

func trackingGroup() async {
    await scenario("D1", "tracking URLs are absolute /v1/tracking with an opaque ?e= token") {
        notes in
        let driver = newDriver()
        let creative = try await serveTrackable(driver, freshSession("d1"))
        let impression = creative.tracking.getImpressionUrl(key: "default")

        try check(
            isTrackingURL(impression),
            "the impression URL is absolute, path /v1/tracking, with a non-empty ?e= token "
                + "(got \(impression ?? "none"))")
        let token = trackingToken(impression!) ?? ""
        try check(token.count > 20, "the token is opaque, not a readable identifier")
        let parsed = URL(string: impression!)!
        let authority =
            parsed.port.map { "\(parsed.host ?? "?"):\($0)" } ?? (parsed.host ?? "?")
        notes.append(
            "\(parsed.scheme ?? "?")://\(authority)\(parsed.path) ?e=<\(token.count) chars>")
    }

    await scenario("D5", "a journey creative with a destination exposes a click URL") { notes in
        // Regression guard for adhub #2483: the platform writes camelCase template fields while
        // the click resolver matched a snake_case list, so tracking.clicks was [] on EVERY
        // journey serve for weeks. The suite stayed green the whole time because §D asserted
        // impressions only. An assertion that was never written is indistinguishable from a
        // passing one.
        let driver = newDriver()
        let creative = try await serveTrackable(driver, freshSession("d5"))
        let click = creative.tracking.getClickUrl(key: "default")

        try check(
            isTrackingURL(click),
            "a click tracking URL is exposed and meets the same transport contract as the "
                + "impression (got \(click ?? "none"))")
        try check(
            click != creative.tracking.getImpressionUrl(key: "default"),
            "the click beacon is distinct from the impression beacon")
        notes.append("clicks=\(creative.tracking.clicks?.count ?? 0)")
    }

    await scenario("D2", "the SDK fires the URL verbatim and a retry re-fires it identically") {
        notes in
        let driver = newDriver()
        let creative = try await serveTrackable(driver, freshSession("d2"))
        guard let impression = creative.tracking.getImpressionUrl(key: "default") else {
            throw ClaimFailed(claim: "the served creative exposes an impression URL")
        }

        RecordingURLProtocol.clear()
        driver.sdk.fireImpression(tracking: creative.tracking)
        _ = await waitForFires(1)
        driver.sdk.fireImpression(tracking: creative.tracking)
        let fired = await waitForFires(2)

        try check(fired.count == 2, "both fires reached the transport (got \(fired.count))")
        try check(
            fired[0] == impression,
            "the URL was fired byte-identical to what the engine returned")
        try check(fired[0] == fired[1], "the retry re-fired the identical string")
        // Fire-and-forget: locally the engine mints https:// URLs while serving plaintext, so
        // the request itself fails the TLS handshake. It must never surface to the caller —
        // reaching this line at all is the proof (T3).
        notes.append("fired verbatim twice; failures stayed inside the SDK")
    }

    await scenario("D4", "a no-ad response exposes no tracking and fires nothing") { notes in
        let driver = newDriver()
        let session = freshSession("d4")
        _ = try await serveTrackable(driver, session)  // consume the only node

        let repeated = try await decide(
            driver, placements: [cptCustomEventPlacement], sessionId: session, opt: .optIn)
        guard let decision = repeated.decision(for: cptCustomEventPlacement),
            !decision.hasCreative
        else {
            throw SkipScenario(
                "expected a no-ad on the repeat request but a creative served — the fixture "
                    + "may have more than one node on this placement")
        }

        try check(decision.isNoAd, "the decision is a clean no-ad")
        try check(
            decision.creatives == nil || decision.creatives?.isEmpty == true,
            "creatives is empty or absent — both shapes mean the same thing")

        RecordingURLProtocol.clear()
        // There is no creative, so there is no tracking to fire. Nothing is ever fired
        // automatically, so this is a no-op by construction (T4/T5).
        await sleepSeconds(0.3)
        try check(
            RecordingURLProtocol.sent.filter { $0.contains("/v1/tracking") }.isEmpty,
            "no tracking request was made")
        notes.append("no-ad exposed no creative and fired nothing")
    }

    await scenario("D6", "the engine accepts a tracking token it minted itself") { notes in
        let driver = newDriver()
        let creative = try await serveTrackable(driver, freshSession("d6"))
        guard let minted = creative.tracking.getImpressionUrl(key: "default") else {
            throw ClaimFailed(claim: "the served creative exposes an impression URL")
        }

        // Local-only artifact: the engine mints production-shaped https:// URLs while serving
        // plaintext on :8080, so firing one verbatim fails the TLS handshake locally.
        // Scheme/host/port are normalized onto the configured base URL and the ?e= token is
        // left untouched — rewriting the token would invalidate the very thing being tested.
        let normalized = normalizeForLocalIngestion(minted)
        try check(
            trackingToken(normalized) == trackingToken(minted),
            "normalization left the opaque token untouched")

        var request = URLRequest(url: URL(string: normalized)!)
        request.setValue(e2eAPIVersion, forHTTPHeaderField: "X-Tracking-Version")
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        try check(
            (200...299).contains(status),
            "the tracking endpoint accepted the token it minted (got HTTP \(status))")
        notes.append("ingestion returned HTTP \(status)")
    }
}

// MARK: - §E frequency cap

// The cap is a Redis sorted set counting NEW instances per user+deal. It never blocks
// continuation of an active instance, and it is skipped entirely when `user.id` is absent — so
// every scenario here must set a user id, and it must be unique per run or the cap keys
// collide across runs and the suite becomes a one-shot.

func frequencyCapGroup() async {
    await scenario("E1", "new-entry capping gates deterministically at the configured amount") {
        notes in
        let driver = newDriver()
        let userId = freshUser("e1")
        var admitted: [String] = []

        // Each attempt is a brand-new session, so each is a new-instance admission — the only
        // thing the cap counts. Deterministic: it depends on the count, not on wall-clock.
        for attempt in 1...(freqCapAmount + 1) {
            let served = try await decide(
                driver, placements: [freqCapPlacement],
                sessionId: freshSession("e1_\(attempt)"), opt: .optIn
            ) { builder in
                _ = builder.setUserId(userId)
            }
            let creative = served.creative(for: freqCapPlacement)
            if attempt == 1 && creative?.isJourneyAd != true {
                throw SkipScenario(
                    "the seeded frequency-cap fixture did not serve on \"\(freqCapPlacement)\" "
                        + "— is `e2e_frequency_cap_journey` present?")
            }
            if let creative = creative, creative.isJourneyAd {
                admitted.append(creative.journeyInstanceId ?? "")
            }
        }

        try check(
            admitted.count == freqCapAmount,
            "exactly \(freqCapAmount) new instances were admitted and the next was refused "
                + "(got \(admitted.count))")
        try check(
            Set(admitted).count == freqCapAmount, "each admission minted a distinct instance")
        notes.append("cap \(freqCapAmount) honoured for user \(userId)")
    }

    await scenario("E2", "the cap never blocks continuation of an active instance") { notes in
        let driver = newDriver()
        let userId = freshUser("e2")
        let liveSession = freshSession("e2_live")

        // Admission 1 — the instance we will later continue.
        let first = try await decide(
            driver, placements: [freqCapPlacement], sessionId: liveSession, opt: .optIn
        ) { builder in
            _ = builder.setUserId(userId)
        }
        guard let started = first.creative(for: freqCapPlacement), started.isJourneyAd else {
            throw SkipScenario(
                "the seeded frequency-cap fixture did not serve on \"\(freqCapPlacement)\" — "
                    + "is `e2e_frequency_cap_journey` present?")
        }
        let liveInstance = started.journeyInstanceId

        // Exhaust the remaining admissions with throwaway sessions.
        for index in 0..<freqCapAmount {
            _ = try await decide(
                driver, placements: [freqCapPlacement],
                sessionId: freshSession("e2_fill_\(index)"), opt: .optIn
            ) { builder in
                _ = builder.setUserId(userId)
            }
        }

        // A brand-new instance is now refused...
        let refused = try await decide(
            driver, placements: [freqCapPlacement], sessionId: freshSession("e2_refused"),
            opt: .optIn
        ) { builder in
            _ = builder.setUserId(userId)
        }
        let refusedCreative = refused.creative(for: freqCapPlacement)
        try check(
            refusedCreative == nil || refusedCreative?.isJourneyAd == false,
            "a brand-new instance is refused once the cap is exhausted")

        // ...while the already-active instance still progresses.
        let continued = try await decide(
            driver, placements: [freqCapLaterPlacement], sessionId: liveSession, opt: .optIn
        ) { builder in
            _ = builder.setUserId(userId)
        }
        guard let continuation = continued.creative(for: freqCapLaterPlacement),
            continuation.isJourneyAd
        else {
            throw ClaimFailed(
                claim: "the active instance still serves its next node with the cap exhausted")
        }
        try check(
            continuation.journeyInstanceId == liveInstance,
            "it is the same instance, not a new admission (\(liveInstance ?? "nil") vs "
                + "\(continuation.journeyInstanceId ?? "nil"))")
        notes.append("instance \(liveInstance ?? "?") continued past an exhausted cap")
    }
}

// MARK: - §H CPT pricing and the two completion strategies

// The strategies are mutually exclusive per deal:
//   custom_event → every served node exposes a completions[] beacon and isCompletion stays
//     FALSE. Completion records only when the publisher fires it — this is what bills CPT.
//   final_stage  → isCompletion is TRUE on any served node of the completion stage, marked
//     inline at decision time, and there is NO beacon.

func completionGroup() async {
    await scenario("H1/H2", "a CPT deal surfaces the exact pricing model and fallback billing mode")
    { notes in
        let driver = newDriver()
        let served = try await decide(
            driver, placements: [cptCustomEventPlacement], sessionId: freshSession("h1"),
            opt: .optIn)
        guard let creative = served.creative(for: cptCustomEventPlacement),
            creative.isJourneyAd
        else {
            throw SkipScenario(
                "the seeded CPT fixture did not serve on \"\(cptCustomEventPlacement)\" — is "
                    + "`e2e_cpt_journey` present?")
        }

        // Asserted exactly, not just non-blank: a non-blank check passes on any wrong value,
        // which is how a wrong billing mode ships unnoticed.
        try check(
            creative.journeyPricingModel == cptPricingModel,
            "pricingModel is \"\(cptPricingModel)\" (got \(creative.journeyPricingModel ?? "nil"))")
        try check(
            creative.journeyFallbackBillingMode == cptCustomEventFallback,
            "fallbackBillingMode is exactly \"\(cptCustomEventFallback)\" "
                + "(got \(creative.journeyFallbackBillingMode ?? "nil"))")
        notes.append(
            "\(creative.journeyPricingModel ?? "?") / "
                + "\(creative.journeyFallbackBillingMode ?? "?")")
    }

    await scenario(
        "H5",
        "a custom_event CPT deal exposes a fireable completion beacon while isCompletion stays "
            + "false"
    ) { notes in
        // The CPT billing trigger, and shipped public API. On Android this surface had ZERO
        // coverage: hasCompletionUrl/fireCompletion were exercised by nothing at all, so a
        // break would have been invisible.
        let driver = newDriver()
        let served = try await decide(
            driver, placements: [cptCustomEventPlacement], sessionId: freshSession("h5"),
            opt: .optIn)
        guard let creative = served.creative(for: cptCustomEventPlacement),
            creative.isJourneyAd
        else {
            throw SkipScenario(
                "the seeded CPT fixture did not serve on \"\(cptCustomEventPlacement)\" — is "
                    + "`e2e_cpt_journey` present?")
        }

        try check(creative.hasCompletionUrl, "the served node exposes a completions[] beacon")
        let completionURL = creative.tracking.getCompletionUrl(key: cptCustomEventKey)
        try check(
            isTrackingURL(completionURL),
            "the beacon is keyed \"\(cptCustomEventKey)\" and meets the transport contract "
                + "(got \(completionURL ?? "none"))")
        try check(
            creative.isJourneyCompletion == false,
            "isCompletion stays FALSE for custom_event — completion is recorded only when the "
                + "publisher fires the beacon")
        // Additive to the normal impression, never a replacement (C3).
        try check(
            isTrackingURL(creative.tracking.getImpressionUrl(key: "default")),
            "the normal impression beacon is still present alongside it")

        RecordingURLProtocol.clear()
        driver.sdk.fireCompletion(tracking: creative.tracking, key: cptCustomEventKey)
        let fired = await waitForFires(1)
        try check(
            fired.count == 1, "fireCompletion dispatched exactly one request (got \(fired.count))")
        try check(fired[0] == completionURL, "it fired the server-provided URL verbatim")
        notes.append("beacon \"\(cptCustomEventKey)\" exposed and fired verbatim")
    }

    await scenario("H3", "a final_stage serve flips isCompletion and emits NO beacon") { notes in
        let driver = newDriver()
        let session = freshSession("h3")
        let early = try await decide(
            driver, placements: [cptFinalEarlyPlacement], sessionId: session, opt: .optIn)
        guard let earlyCreative = early.creative(for: cptFinalEarlyPlacement),
            earlyCreative.isJourneyAd
        else {
            throw SkipScenario(
                "the seeded final_stage fixture did not serve on \"\(cptFinalEarlyPlacement)\" "
                    + "— is `e2e_cpt_final_journey` present?")
        }
        try check(
            earlyCreative.isJourneyCompletion == false,
            "the earlier stage is not the completion stage")

        let complete = try await decide(
            driver, placements: [cptFinalCompletePlacement], sessionId: session, opt: .optIn)
        guard let completion = complete.creative(for: cptFinalCompletePlacement),
            completion.isJourneyAd
        else {
            throw ClaimFailed(
                claim: "the completion stage serves on \"\(cptFinalCompletePlacement)\"")
        }

        try check(
            completion.isJourneyCompletion == true,
            "final_stage flips isCompletion to true, inline at decision time")
        try check(
            completion.hasCompletionUrl == false,
            "and emits NO completion beacon — there is nothing for the publisher to fire, so a "
                + "beacon here would mean double counting "
                + "(got \(completion.tracking.completions?.count ?? 0))")
        try check(
            completion.journeyPricingModel == cptPricingModel,
            "CPT pricing is surfaced on the completing serve")
        try check(
            completion.journeyFallbackBillingMode == cptFinalStageFallback,
            "fallbackBillingMode is exactly \"\(cptFinalStageFallback)\" "
                + "(got \(completion.journeyFallbackBillingMode ?? "nil"))")
        notes.append(
            "completed inline; beacons=0; \(completion.journeyPricingModel ?? "?")/"
                + "\(completion.journeyFallbackBillingMode ?? "?")")
    }

    await scenario("H4", "after completion, takeover protection ends") { notes in
        let driver = newDriver()
        let session = freshSession("h4")
        _ = try await decide(
            driver, placements: [cptFinalEarlyPlacement], sessionId: session, opt: .optIn)
        let complete = try await decide(
            driver, placements: [cptFinalCompletePlacement], sessionId: session, opt: .optIn)
        guard let completion = complete.creative(for: cptFinalCompletePlacement),
            completion.isJourneyCompletion
        else {
            throw SkipScenario(
                "could not reach the completion stage on \"\(cptFinalCompletePlacement)\" — is "
                    + "`e2e_cpt_final_journey` present?")
        }

        // The corrected assertion. A completed instance is TERMINAL: a continued OPT-IN mints a
        // brand-new instance (opt-in means "give me a journey"), so only OPT-OUT reveals that
        // the takeover has ended. The original Android test assumed "after completion ⇒ normal
        // ad" under opt-in and was wrong; the engine was right.
        let after = try await decide(
            driver, placements: [cptFinalCompletePlacement], sessionId: session, opt: .optOut)
        guard let normal = after.creative(for: cptFinalCompletePlacement) else {
            throw ClaimFailed(
                claim: "a competing normal ad serves on the completion placement once the "
                    + "takeover has ended")
        }
        try check(!normal.isJourneyAd, "and it is not a journey ad")
        notes.append("takeover ended; normal ad from \(normal.advertiser.name ?? "?")")
    }
}

// MARK: - §J mandatory vs optional stages, and targeting in both directions

func targetingGroup() async {
    await scenario("J1", "an unserved mandatory stage HOLDS the later surface") { notes in
        let driver = newDriver()
        // Requesting the later stage while the mandatory earlier stage is unserved must produce
        // a no-ad hold rather than letting a competitor in.
        let held = try await decide(
            driver, placements: [mandatoryLaterPlacement], sessionId: freshSession("j1"),
            opt: .optIn)
        let heldCreative = held.creative(for: mandatoryLaterPlacement)

        // Positive control FIRST, so a missing fixture cannot masquerade as a hold. No session
        // at all — a session with journeyOpt omitted is effectively opt-in and would start a
        // journey that holds the surface itself.
        let control = try await decide(driver, placements: [mandatoryLaterPlacement])
        guard let controlCreative = control.creative(for: mandatoryLaterPlacement) else {
            throw SkipScenario(
                "no competing control ad on \"\(mandatoryLaterPlacement)\" — without one, a "
                    + "no-ad is indistinguishable from an empty placement and proves nothing. "
                    + "Is `e2e_mandatory_journey` and its control ad seeded?")
        }
        try check(
            !controlCreative.isJourneyAd,
            "the no-session control serves a competing normal ad, proving the placement has "
                + "inventory")

        try check(
            heldCreative == nil || heldCreative?.isJourneyAd == false,
            "the later optional stage did not serve while the mandatory stage is unserved")
        try check(
            heldCreative == nil,
            "the surface is HELD — no competing ad served either, which is correct takeover "
                + "behaviour and not a fill failure")
        notes.append("mandatory hold confirmed against a serving control")
    }

    await scenario(
        "J5",
        "an optional stage with no node on the requested placement is SKIPPED and cannot serve "
            + "later"
    ) { notes in
        let driver = newDriver()
        let session = freshSession("j5")

        // Requesting the LATER placement means the earlier optional stage has no node for this
        // request, so the engine skips it. Contrast with J1, where the earlier stage is
        // mandatory and holds instead. The skip lever is placement availability, not creative
        // absence: a node that merely lacks a creative "phantom-serves" and closes the whole
        // instance.
        let later = try await decide(
            driver, placements: [optSkipLaterPlacement], sessionId: session, opt: .optIn)
        guard let laterCreative = later.creative(for: optSkipLaterPlacement),
            laterCreative.isJourneyAd
        else {
            throw SkipScenario(
                "the later optional stage did not serve on \"\(optSkipLaterPlacement)\" — is "
                    + "`e2e_optional_skip_journey` present?")
        }

        let earlier = try await decide(
            driver, placements: [optSkipEarlyPlacement], sessionId: session, opt: .optIn)
        let earlierCreative = earlier.creative(for: optSkipEarlyPlacement)
        try check(
            earlierCreative == nil || earlierCreative?.isJourneyAd == false,
            "the skipped stage cannot serve afterwards — the journey never goes backwards")
        notes.append(
            "stage \(laterCreative.journeyStageKey ?? "?") served; the earlier stage stayed "
                + "skipped")
    }

    await scenario("J4", "geo targeting: a matching geoname serves, a real non-matching one does not")
    { notes in
        let driver = newDriver()
        let match = try await decide(
            driver, placements: [targetGeoPlacement], sessionId: freshSession("j4_match"),
            opt: .optIn
        ) { builder in
            _ = builder.addGeoTargeting(nycGeonameId)
        }
        guard let matched = match.creative(for: targetGeoPlacement), matched.isJourneyAd else {
            throw SkipScenario(
                "the geo-targeted fixture did not serve for geoname \(nycGeonameId) on "
                    + "\"\(targetGeoPlacement)\" — is `e2e_target_geo_journey` present?")
        }

        let noMatch = try await decide(
            driver, placements: [targetGeoPlacement], sessionId: freshSession("j4_nomatch"),
            opt: .optIn
        ) { builder in
            _ = builder.addGeoTargeting(londonGeonameId)
        }
        let unmatched = noMatch.creative(for: targetGeoPlacement)
        try check(
            unmatched == nil || unmatched?.isJourneyAd == false,
            "a real but non-matching geoname (\(londonGeonameId)) excludes the deal cleanly, "
                + "rather than erroring")
        notes.append("geo \(nycGeonameId) served; \(londonGeonameId) excluded")
        _ = matched
    }

    await scenario("J2", "location targeting: inside the radius serves, outside does not") {
        notes in
        let driver = newDriver()
        let inside = try await decide(
            driver, placements: [targetLocationPlacement], sessionId: freshSession("j2_in"),
            opt: .optIn
        ) { builder in
            _ = builder.addLocationTargeting(latitude: nycLatitude, longitude: nycLongitude)
        }
        guard let insideCreative = inside.creative(for: targetLocationPlacement),
            insideCreative.isJourneyAd
        else {
            throw SkipScenario(
                "the location-targeted fixture did not serve in-radius on "
                    + "\"\(targetLocationPlacement)\" — is `e2e_target_location_journey` present?")
        }

        let outside = try await decide(
            driver, placements: [targetLocationPlacement], sessionId: freshSession("j2_out"),
            opt: .optIn
        ) { builder in
            _ = builder.addLocationTargeting(
                latitude: londonLatitude, longitude: londonLongitude)
        }
        let outsideCreative = outside.creative(for: targetLocationPlacement)
        try check(
            outsideCreative == nil || outsideCreative?.isJourneyAd == false,
            "a coordinate outside the seeded radius excludes the deal")
        if outsideCreative != nil {
            notes.append(
                "out-of-radius fell through to a competing normal ad, so the exclusion is "
                    + "attributable to targeting rather than no-fill")
        }
        notes.append("in-radius served stage \(insideCreative.journeyStageKey ?? "?")")
    }

    await scenario(
        "J3", "destination targeting: confidence at or above the threshold serves, below does not"
    ) { notes in
        let driver = newDriver()
        let above = try await decide(
            driver, placements: [targetDestinationPlacement],
            sessionId: freshSession("j3_above"), opt: .optIn
        ) { builder in
            _ = try builder.addDestinationTargeting(
                latitude: nycLatitude, longitude: nycLongitude,
                minConfidence: destinationThreshold + 0.2)
        }
        guard let aboveCreative = above.creative(for: targetDestinationPlacement),
            aboveCreative.isJourneyAd
        else {
            throw SkipScenario(
                "the destination-targeted fixture did not serve above the confidence threshold "
                    + "on \"\(targetDestinationPlacement)\" — is `e2e_target_destination_journey` "
                    + "present?")
        }

        let below = try await decide(
            driver, placements: [targetDestinationPlacement],
            sessionId: freshSession("j3_below"), opt: .optIn
        ) { builder in
            _ = try builder.addDestinationTargeting(
                latitude: nycLatitude, longitude: nycLongitude,
                minConfidence: destinationThreshold - 0.2)
        }
        let belowCreative = below.creative(for: targetDestinationPlacement)
        try check(
            belowCreative == nil || belowCreative?.isJourneyAd == false,
            "a confidence below the seeded threshold (\(destinationThreshold)) excludes the deal")
        notes.append("confidence gate honoured at \(destinationThreshold)")
    }
}

// MARK: - §F runtime-state TTL

// The TTL is `journey_definitions.runtime_state_ttl_seconds`, applied verbatim as a Redis
// `SET … EX ttl` with no floor. Advancing to a NEW node re-sets it; re-serving the SAME node
// returns early and does NOT refresh. These two scenarios spend real wall-clock time, which is
// why they run last.

func ttlGroup() async {
    await scenario("F1", "runtime-state expiry restarts the journey") { notes in
        let driver = newDriver()
        let session = freshSession("f1")
        let first = try await decide(
            driver, placements: [shortTtlPlacement], sessionId: session, opt: .optIn)
        guard let started = first.creative(for: shortTtlPlacement), started.isJourneyAd else {
            throw SkipScenario(
                "the short-TTL fixture did not serve on \"\(shortTtlPlacement)\" — is "
                    + "`e2e_short_ttl_journey` present?")
        }
        try check(
            started.isJourneyCompletion != true,
            "the journey did not complete — so a new instance later can only be the TTL "
                + "expiring, not a completed journey being replaced")
        let firstInstance = started.journeyInstanceId

        // Wait past the TTL with a margin. The runtime-state key expires and the same session
        // becomes a brand-new journey.
        await sleepSeconds(shortTtlSeconds + 2)

        let afterExpiry = try await decide(
            driver, placements: [shortTtlPlacement], sessionId: session, opt: .optIn)
        guard let restarted = afterExpiry.creative(for: shortTtlPlacement),
            restarted.isJourneyAd
        else {
            throw ClaimFailed(claim: "the same session serves again after the TTL expired")
        }
        try check(
            restarted.journeyInstanceId != firstInstance,
            "a NEW instance was minted (\(firstInstance ?? "nil") → "
                + "\(restarted.journeyInstanceId ?? "nil")) — the expired state was not resumed")
        notes.append("instance restarted after \(Int(shortTtlSeconds))s TTL expiry")
    }

    await scenario(
        "F2", "serving a NEW node refreshes the TTL, so the instance outlives its original "
            + "deadline"
    ) { notes in
        let driver = newDriver()
        let session = freshSession("f2")
        // The multi-node fixture also carries a 5s TTL, and its three nodes let us advance to a
        // *new* node mid-window — which is the only thing that refreshes the key. Re-serving the
        // same node returns early and does not.
        let step = 3.5

        let first = try await decide(
            driver, placements: [multiNodePlacements[0]], sessionId: session, opt: .optIn)
        guard let started = first.creative(for: multiNodePlacements[0]), started.isJourneyAd
        else {
            throw SkipScenario(
                "the multi-node fixture did not serve on \"\(multiNodePlacements[0])\" — is "
                    + "`e2e_multinode_journey` present?")
        }
        let instance = started.journeyInstanceId

        await sleepSeconds(step)
        let refreshed = try await decide(
            driver, placements: [multiNodePlacements[1]], sessionId: session, opt: .optIn)
        guard let refreshedCreative = refreshed.creative(for: multiNodePlacements[1]),
            refreshedCreative.isJourneyAd
        else {
            throw ClaimFailed(
                claim: "a new node served mid-window, refreshing the runtime state")
        }
        try check(
            refreshedCreative.journeyInstanceId == instance, "still the same instance")

        // Now past the ORIGINAL 5s deadline, but within the refreshed window.
        await sleepSeconds(step)
        let survived = try await decide(
            driver, placements: [multiNodePlacements[2]], sessionId: session, opt: .optIn)
        guard let survivedCreative = survived.creative(for: multiNodePlacements[2]),
            survivedCreative.isJourneyAd
        else {
            throw ClaimFailed(
                claim: "the journey still serves past its original creation deadline")
        }
        try check(
            survivedCreative.journeyInstanceId == instance,
            "the instance survived because the mid-window serve refreshed the TTL "
                + "(\(instance ?? "nil") vs \(survivedCreative.journeyInstanceId ?? "nil"))")
        notes.append(
            "instance \(instance ?? "?") survived \(step * 2)s on a \(Int(shortTtlSeconds))s TTL")
    }
}

// MARK: - §G video delivery

// A headless runner can prove the SDK EXPOSES the delivery data and does NOT auto-fire
// anything. It cannot drive real playback callbacks — that needs an actual player and is
// flagged as a follow-up rather than faked here.

private func serveVideo(_ driver: Driver, _ placement: String, _ tag: String) async throws
    -> Creative
{
    let served = try await decide(
        driver, placements: [placement], sessionId: freshSession(tag), opt: .optIn)
    guard let creative = served.creative(for: placement), creative.isJourneyAd else {
        throw SkipScenario(
            "the video fixture did not serve on \"\(placement)\" — is its "
                + "`e2e_video_*_journey` seeded, and are the VAST env vars set?")
    }
    return creative
}

func videoGroup() async {
    await scenario("G1", "a JSON video node exposes json delivery and its video tracking") {
        notes in
        let driver = newDriver()
        let creative = try await serveVideo(driver, videoJsonPlacement, "g1")

        try check(
            creative.delivery == "json", "delivery is \"json\" (got \(creative.delivery ?? "nil"))")
        try check(creative.isJsonDelivery(), "the helper agrees it is JSON delivery")
        try check(
            !creative.isVastTagDelivery() && !creative.isVastXmlDelivery(),
            "and it is not reported as either VAST mode")

        // For JSON delivery the engine owns the beacons, so they must be present for the
        // publisher's player to fire.
        let events = creative.tracking.videoEvents ?? []
        try check(
            !events.isEmpty,
            "video event beacons are exposed for the player to fire (got \(events.count))")
        for event in events {
            try check(
                isTrackingURL(event.url),
                "video event \"\(event.key)\" meets the transport contract")
        }

        // Nothing is ever fired automatically (T4).
        RecordingURLProtocol.clear()
        await sleepSeconds(0.3)
        try check(
            RecordingURLProtocol.sent.filter { $0.contains("/v1/tracking") }.isEmpty,
            "merely reading the video data fires nothing")
        notes.append(
            "json delivery, \(events.count) video events: "
                + events.map(\.key).joined(separator: ", "))
    }

    await scenario("G2", "VAST tag/xml expose the payload and surface NO VAST-owned beacons") {
        notes in
        // The double-count rule: for VAST delivery the impression, quartile and click beacons
        // live INSIDE the VAST document and belong to the publisher's player. If the SDK also
        // surfaced them, a publisher wiring up both would count everything twice.
        let driver = newDriver()
        let tag = try await serveVideo(driver, videoVastTagPlacement, "g2_tag")
        try check(
            tag.delivery == "vast_tag", "delivery is \"vast_tag\" (got \(tag.delivery ?? "nil"))")
        try check(tag.isVastTagDelivery(), "the helper agrees")
        let tagURL = tag.getVastTagUrl()
        try check(
            !(tagURL ?? "").isEmpty, "the VAST tag URL is exposed for the player")
        try check(
            (tag.tracking.videoEvents ?? []).isEmpty,
            "NO VAST-owned video-event beacons are surfaced "
                + "(got \(tag.tracking.videoEvents?.count ?? 0))")

        let xml = try await serveVideo(driver, videoVastXmlPlacement, "g2_xml")
        try check(
            xml.delivery == "vast_xml", "delivery is \"vast_xml\" (got \(xml.delivery ?? "nil"))")
        try check(xml.isVastXmlDelivery(), "the helper agrees")
        try check(
            !(xml.getVastXmlBase64() ?? "").isEmpty,
            "the inline base64 VAST document is exposed")
        try check(
            (xml.tracking.videoEvents ?? []).isEmpty,
            "NO VAST-owned video-event beacons are surfaced for xml either "
                + "(got \(xml.tracking.videoEvents?.count ?? 0))")

        RecordingURLProtocol.clear()
        await sleepSeconds(0.3)
        try check(
            RecordingURLProtocol.sent.filter { $0.contains("/v1/tracking") }.isEmpty,
            "and nothing was auto-fired")
        notes.append("vast_tag + vast_xml exposed with zero SDK-surfaced video beacons")
    }
}
