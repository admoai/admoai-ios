import Foundation

public struct DecisionRequest: Encodable {
    public let placements: [Placement]
    public let targeting: Targeting?
    public let user: User?
    public let device: Device?
    public let app: App?
    /// Journey Takeover Ads: opaque, publisher-owned session identifier forwarded verbatim
    /// to the engine (top-level). Trimmed and omitted when blank at encode time.
    public let sessionId: String?
    /// Journey Takeover Ads: publisher opt-in/opt-out for the current session.
    public let journeyOpt: JourneyOpt?

    init(
        placements: [Placement],
        targeting: Targeting? = nil,
        user: User? = nil,
        device: Device? = nil,
        app: App? = nil,
        sessionId: String? = nil,
        journeyOpt: JourneyOpt? = nil
    ) {
        self.placements = placements
        self.targeting = targeting
        self.user = user
        self.device = device
        self.app = app
        self.sessionId = sessionId
        self.journeyOpt = journeyOpt
    }

    private enum CodingKeys: String, CodingKey {
        case placements, targeting, user, device, app, sessionId, journeyOpt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(placements, forKey: .placements)
        try container.encodeIfPresent(targeting, forKey: .targeting)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encodeIfPresent(device, forKey: .device)
        try container.encodeIfPresent(app, forKey: .app)

        // Journey `sessionId`: engine trims and silently disables Journey when blank.
        // Mirror that here — send the trimmed value, omit entirely when blank.
        // Over-length values are sent as-is (the engine silently disables Journey,
        // the request still succeeds as a normal ad).
        if let sessionId = sessionId {
            let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try container.encode(trimmed, forKey: .sessionId)
            }
        }
        // `journeyOpt` is strict on the engine ("in"/"out" or HTTP 400); the typed enum
        // guarantees only valid literals are ever emitted, and only when set.
        if let journeyOpt = journeyOpt {
            try container.encode(journeyOpt.rawValue, forKey: .journeyOpt)
        }
    }

    /// Returns a PII-safe reason token when `sessionId` would be rejected by the engine's
    /// Journey gate — `"blank_after_trim"` (empty after trimming) or `"exceeds_256_bytes"`
    /// (over the 256 UTF-8 **byte** limit) — otherwise `nil`.
    ///
    /// The returned token intentionally matches the sibling Flutter SDK for cross-SDK
    /// diagnostic parity and deliberately differs from the engine's internal constant name.
    /// It never contains the `sessionId` value itself (which is PII).
    public static func journeySessionIdRejectionReason(_ sessionId: String?) -> String? {
        guard let sessionId = sessionId else { return nil }
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "blank_after_trim" }
        if trimmed.utf8.count > 256 { return "exceeds_256_bytes" }
        return nil
    }

    /// Normalizes a `sessionId` to its wire form: trimmed, with a blank value collapsing to
    /// `nil`. Used so a stored/forwarded `sessionId` matches exactly what is sent, avoiding a
    /// field-vs-wire mismatch.
    public static func normalizedSessionId(_ sessionId: String?) -> String? {
        guard let sessionId = sessionId else { return nil }
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct Placement: Encodable {
    public let key: String
    public let count: Int?
    public let format: Format?
    public let advertiserId: String?
    public let templateId: String?

    public init(
        key: String,
        count: Int? = nil,
        format: Format? = nil,
        advertiserId: String? = nil,
        templateId: String? = nil
    ) {
        self.key = key
        self.count = count
        self.format = format
        self.advertiserId = advertiserId
        self.templateId = templateId
    }
}

public enum Format: String, Encodable {
    case native = "native"
    case video = "video"
}

/// Journey Takeover Ads opt state.
///
/// The wire literals are `"in"` / `"out"` (`in`/`out` are Swift keywords, hence the
/// `optIn`/`optOut` case names). Conforms to `Codable` so a response `optStatus` can be
/// read with `try? container.decode(JourneyOpt.self, forKey:)` — an unknown raw value
/// decodes to `nil` (open-set / Tolerant Reader), while the request side stays strict
/// (only `optIn`/`optOut` can ever be encoded).
public enum JourneyOpt: String, Codable {
    case optIn = "in"
    case optOut = "out"

    /// Tolerant parse from a raw wire string for non-`Decoder` contexts: unknown or `nil`
    /// input maps to `nil` rather than throwing.
    public static func fromWire(_ raw: String?) -> JourneyOpt? {
        guard let raw = raw else { return nil }
        return JourneyOpt(rawValue: raw)
    }
}

public struct Targeting: Encodable {
    public typealias LocationCoordinate = (latitude: Double, longitude: Double)
    public typealias DestinationCoordinate = (latitude: Double, longitude: Double, minConfidence: Double)
    public typealias CustomKeyValue = (key: String, value: Any)

    public let geo: [Int]?
    public let location: [LocationCoordinate]?
    public let destination: [DestinationCoordinate]?
    public let custom: [CustomKeyValue]?

    public init(
        geo: [Int]? = nil,
        location: [LocationCoordinate]? = nil,
        destination: [DestinationCoordinate]? = nil,
        custom: [CustomKeyValue]? = nil
    ) {
        self.geo = geo
        self.location = location
        self.destination = destination
        self.custom = custom
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(geo, forKey: .geo)

        if let locations = location {
            try container.encode(
                locations.map { coord in
                    ["latitude": coord.latitude, "longitude": coord.longitude]
                }, forKey: .location)
        }

        if let destinations = destination {
            // `minConfidence` is the engine's canonical key, matching every other field on the
            // request contract. `min_confidence` survives only as a back-compat alias kept so
            // already-fielded SDKs keep parsing, and camelCase wins when both are present.
            try container.encode(
                destinations.map { coord in
                    ["latitude": coord.latitude, "longitude": coord.longitude, "minConfidence": coord.minConfidence]
                }, forKey: .destination)
        }

        if let customs = custom {
            let encodableCustoms = customs.map { kv in
                [
                    "key": AnyCodable(kv.key),
                    "value": AnyCodable(kv.value),
                ]
            }
            try container.encode(encodableCustoms, forKey: .custom)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case geo, location, destination, custom
    }
}

public struct User: Encodable {
    public let id: String?
    public let ip: String?
    public let timezone: String?
    public let consent: Consent?

    public init(
        id: String? = nil,
        ip: String? = nil,
        timezone: String? = nil,
        consent: Consent? = nil
    ) {
        self.id = id
        self.ip = ip
        self.timezone = timezone
        self.consent = consent
    }

    public struct Consent: Encodable, Equatable {
        public let gdpr: Bool

        public init(gdpr: Bool = false) {
            self.gdpr = gdpr
        }

        public static func == (lhs: Consent, rhs: Consent) -> Bool {
            lhs.gdpr == rhs.gdpr
        }
    }
}

public struct Device: Encodable {
    public let id: String?
    public let model: String?
    public let manufacturer: String?
    public let os: String?
    public let osVersion: String?
    public let timezone: String?
    public let language: String?

    public init(
        id: String? = nil,
        model: String? = nil,
        manufacturer: String? = nil,
        os: String? = nil,
        osVersion: String? = nil,
        timezone: String? = nil,
        language: String? = nil
    ) {
        self.id = id
        self.model = model
        self.manufacturer = manufacturer
        self.os = os
        self.osVersion = osVersion
        self.timezone = timezone
        self.language = language
    }
}

public struct App: Encodable {
    public let name: String?
    public let version: String?
    public let buildNumber: String?
    public let identifier: String?
    public let language: String?

    public init(
        name: String? = nil,
        version: String? = nil,
        buildNumber: String? = nil,
        identifier: String? = nil,
        language: String? = nil
    ) {
        self.name = name
        self.version = version
        self.buildNumber = buildNumber
        self.identifier = identifier
        self.language = language
    }
}
