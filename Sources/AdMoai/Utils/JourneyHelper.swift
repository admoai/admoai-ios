import Foundation

/// Read-only convenience accessors for Journey Takeover Ads metadata on a `Creative`.
///
/// Mirrors the `VideoHelper`/`OMHelper` pattern: keeps `Creative` lean while surfacing
/// Journey fields ergonomically. Everything here is read-only — the SDK never infers,
/// persists, or mutates Journey state (that is owned entirely by the decision-engine).
extension Creative {
    /// `true` when this creative is part of a Journey (i.e. `creative.journey` is present).
    public var isJourneyAd: Bool { journey != nil }

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
}
