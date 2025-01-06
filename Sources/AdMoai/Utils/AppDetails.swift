import Foundation

public func getAppDetails() -> AppDetails {
    let bundle = Bundle.main
    return AppDetails(
        name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
        version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
        buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String,
        identifier: bundle.bundleIdentifier,
        language: Bundle.main.preferredLocalizations.first
    )
}

public struct AppDetails {
    public let name: String?
    public let version: String?
    public let buildNumber: String?
    public let identifier: String?
    public let language: String?
}
