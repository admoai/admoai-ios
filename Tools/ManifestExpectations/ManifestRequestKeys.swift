import Foundation

// The `request` keys of the shared scenario manifest (@admoai/sdk-scenarios) this runner
// executes, as pure functions shared by the live runner (`journey-e2e`) and `swift test`.
//
// A key the runner does not execute must fail its scenario, never be dropped: the Decodable
// request model ignores keys it has no field for, and a scenario whose request was silently
// trimmed would report green for a request it never sent.

public enum ManifestRequestKeys {
    /// Every top-level key of `request` this runner executes.
    public static let request: Set<String> = [
        "placements", "custom", "session", "journeyOpt", "apiVersion", "distance", "device",
    ]

    /// Every key of `request.device`: the app's manual device configuration.
    public static let device: Set<String> = ["carrier", "category"]

    /// Every value `request.device.category` may take (`DeviceCategory`'s raw values).
    public static let deviceCategories: Set<String> = ["phone", "tablet", "other"]

    /// Keys of `request` this runner does not execute. Non-empty means the scenario is refused.
    public static func unknownRequestKeys(in request: [String: Any]) -> [String] {
        request.keys.filter { !Self.request.contains($0) }.sorted()
    }

    /// Keys of `request.device` this runner does not execute.
    public static func unknownDeviceKeys(in device: [String: Any]) -> [String] {
        device.keys.filter { !Self.device.contains($0) }.sorted()
    }
}

/// `request.custom[].value`: a string, or a list of strings (`publisher_segments`).
public enum ManifestCustomValue: Decodable, Equatable {
    case string(String)
    case strings([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let values = try? container.decode([String].self) {
            self = .strings(values)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "request.custom[].value must be a string or a list of strings"
            )
        }
    }
}
