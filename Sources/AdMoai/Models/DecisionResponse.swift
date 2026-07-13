import Foundation

public typealias DecisionResponse = [Decision]

public struct Decision: Decodable {
    public let placement: String
    public let creatives: [Creative]?
}

public struct Creative: Decodable {
    public let contents: [Content]
    public let metadata: Metadata?
    public let advertiser: Advertiser
    public let template: Template?
    public let tracking: Tracking
    public let verificationScriptResources: [VerificationScriptResource]?
    public let delivery: String? // "vast_tag", "vast_xml", "json" - optional for native ads
    public let vast: VastData?
    /// Journey Takeover Ads: read-only Journey metadata, present only for Journey serves.
    /// `nil` for normal ads (backward compatible).
    public let journey: CreativeJourney?
}

extension Creative {
    private enum CodingKeys: String, CodingKey {
        case contents, metadata, advertiser, template, tracking
        case verificationScriptResources, delivery, vast, journey
    }

    /// Tolerant Reader decoder (Journey scope, PR A): a present-but-malformed `journey`,
    /// `tracking`, or `contents` never throws. `contents` drops malformed entries;
    /// `advertiser`/`tracking` fall back to empty; optional fields degrade to `nil`.
    /// PR B extends total tolerance to the surrounding envelope and sibling types.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.contents =
            ((try? c.decode([SafelyDecodable<Content>].self, forKey: .contents)) ?? [])
            .compactMap(\.value)
        self.metadata = try? c.decode(Metadata.self, forKey: .metadata)
        self.advertiser = (try? c.decode(Advertiser.self, forKey: .advertiser)) ?? Advertiser()
        self.template = try? c.decode(Template.self, forKey: .template)
        self.tracking = (try? c.decode(Tracking.self, forKey: .tracking)) ?? Tracking()
        self.verificationScriptResources =
            (try? c.decode([SafelyDecodable<VerificationScriptResource>].self,
                           forKey: .verificationScriptResources))?
            .compactMap(\.value)
        self.delivery = try? c.decode(String.self, forKey: .delivery)
        self.vast = try? c.decode(VastData.self, forKey: .vast)
        self.journey = try? c.decode(CreativeJourney.self, forKey: .journey)
    }
}

/// Tolerant array-element wrapper: a malformed or non-object element decodes to `nil`
/// (dropped via `compactMap`) instead of failing the entire array decode. Swift fails a
/// whole `[T]` decode if any single element throws — this isolates that failure per-element.
struct SafelyDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// Read-only Journey Takeover Ads metadata (engine-owned). All fields are optional and
/// decoded tolerantly (unknown/absent/mistyped → `nil`); the SDK never infers or mutates them.
public struct CreativeJourney {
    public let dealId: String?
    public let instanceId: String?
    public let definitionKey: String?
    public let stageId: String?
    public let stageKey: String?
    public let stageNodeId: String?
    public let sessionId: String?
    /// Opt state; unknown wire values decode to `nil` (open-set).
    public let optStatus: JourneyOpt?
    public let isCompletion: Bool?
    /// Open-set string (e.g. cpm/cpc/cpv/cpcv/fixed/cpt/standard) — kept as `String?` so a
    /// future engine pricing model never breaks decoding.
    public let pricingModel: String?
    /// Open-set string (e.g. bill_per_stage/no_charge).
    public let fallbackBillingMode: String?
}

extension CreativeJourney: Decodable {
    private enum CodingKeys: String, CodingKey {
        case dealId, instanceId, definitionKey, stageId, stageKey, stageNodeId
        case sessionId, optStatus, isCompletion, pricingModel, fallbackBillingMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.dealId = try? c.decode(String.self, forKey: .dealId)
        self.instanceId = try? c.decode(String.self, forKey: .instanceId)
        self.definitionKey = try? c.decode(String.self, forKey: .definitionKey)
        self.stageId = try? c.decode(String.self, forKey: .stageId)
        self.stageKey = try? c.decode(String.self, forKey: .stageKey)
        self.stageNodeId = try? c.decode(String.self, forKey: .stageNodeId)
        self.sessionId = try? c.decode(String.self, forKey: .sessionId)
        self.optStatus = try? c.decode(JourneyOpt.self, forKey: .optStatus)
        self.isCompletion = try? c.decode(Bool.self, forKey: .isCompletion)
        self.pricingModel = try? c.decode(String.self, forKey: .pricingModel)
        self.fallbackBillingMode = try? c.decode(String.self, forKey: .fallbackBillingMode)
    }
}

public struct Content: Decodable {
    public let key: String
    public let value: AnyCodable
    public let type: String
}

extension Array where Element == Content {
    public func getContent(key: String) -> Content? {
        first { $0.key == key }
    }

    public func hasContents() -> Bool {
        !isEmpty
    }

    public func isType(key: String, type: String) -> Bool {
        contains { $0.key == key && $0.type == type }
    }
}

/// Strongly-typed ad priority.
///
/// Use `.rawValue` to get the underlying string if needed.
public enum Priority: String, Decodable {
    case house = "house"
    case sponsorship = "sponsorship"
    case standard = "standard"
    case unknown = "unknown"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Priority(rawValue: raw) ?? .unknown
    }
}

public struct Metadata: Decodable {
    public let adId: String
    public let creativeId: String
    public let advertiserId: String?
    public let templateId: String
    public let placementId: String
    public let priority: Priority
    public let language: String?
    public let format: String?
    public let style: String?
    // Video-specific metadata (2025-11-01+)
    public let duration: Int?
    public let aspectRatio: String?
    public let isSkippable: Bool?
}

public struct Advertiser: Decodable {
    public let id: String?
    public let name: String?
    public let legalName: String?
    public let logoUrl: String?
}

extension Advertiser {
    /// Empty advertiser, used as a tolerant fallback when the block is missing/malformed.
    public init() {
        self.init(id: nil, name: nil, legalName: nil, logoUrl: nil)
    }
}

public struct Template: Decodable {
    public let key: String
    public let style: String?
}

public struct VastData: Decodable {
    public let tagUrl: String? // For vast_tag delivery
    public let xmlBase64: String? // For vast_xml delivery
}

public struct Tracking: Decodable {
    public let impressions: [TrackingItem]?
    public let clicks: [TrackingItem]?
    public let custom: [TrackingItem]?
    public let videoEvents: [TrackingItem]? // For JSON delivery video tracking

    public func hasTrackingFor(type: TrackingType, key: String) -> Bool {
        switch type {
        case .impression:
            return impressions?.contains { $0.key == key } ?? false
        case .click:
            return clicks?.contains { $0.key == key } ?? false
        case .custom:
            return custom?.contains { $0.key == key } ?? false
        case .videoEvent:
            return videoEvents?.contains { $0.key == key } ?? false
        }
    }

    public func getTrackingUrl(type: TrackingType, key: String) -> String? {
        switch type {
        case .impression:
            return getImpressionUrl(key: key)
        case .click:
            return getClickUrl(key: key)
        case .custom:
            return getCustomUrl(key: key)
        case .videoEvent:
            return getVideoEventUrl(key: key)
        }
    }

    public func getImpressionUrl(key: String) -> String? {
        impressions?.first { $0.key == key }?.url
    }

    public func getClickUrl(key: String) -> String? {
        clicks?.first { $0.key == key }?.url
    }

    public func getCustomUrl(key: String) -> String? {
        custom?.first { $0.key == key }?.url
    }
    
    public func getVideoEventUrl(key: String) -> String? {
        videoEvents?.first { $0.key == key }?.url
    }
}

extension Tracking {
    /// Empty tracking block, used as a tolerant fallback when the block is missing/malformed.
    public init() {
        self.init(impressions: nil, clicks: nil, custom: nil, videoEvents: nil)
    }
}

public struct TrackingItem: Decodable {
    public let key: String
    public let url: String
}

public enum TrackingType: String {
    case impression = "impression"
    case click = "click"
    case custom = "custom"
    case videoEvent = "videoEvent"
}

public struct VerificationScriptResource: Decodable {
    public let vendorKey: String
    public let scriptUrl: String
    public let verificationParameters: String
}