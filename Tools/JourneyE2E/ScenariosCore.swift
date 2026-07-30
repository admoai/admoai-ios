import AdMoai
import Foundation

// §Self-check, §K wizard parity, §A request forwarding, §B progression, §C opt-in/opt-out.

// MARK: - §Self-check

// Guards the Swift analogue of the Android runner's worst bug: a config hook that silently
// drops the caller's user id and targeting looks exactly like an engine defect. Proven on the
// wire before any scenario relies on it.
func selfCheckGroup() async {
    await scenario("S1", "the decide() helper forwards user id and targeting") { notes in
        let driver = newDriver()
        let userId = freshUser("selfcheck")
        let request = driver.sdk.createRequestBuilder()
            .addPlacement(key: demoStage1Placement)
            .setUserId(userId)
            .addGeoTargeting(nycGeonameId)
            .build()
        let body = String(data: try driver.sdk.getHttpRequest(request).body ?? Data(), encoding: .utf8) ?? ""

        try check(
            body.contains("\"id\":\"\(userId)\""),
            "the request body carries the user id set by the caller")
        try check(
            body.contains("\(nycGeonameId)"),
            "the request body carries the geo target set by the caller")
        notes.append("config forwarding proven on the wire")
    }
}

// MARK: - §K wizard parity

// Every seeded fixture encodes what the ENGINE expects, so no seeded fixture can catch a
// mismatch between what the platform (Ad Manager) WRITES and what the engine READS. Both real
// bugs of the Android rounds lived in exactly that seam and both survived a fully green suite:
//   adhub #2459 — the wizard always persists a {"enabled":bool,"payload":{…}} targeting
//     envelope; the engine passed custom_targeting through raw, so every wizard-created
//     journey deal was dropped from every shortlist.
//   adhub #2483 — the platform writes camelCase template fields (destinationUrl,
//     urlSlide1..3) while the click resolver matched a snake_case list, so tracking.clicks was
//     [] on every journey serve for weeks.

/// Probes the wizard fixture's placement. Absence is an environment fact (a `db-reset`
/// happened), so it SKIPs rather than FAILs — but a SKIP here means the platform→engine seam
/// went unverified, which the summary calls out explicitly.
private func requireWizardServe(
    _ driver: Driver, _ sessionId: String, _ placement: String
) async throws -> Creative {
    let served = try await decide(
        driver, placements: [placement], sessionId: sessionId, opt: .optIn)
    guard let creative = served.creative(for: placement), creative.isJourneyAd else {
        throw SkipScenario(
            "no journey served on \"\(placement)\" — the hand-built \"\(wizardDefinition)\" "
                + "fixture is absent (destroyed by `make db-reset`?). Rebuild it from "
                + "Tests/AdMoaiTests/E2E/Fixtures/README.md, or the platform→engine seam is "
                + "unverified.")
    }
    guard creative.journeyDefinitionKey == wizardDefinition else {
        throw SkipScenario(
            "\"\(placement)\" is owned by \"\(creative.journeyDefinitionKey ?? "nil")\", not "
                + "the wizard fixture \"\(wizardDefinition)\" — another journey deal is masking it")
    }
    return creative
}

func wizardParityGroup() async {
    await scenario(
        "K1",
        "platform-authored journey serves stage 1 with the config the wizard wrote, and "
            + "exposes a click URL"
    ) { notes in
        let driver = newDriver()
        let session = freshSession("k1")
        let creative = try await requireWizardServe(driver, session, wizardPlacement1)

        try check(
            creative.journeyDefinitionKey == wizardDefinition,
            "definitionKey is \"\(wizardDefinition)\"")
        try check(
            creative.journeyDealId == wizardDeal,
            "dealId is the wizard deal \(wizardDeal) (got \(creative.journeyDealId ?? "nil"))")
        try check(
            creative.journeyStageKey == wizardStage1,
            "stageKey is \"\(wizardStage1)\" (got \(creative.journeyStageKey ?? "nil"))")
        try check(
            !(creative.journeyInstanceId ?? "").isEmpty, "an instance id was minted")
        try check(
            creative.journeyPricingModel == cptPricingModel,
            "pricingModel is \"\(cptPricingModel)\" (got \(creative.journeyPricingModel ?? "nil"))")
        try check(
            creative.journeyFallbackBillingMode == cptFinalStageFallback,
            "fallbackBillingMode is \"\(cptFinalStageFallback)\" "
                + "(got \(creative.journeyFallbackBillingMode ?? "nil"))")
        try check(
            creative.isJourneyCompletion == false,
            "stage 1 of a final_stage deal is not a completion")
        try check(
            creative.journeySessionId == session, "the engine echoes the session id back")

        // The #2483 regression guard. The wizard writes camelCase url fields (urlSlide1..3);
        // if the click resolver ever stops matching them, tracking.clicks silently becomes []
        // and journey CTR is unmeasurable — with every other assertion here still green.
        let clickURL = creative.tracking.getClickUrl(key: "default")
        try check(
            isTrackingURL(clickURL),
            "a click tracking URL is exposed and meets the transport contract (absolute, "
                + "/v1/tracking, opaque ?e=) — got \(clickURL ?? "none")")
        try check(
            isTrackingURL(creative.tracking.getImpressionUrl(key: "default")),
            "an impression tracking URL is exposed")

        notes.append(
            "stage=\(creative.journeyStageKey ?? "?") node=\(creative.journeyStageNodeId ?? "?")")
        notes.append(
            "clicks=\(creative.tracking.clicks?.count ?? 0) "
                + "impressions=\(creative.tracking.impressions?.count ?? 0)")
    }

    await scenario("K2", "progression across platform-authored stages holds one instance") {
        notes in
        let driver = newDriver()
        let session = freshSession("k2")
        let first = try await requireWizardServe(driver, session, wizardPlacement1)

        let servedSecond = try await decide(
            driver, placements: [wizardPlacement2], sessionId: session, opt: .optIn)
        guard let second = servedSecond.creative(for: wizardPlacement2), second.isJourneyAd
        else {
            throw ClaimFailed(claim: "stage 2 serves on \"\(wizardPlacement2)\"")
        }

        try check(
            second.journeyInstanceId == first.journeyInstanceId,
            "the instance id is stable across stages "
                + "(\(first.journeyInstanceId ?? "nil") vs \(second.journeyInstanceId ?? "nil"))")
        try check(
            second.journeyDealId == first.journeyDealId,
            "the deal id is constant across the journey")
        try check(
            second.journeyStageKey == wizardStage2,
            "stage advanced to \"\(wizardStage2)\" (got \(second.journeyStageKey ?? "nil"))")
        try check(
            second.journeyStageNodeId != first.journeyStageNodeId, "a different node served")
        try check(
            second.isJourneyCompletion == false, "the middle stage is not the completion stage")

        notes.append(
            "instance \(first.journeyInstanceId ?? "?") held across "
                + "\(wizardStage1) → \(wizardStage2)")
    }

    await scenario("K3", "the wizard's final_stage completes the journey and emits no beacon") {
        notes in
        let driver = newDriver()
        let session = freshSession("k3")
        let first = try await requireWizardServe(driver, session, wizardPlacement1)

        // Walk the graph to the completion stage.
        _ = try await decide(
            driver, placements: [wizardPlacement2], sessionId: session, opt: .optIn)
        let servedFinal = try await decide(
            driver, placements: [wizardPlacement3], sessionId: session, opt: .optIn)
        guard let last = servedFinal.creative(for: wizardPlacement3), last.isJourneyAd else {
            throw ClaimFailed(
                claim: "the completion stage serves on \"\(wizardPlacement3)\"")
        }

        try check(
            last.journeyStageKey == wizardStage3,
            "the served stage is \"\(wizardStage3)\" (got \(last.journeyStageKey ?? "nil"))")
        try check(
            last.journeyInstanceId == first.journeyInstanceId,
            "still the same instance at completion")
        try check(
            last.isJourneyCompletion == true, "final_stage flips isCompletion to true")
        // The mirror assertion. final_stage and custom_event are mutually exclusive per deal:
        // completion is marked inline at decision time, so there is nothing for the publisher
        // to fire. A beacon here would mean double counting.
        try check(
            last.hasCompletionUrl == false,
            "a final_stage deal exposes NO completion beacon "
                + "(got \(last.tracking.completions?.count ?? 0))")

        notes.append("completed on stage \(wizardStage3), no beacon exposed")
    }

    await scenario("K4", "an already-served wizard node does not serve twice") { notes in
        let driver = newDriver()
        let session = freshSession("k4")
        let first = try await requireWizardServe(driver, session, wizardPlacement1)
        let servedNode = first.journeyStageNodeId

        let repeated = try await decide(
            driver, placements: [wizardPlacement1], sessionId: session, opt: .optIn)
        let repeatCreative = repeated.creative(for: wizardPlacement1)
        let repeatedSameNode =
            repeatCreative?.isJourneyAd == true
            && repeatCreative?.journeyStageNodeId == servedNode
        try check(
            !repeatedSameNode,
            "the same node does not serve twice (node \(servedNode ?? "?"))")

        // Positive control. Without it, "no ad" is indistinguishable from "empty placement"
        // and the assertion above proves nothing. The control sends NO session at all —
        // omitting journeyOpt while sending a session is effectively opt-in, which would start
        // a journey and hold the surface, so the control could never serve the competing ad.
        // That mistake cost the Android round a day.
        let control = try await decide(driver, placements: [wizardPlacement1])
        if let controlCreative = control.creative(for: wizardPlacement1) {
            try check(
                !controlCreative.isJourneyAd,
                "the control (no session) serves a normal, non-journey ad, proving "
                    + "\"\(wizardPlacement1)\" has inventory and the no-ad above was takeover "
                    + "suppression rather than no-fill")
            notes.append(
                "positive control served a normal ad "
                    + "(advertiser \(controlCreative.advertiser.name ?? "?"))")
        } else {
            notes.append(
                "no competing normal ad on \"\(wizardPlacement1)\" — suppression is asserted "
                    + "without a positive control")
        }

        notes.append(
            repeated.isNoAd(for: wizardPlacement1)
                ? "repeat request returned no-ad"
                : "repeat request served a different node "
                    + "(\(repeatCreative?.journeyStageNodeId ?? "?"))")
    }
}

// MARK: - §A request forwarding & backward compatibility

func requestForwardingGroup() async {
    await scenario("A1", "no sessionId → a normal decision with no journey metadata") { notes in
        // Journeys cannot activate without a publisher-supplied session. This is the safe
        // default: an integration that forgets sessionId keeps serving normal ads rather than
        // breaking.
        let driver = newDriver()
        let served = try await decide(driver, placements: [demoStage1Placement])
        guard let creative = served.creative(for: demoStage1Placement) else {
            throw ClaimFailed(claim: "a normal ad served on \"\(demoStage1Placement)\"")
        }

        try check(!creative.isJourneyAd, "the serve is not a journey ad")
        try check(creative.journeyInstanceId == nil, "no instance id is exposed")
        try check(creative.journeyDealId == nil, "no deal id is exposed")
        try check(creative.journeyStageKey == nil, "no stage key is exposed")
        try check(creative.isJourneyCompletion == false, "isCompletion is false")
        try check(creative.hasCompletionUrl == false, "no completion beacon")
        notes.append("normal ad from advertiser \(creative.advertiser.name ?? "?")")
    }

    await scenario(
        "A3",
        "sessionId/journeyOpt reach the wire top-level and camelCase, with the version header"
    ) { notes in
        let driver = newDriver()
        let session = freshSession("a3")
        let request = driver.sdk.createRequestBuilder()
            .addPlacement(key: demoStage1Placement)
            .setSessionId(session)
            .setJourneyOpt(.optIn)
            .build()
        let http = try driver.sdk.getHttpRequest(request)
        let body = String(data: http.body ?? Data(), encoding: .utf8) ?? ""

        try check(
            http.headers?["X-Decision-Version"] == e2eAPIVersion,
            "X-Decision-Version is \(e2eAPIVersion) — without it the engine SILENTLY ignores "
                + "journey fields and serves normal ads")
        try check(
            body.contains("\"sessionId\":\"\(session)\""),
            "sessionId is a top-level camelCase field")
        try check(
            body.contains("\"journeyOpt\":\"in\""),
            "journeyOpt serializes as the wire literal \"in\"")
        // Not nested under user/targeting — a shape mismatch the engine would ignore without
        // complaining.
        try check(
            !body.contains("\"user\":{\"sessionId\""), "sessionId is not nested under user")
        notes.append("wire shape verified without touching the engine")
    }

    await scenario("A4", "sessionId is sticky across builds and not regenerated") { notes in
        let session = freshSession("a4")
        let driver = newDriver(sessionId: session)

        // Every builder inherits the sticky value, and rebuilding never mints a new one — the
        // SDK must never generate, rotate or persist a session id.
        let first = driver.sdk.createRequestBuilder()
            .addPlacement(key: demoStage1Placement).build()
        let second = driver.sdk.createRequestBuilder()
            .addPlacement(key: demoStage2Placement).build()
        try check(first.sessionId == session, "the first builder inherited it")
        try check(second.sessionId == session, "the second builder inherited it too")

        // A per-request override applies to that request only.
        let override = freshSession("a4-override")
        let third = driver.sdk.createRequestBuilder()
            .addPlacement(key: demoStage1Placement).setSessionId(override).build()
        let fourth = driver.sdk.createRequestBuilder()
            .addPlacement(key: demoStage1Placement).build()
        try check(third.sessionId == override, "the per-request override applies")
        try check(
            fourth.sessionId == session, "the override did not leak into the next request")

        // And a per-request clear removes it for that request only.
        let cleared = driver.sdk.createRequestBuilder()
            .addPlacement(key: demoStage1Placement).clearSessionId().build()
        try check(cleared.sessionId == nil, "a per-request clear drops the session")
        notes.append("sticky, overridable, and clearable per request")
    }
}

// MARK: - §B stage progression & multi-node (shipped demo ride-hailing journey)

/// Serves the demo journey's first stage.
private func startJourney(_ driver: Driver, _ session: String) async throws -> Creative {
    let served = try await decide(
        driver, placements: [demoStage1Placement], sessionId: session, opt: .optIn)
    guard let creative = served.creative(for: demoStage1Placement), creative.isJourneyAd else {
        throw ClaimFailed(claim: "the journey starts on \"\(demoStage1Placement)\"")
    }
    return creative
}

func progressionGroup() async {
    await scenario("B1", "a new session serves the first stage and starts an instance") { notes in
        let driver = newDriver()
        let creative = try await startJourney(driver, freshSession("b1"))

        try check(
            creative.journeyDefinitionKey == demoDefinition,
            "definitionKey is \"\(demoDefinition)\"")
        try check(
            creative.journeyStageKey == demoStage1Key,
            "the first stage \"\(demoStage1Key)\" serves (got \(creative.journeyStageKey ?? "nil"))")
        try check(
            !(creative.journeyInstanceId ?? "").isEmpty, "a non-blank instance id was minted")
        try check(
            creative.isJourneyCompletion != true, "the first stage is not a completion")
        notes.append(
            "instance \(creative.journeyInstanceId ?? "?") stage \(creative.journeyStageKey ?? "?")")
    }

    await scenario("B2", "a second node in the same stage serves (multi-node)") { notes in
        let driver = newDriver()
        let session = freshSession("b2")
        let first = try await startJourney(driver, session)

        let served = try await decide(
            driver, placements: [demoStage1PlacementB], sessionId: session, opt: .optIn)
        guard let second = served.creative(for: demoStage1PlacementB), second.isJourneyAd else {
            throw ClaimFailed(
                claim: "the second node serves on \"\(demoStage1PlacementB)\"")
        }

        try check(
            second.journeyStageKey == first.journeyStageKey,
            "the stage did not advance (still \(first.journeyStageKey ?? "nil"))")
        try check(
            second.journeyStageNodeId != first.journeyStageNodeId, "a different node served")
        try check(
            second.journeyInstanceId == first.journeyInstanceId,
            "the same instance served both nodes")
        notes.append(
            "nodes \(first.journeyStageNodeId ?? "?") + \(second.journeyStageNodeId ?? "?") "
                + "in \(first.journeyStageKey ?? "?")")
    }

    await scenario(
        "B3", "a repeated node returns no-ad; a positive control proves suppression rather "
            + "than no-fill"
    ) { notes in
        let driver = newDriver()
        let session = freshSession("b3")
        let first = try await startJourney(driver, session)

        let repeated = try await decide(
            driver, placements: [demoStage1Placement], sessionId: session, opt: .optIn)
        let repeatCreative = repeated.creative(for: demoStage1Placement)
        let sameNodeAgain =
            repeatCreative?.isJourneyAd == true
            && repeatCreative?.journeyStageNodeId == first.journeyStageNodeId
        try check(!sameNodeAgain, "the already-served node does not serve again")

        // The control sends NO session. Sending a session with journeyOpt omitted is
        // effectively opt-in, so the control would start its own journey and hold the surface —
        // and could never serve the competing ad.
        let control = try await decide(driver, placements: [demoStage1Placement])
        guard let controlCreative = control.creative(for: demoStage1Placement) else {
            throw ClaimFailed(
                claim: "the no-session control serves a competing normal ad on "
                    + "\"\(demoStage1Placement)\"")
        }
        try check(
            !controlCreative.isJourneyAd,
            "the no-session control serves a competing normal ad, proving the placement has "
                + "inventory and the no-ad above was takeover suppression, not a fill failure")
        notes.append("control advertiser \(controlCreative.advertiser.name ?? "?")")
    }

    await scenario("B4", "the next stage serves with a stable instance") { notes in
        let driver = newDriver()
        let session = freshSession("b4")
        let first = try await startJourney(driver, session)

        let served = try await decide(
            driver, placements: [demoStage2Placement], sessionId: session, opt: .optIn)
        guard let second = served.creative(for: demoStage2Placement), second.isJourneyAd else {
            throw ClaimFailed(claim: "stage 2 serves on \"\(demoStage2Placement)\"")
        }

        try check(
            second.journeyStageKey == demoStage2Key,
            "the stage advanced to \"\(demoStage2Key)\" (got \(second.journeyStageKey ?? "nil"))")
        try check(
            second.journeyInstanceId == first.journeyInstanceId,
            "the instance id is stable across \(demoStage1Key) → \(demoStage2Key)")
        notes.append("instance \(first.journeyInstanceId ?? "?") held across stages")
    }

    await scenario("B5", "the final stage serves") { notes in
        let driver = newDriver()
        let session = freshSession("b5")
        let first = try await startJourney(driver, session)
        _ = try await decide(
            driver, placements: [demoStage2Placement], sessionId: session, opt: .optIn)
        let served = try await decide(
            driver, placements: [demoStage3Placement], sessionId: session, opt: .optIn)
        guard let last = served.creative(for: demoStage3Placement), last.isJourneyAd else {
            throw ClaimFailed(
                claim: "the final stage serves on \"\(demoStage3Placement)\"")
        }

        try check(
            last.journeyStageKey == demoStage3Key,
            "the stage advanced to \"\(demoStage3Key)\" (got \(last.journeyStageKey ?? "nil"))")
        try check(
            last.journeyInstanceId == first.journeyInstanceId, "still the same instance")
        // Recorded rather than over-asserted: whether the last stage completes depends on the
        // deal's completion configuration, which is the engine's business, not the SDK's.
        notes.append(
            "isCompletion=\(last.isJourneyCompletion) pricing=\(last.journeyPricingModel ?? "nil")")
    }

    await scenario("B6", "three nodes in one stage each serve exactly once") { notes in
        let driver = newDriver()
        let session = freshSession("b6")
        var seen: [String] = []
        var instance: String?
        var stageKey: String?

        for placement in multiNodePlacements {
            let served = try await decide(
                driver, placements: [placement], sessionId: session, opt: .optIn)
            guard let creative = served.creative(for: placement), creative.isJourneyAd else {
                throw SkipScenario(
                    "the seeded multi-node fixture did not serve on \"\(placement)\" — is "
                        + "`e2e_multinode_journey` present in this database?")
            }
            if instance == nil { instance = creative.journeyInstanceId }
            if stageKey == nil { stageKey = creative.journeyStageKey }

            try check(
                creative.journeyInstanceId == instance,
                "every node served under the same instance")
            try check(
                creative.journeyStageKey == stageKey,
                "the stage never regresses or advances (still \(stageKey ?? "nil"))")
            try check(
                !seen.contains(creative.journeyStageNodeId ?? ""),
                "node \(creative.journeyStageNodeId ?? "?") served only once")
            seen.append(creative.journeyStageNodeId ?? "")
        }

        try check(seen.count == 3, "all three nodes served")
        try check(Set(seen).count == 3, "the three node ids are distinct")
        notes.append("stage \(stageKey ?? "?") served nodes \(seen.joined(separator: ", "))")
    }

    await scenario("B7", "journey metadata is coherent and echoes the request") { notes in
        let driver = newDriver()
        let session = freshSession("b7")
        let first = try await startJourney(driver, session)

        // Guards the tolerant-reader mapping. If one field silently decodes to nil, every
        // other scenario stays green — this is the scenario that notices.
        try check(
            first.journeySessionId == session,
            "the engine echoes the session id back (got \(first.journeySessionId ?? "nil"))")
        try check(
            first.journeyOptStatus == .optIn,
            "optStatus echoes the opt-in (got \(String(describing: first.journeyOptStatus)))")
        try check(!(first.journeyStageId ?? "").isEmpty, "stageId is surfaced")
        try check(!(first.journeyStageNodeId ?? "").isEmpty, "stageNodeId is surfaced")
        try check(!(first.journeyDealId ?? "").isEmpty, "dealId is surfaced")
        try check(!(first.journeyPricingModel ?? "").isEmpty, "pricingModel is surfaced")

        let served = try await decide(
            driver, placements: [demoStage2Placement], sessionId: session, opt: .optIn)
        guard let next = served.creative(for: demoStage2Placement), next.isJourneyAd else {
            throw ClaimFailed(claim: "stage 2 serves")
        }
        try check(
            next.journeyDealId == first.journeyDealId,
            "dealId is constant across the journey stages")
        try check(
            next.journeySessionId == session, "the session id is echoed on every serve")
        notes.append("deal \(first.journeyDealId ?? "?") stable; sessionId echoed")
    }
}

// MARK: - §C opt-in / opt-out

func optGroup() async {
    await scenario("C1", "opt-out before any serve → no journey") { notes in
        let driver = newDriver()
        let served = try await decide(
            driver, placements: [demoStage1Placement], sessionId: freshSession("c1"),
            opt: .optOut)
        guard let creative = served.creative(for: demoStage1Placement) else {
            throw ClaimFailed(claim: "a normal ad serves instead")
        }
        try check(
            !creative.isJourneyAd,
            "opt-out suppresses the journey entirely — note that OMITTING journeyOpt would be "
                + "permissive and start one")
        notes.append("opt-out fell back to a normal ad (\(creative.advertiser.name ?? "?"))")
    }

    await scenario("C2/C3", "opt-out closes the instance; a later opt-in mints a NEW instance") {
        notes in
        let driver = newDriver()
        let session = freshSession("c2")
        let first = try await decide(
            driver, placements: [demoStage1Placement], sessionId: session, opt: .optIn)
        guard let started = first.creative(for: demoStage1Placement), started.isJourneyAd else {
            throw ClaimFailed(claim: "a journey started")
        }
        let firstInstance = started.journeyInstanceId

        // Opt-out ENDS the journey rather than pausing it.
        let optedOut = try await decide(
            driver, placements: [demoStage2Placement], sessionId: session, opt: .optOut)
        let optedOutCreative = optedOut.creative(for: demoStage2Placement)
        try check(
            optedOutCreative == nil || optedOutCreative?.isJourneyAd == false,
            "no journey serves while opted out")

        // Opting back in cannot resume the closed instance — it starts a new one.
        let rejoined = try await decide(
            driver, placements: [demoStage1Placement], sessionId: session, opt: .optIn)
        guard let rejoinedCreative = rejoined.creative(for: demoStage1Placement),
            rejoinedCreative.isJourneyAd
        else {
            throw ClaimFailed(claim: "a journey serves again after opting back in")
        }
        try check(
            rejoinedCreative.journeyInstanceId != firstInstance,
            "the new instance id differs from the closed one (\(firstInstance ?? "nil") → "
                + "\(rejoinedCreative.journeyInstanceId ?? "nil"))")
        notes.append(
            "instance \(firstInstance ?? "?") closed; "
                + "\(rejoinedCreative.journeyInstanceId ?? "?") minted")
    }
}
