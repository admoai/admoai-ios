import Foundation

public struct DecisionRequest: Encodable {
    public let placements: [Placement]
    public let targeting: Targeting?
    public let user: User?
    public let device: Device?
    public let app: App?

    init(
        placements: [Placement],
        targeting: Targeting? = nil,
        user: User? = nil,
        device: Device? = nil,
        app: App? = nil
    ) {
        self.placements = placements
        self.targeting = targeting
        self.user = user
        self.device = device
        self.app = app
    }
}

public struct Placement: Encodable {
    public let key: String
    public let count: Int
    public let format: Format
    public let advertiserId: String?
    public let templateId: String?

    public init(
        key: String,
        count: Int = 1,
        format: Format = .native,
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
}

public struct Targeting: Encodable {
    public typealias LocationCoordinate = (latitude: Double, longitude: Double)
    public typealias CustomKeyValue = (key: String, value: Any)

    public let geo: [Int]?
    public let location: [LocationCoordinate]?
    public let custom: [CustomKeyValue]?

    public init(
        geo: [Int]? = nil,
        location: [LocationCoordinate]? = nil,
        custom: [CustomKeyValue]? = nil
    ) {
        self.geo = geo
        self.location = location
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
        case geo, location, custom
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
