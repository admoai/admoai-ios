import Foundation

public typealias DecisionResponse = [Decision]

public struct Decision: Decodable {
    public let placement: String
    public let creatives: [Creative]?
}

extension Decision {
    /// `true` when this decision carries at least one creative to render.
    public var hasCreative: Bool { creatives?.isEmpty == false }

    /// `true` for a no-ad response.
    ///
    /// Treats `creatives: []` (single-brand takeover protection) and `creatives: null` /
    /// absent (ordinary no-fill) **uniformly** — the difference is incidental (the reason
    /// lives only in server logs). The SDK deliberately exposes no "protected no-ad" signal
    /// and performs no local ad substitution: a no-ad response yields nothing to render and
    /// nothing to track.
    public var isNoAd: Bool { !hasCreative }
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
    /// The content value. May wrap `NSNull()` when the server sends a null value or omits the
    /// field (tolerant decoding), so read it with a conditional cast (`value.value as? String`)
    /// rather than a force cast (`as!`), which would crash on a null/absent value.
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
    /// Render-level attribution key the engine mints per served creative (`impId,omitempty`);
    /// present for Journey serves, `nil` for normal ads. Read-only passthrough of the engine
    /// contract — the decrypted tracking token remains authoritative server-side.
    public let impId: String?
    // Video-specific metadata (2025-11-01+)
    public let duration: Int?
    public let aspectRatio: String?
    public let isSkippable: Bool?
    /// Seconds before a skippable video may be skipped (`skipOffsetSeconds,omitempty`).
    public let skipOffsetSeconds: Int?
    /// End-card presentation mode for video creatives (`endCardMode,omitempty`).
    public let endCardMode: String?
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
    /// Journey Takeover Ads: completion beacons, populated only for `custom_event`
    /// completion deals (one `{key,url}` entry). Fire once when the mapped action occurs.
    public let completions: [TrackingItem]?

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
        case .completion:
            return completions?.contains { $0.key == key } ?? false
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
        case .completion:
            return getCompletionUrl(key: key)
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

    public func getCompletionUrl(key: String) -> String? {
        completions?.first { $0.key == key }?.url
    }
}

extension Tracking {
    /// Empty tracking block, used as a tolerant fallback when the block is missing/malformed.
    public init() {
        self.init(impressions: nil, clicks: nil, custom: nil, videoEvents: nil, completions: nil)
    }

    private enum CodingKeys: String, CodingKey {
        case impressions, clicks, custom, videoEvents, completions
    }

    /// Tolerant decoder: every category drops malformed entries (via `SafelyDecodable`) so a
    /// single bad `{key,url}` never fails the whole response. Covers the new `completions`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func list(_ key: CodingKeys) -> [TrackingItem]? {
            (try? c.decode([SafelyDecodable<TrackingItem>].self, forKey: key))?.compactMap(\.value)
        }
        self.init(
            impressions: list(.impressions),
            clicks: list(.clicks),
            custom: list(.custom),
            videoEvents: list(.videoEvents),
            completions: list(.completions)
        )
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
    case completion = "completion"
}

public struct VerificationScriptResource: Decodable {
    public let vendorKey: String
    public let scriptUrl: String
    public let verificationParameters: String
}

// ---------------------------------------------------------------------------
// MARK: - Tolerant Reader (whole-response) — PR B
//
// Extends the Tolerant Reader posture from the Journey types (PR A) to the rest of the
// response tree so a future-version or partially-malformed response never throws. Rules:
//   • scalar/object fields use `try? c.decode(T.self, forKey:)` (handles absent, null, AND
//     wrong-type) with safe defaults — currently non-optional fields default to ""/empty
//     rather than widening to Optional, preserving source compatibility (non-breaking).
//   • list fields drop malformed/non-object entries via `SafelyDecodable` instead of failing
//     the whole array.
//   • custom `init(from:)` decoders live in extensions to preserve the synthesized
//     memberwise inits used elsewhere.
// ---------------------------------------------------------------------------

extension Decision {
    private enum TolerantKeys: String, CodingKey { case placement, creatives }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        self.placement = (try? c.decode(String.self, forKey: .placement)) ?? ""
        self.creatives =
            (try? c.decode([SafelyDecodable<Creative>].self, forKey: .creatives))?
            .compactMap(\.value)
    }
}

extension Content {
    private enum TolerantKeys: String, CodingKey { case key, value, type }

    /// Scalar-level tolerance: a retyped `key`/`type` degrades to `""` and a missing/malformed
    /// `value` degrades to a null `AnyCodable`, rather than dropping the whole entry at the
    /// array level. This preserves a usable content field (e.g. its `value`) when a future
    /// engine version only retypes `type`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        self.key = (try? c.decode(String.self, forKey: .key)) ?? ""
        self.type = (try? c.decode(String.self, forKey: .type)) ?? ""
        self.value = (try? c.decode(AnyCodable.self, forKey: .value)) ?? AnyCodable(NSNull())
    }
}

extension Metadata {
    private enum TolerantKeys: String, CodingKey {
        case adId, creativeId, advertiserId, templateId, placementId, priority
        case language, format, style, impId, duration, aspectRatio, isSkippable
        case skipOffsetSeconds, endCardMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        // Currently non-optional id fields default to "" (non-breaking; never throw).
        self.adId = (try? c.decode(String.self, forKey: .adId)) ?? ""
        self.creativeId = (try? c.decode(String.self, forKey: .creativeId)) ?? ""
        self.advertiserId = try? c.decode(String.self, forKey: .advertiserId)
        self.templateId = (try? c.decode(String.self, forKey: .templateId)) ?? ""
        self.placementId = (try? c.decode(String.self, forKey: .placementId)) ?? ""
        self.priority = (try? c.decode(Priority.self, forKey: .priority)) ?? .unknown
        self.language = try? c.decode(String.self, forKey: .language)
        self.format = try? c.decode(String.self, forKey: .format)
        self.style = try? c.decode(String.self, forKey: .style)
        self.impId = try? c.decode(String.self, forKey: .impId)
        // Accept an integer or a JSON number that decodes as Double.
        self.duration =
            (try? c.decode(Int.self, forKey: .duration))
            ?? (try? c.decode(Double.self, forKey: .duration)).map { Int($0) }
        self.aspectRatio = try? c.decode(String.self, forKey: .aspectRatio)
        self.isSkippable = try? c.decode(Bool.self, forKey: .isSkippable)
        self.skipOffsetSeconds =
            (try? c.decode(Int.self, forKey: .skipOffsetSeconds))
            ?? (try? c.decode(Double.self, forKey: .skipOffsetSeconds)).map { Int($0) }
        self.endCardMode = try? c.decode(String.self, forKey: .endCardMode)
    }
}

extension Advertiser {
    private enum TolerantKeys: String, CodingKey { case id, name, legalName, logoUrl }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        self.id = try? c.decode(String.self, forKey: .id)
        self.name = try? c.decode(String.self, forKey: .name)
        self.legalName = try? c.decode(String.self, forKey: .legalName)
        self.logoUrl = try? c.decode(String.self, forKey: .logoUrl)
    }
}

extension Template {
    private enum TolerantKeys: String, CodingKey { case key, style }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        self.key = (try? c.decode(String.self, forKey: .key)) ?? ""
        self.style = try? c.decode(String.self, forKey: .style)
    }
}

extension VastData {
    private enum TolerantKeys: String, CodingKey { case tagUrl, xmlBase64 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        self.tagUrl = try? c.decode(String.self, forKey: .tagUrl)
        self.xmlBase64 = try? c.decode(String.self, forKey: .xmlBase64)
    }
}

extension VerificationScriptResource {
    private enum TolerantKeys: String, CodingKey { case vendorKey, scriptUrl, verificationParameters }

    /// `vendorKey` and `scriptUrl` are **structurally required** — without them an OM resource
    /// is unusable (nothing to identify/load), so they stay strict and a malformed one is
    /// dropped at the array level (`Creative` uses `SafelyDecodable`).
    ///
    /// `verificationParameters` is typed `any` by the engine. A plain string decodes verbatim; an
    /// object or array is re-encoded to compact JSON text rather than discarded. It previously
    /// collapsed any non-string to `""`, which silently dropped the vendor payload — the part IAS
    /// or DoubleVerify actually needs to attribute a measurement — while leaving a resource that
    /// still looked usable. Android already preserved it; this brings iOS in line.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        self.vendorKey = try c.decode(String.self, forKey: .vendorKey)
        self.scriptUrl = try c.decode(String.self, forKey: .scriptUrl)
        if let text = try? c.decode(String.self, forKey: .verificationParameters) {
            self.verificationParameters = text
        } else if let structured = try? c.decode(AnyCodable.self, forKey: .verificationParameters),
            !(structured.value is NSNull),
            let data = try? JSONEncoder().encode(structured),
            let json = String(data: data, encoding: .utf8)
        {
            self.verificationParameters = json
        } else {
            self.verificationParameters = ""
        }
    }
}