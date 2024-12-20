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
    public let template: Template
    public let tracking: Tracking
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

public struct Metadata: Decodable {
    public let adId: String
    public let creativeId: String
    public let advertiserId: String
    public let templateId: String
    public let placementId: String
    public let priority: String
    public let language: String
}

public struct Advertiser: Decodable {
    public let name: String
    public let legalName: String
    public let logoUrl: String
}

public struct Template: Decodable {
    public let key: String
    public let style: String
}

public struct Tracking: Decodable {
    public let impressions: [TrackingItem]
    public let clicks: [TrackingItem]?
    public let custom: [TrackingItem]?

    public func hasTrackingFor(type: TrackingType, key: String) -> Bool {
        switch type {
        case .impression:
            return impressions.contains { $0.key == key }
        case .click:
            return clicks?.contains { $0.key == key } ?? false
        case .custom:
            return custom?.contains { $0.key == key } ?? false
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
        }
    }

    public func getImpressionUrl(key: String) -> String? {
        impressions.first { $0.key == key }?.url
    }

    public func getClickUrl(key: String) -> String? {
        clicks?.first { $0.key == key }?.url
    }

    public func getCustomUrl(key: String) -> String? {
        custom?.first { $0.key == key }?.url
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
}
