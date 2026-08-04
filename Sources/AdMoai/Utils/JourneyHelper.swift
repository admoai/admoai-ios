import Foundation

/// `true` when `value` is a non-`nil`, non-blank string. File-private so the SDK does not add
/// a `String` extension to every consumer's namespace.
private func isPresent(_ value: String?) -> Bool {
    guard let value = value else { return false }
    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// Read-only convenience accessors for Journey Takeover Ads metadata on a `Creative`.
///
/// Mirrors the `VideoHelper`/`OMHelper` pattern: keeps `Creative` lean while surfacing
/// Journey fields ergonomically. Everything here is read-only — the SDK never infers,
/// persists, or mutates Journey state (that is owned entirely by the decision-engine).
extension Creative {
    /// `true` when this creative is part of a Journey.
    ///
    /// Checks for a **real identifier** rather than mere presence of the `journey` block:
    /// tolerant decoding turns `"journey": {}` — or a block with every field retyped — into a
    /// non-`nil` `CreativeJourney` whose fields are all `nil`. Keying off `journey != nil`
    /// would report a normal ad as a Journey serve while all thirteen accessors returned
    /// `nil`. Matches the Android reference (`JourneyHelper.kt`).
    public var isJourneyAd: Bool {
        isPresent(journey?.dealId) || isPresent(journey?.instanceId)
    }

    public var journeyDealId: String? { journey?.dealId }
    public var journeyInstanceId: String? { journey?.instanceId }
    public var journeyDefinitionKey: String? { journey?.definitionKey }
    public var journeyStageId: String? { journey?.stageId }
    public var journeyStageKey: String? { journey?.stageKey }
    public var journeyStageNodeId: String? { journey?.stageNodeId }
    public var journeySessionId: String? { journey?.sessionId }
    public var journeyOptStatus: JourneyOpt? { journey?.optStatus }
    public var journeyPricingModel: String? { journey?.pricingModel }
    public var journeyFallbackBillingMode: String? { journey?.fallbackBillingMode }

    /// `true` only when the engine marked this serve as the Journey completion
    /// (`final_stage` strategy). Completion is recorded server-side at decision time;
    /// there is no extra URL to fire in this mode.
    public var isJourneyCompletion: Bool { journey?.isCompletion == true }

    /// `true` when the creative carries a completion beacon to fire (i.e. a `custom_event`
    /// completion deal). Mutually exclusive with `isJourneyCompletion` (`final_stage`).
    public var hasCompletionUrl: Bool { tracking.completions?.isEmpty == false }
}
