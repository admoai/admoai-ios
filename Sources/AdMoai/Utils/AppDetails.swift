import Foundation

public func getAppDetails() -> AppDetails {
    let bundle = Bundle.main
    return AppDetails(
        name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Unknown",
        version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
        buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
        identifier: bundle.bundleIdentifier ?? "Unknown",
        language: Bundle.main.preferredLocalizations.first
    )
}

public struct AppDetails {
    public let name: String
    public let version: String
    public let buildNumber: String
    public let identifier: String
    public let language: String?
}
