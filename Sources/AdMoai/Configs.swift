import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
#if canImport(OSLog)
    import OSLog
#endif

public struct SDKConfig {
    public let baseUrl: String
    /// API version for the Decision Engine (e.g., "2025-11-01"). Enables format filter for Video Ads.
    public let apiVersion: String?
    /// Default language for ad requests (e.g., "en", "es"). Sets Accept-Language header.
    public let defaultLanguage: String?
    public let logger: Logger
    public let sessionConfiguration: URLSessionConfiguration

    /// Initializes the SDKConfig with a base URL, optional API version, logger, and session configuration.
    /// - Parameters:
    ///   - baseUrl: The Decision Engine API endpoint
    ///   - apiVersion: Optional API version (e.g., "2025-11-01" for format filter support)
    ///   - defaultLanguage: Optional default language for requests (e.g., "en", "es")
    ///   - logger: Logger instance for SDK logging
    ///   - sessionConfiguration: URL session configuration
    public init(
        baseUrl: String,
        apiVersion: String? = nil,
        defaultLanguage: String? = nil,
        logger: Logger = Logger(subsystem: "com.admoai.sdk", category: "AdMoaiSDK"),
        sessionConfiguration: URLSessionConfiguration = defaultSessionConfiguration()
    ) {
        self.baseUrl = baseUrl
        self.apiVersion = apiVersion
        self.defaultLanguage = defaultLanguage
        self.logger = logger
        self.sessionConfiguration = sessionConfiguration
        logger.debug("AdMoai SDK config initialized")
    }

    /// Provides the default session configuration with SDK-specific customizations.
    ///
    /// The 10s request timeout matches the Android and Flutter SDKs, which both default to 10s
    /// across request/connect/read. This was 30s (with a 60s resource timeout), so the same slow
    /// endpoint or cold engine succeeded on iOS and timed out on the other two — a multi-stage
    /// journey then looked flaky on two platforms only. An ad request that takes longer than 10s
    /// has no value anyway: the surface it was requested for is long gone.
    ///
    /// The User-Agent here is a convenience for callers who reuse this configuration; the SDK no
    /// longer depends on it, and sets the header per-request so a custom `URLSessionConfiguration`
    /// cannot silently strip it.
    public static func defaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        configuration.httpAdditionalHeaders = [
            "User-Agent": "AdMoaiSDK/\(SDK_VERSION)",
        ]
        return configuration
    }
}

public protocol Clearable {
    static func clear() -> Self
}

public struct AppConfig: Clearable, Equatable {
    public let name: String?
    public let version: String?
    public let buildNumber: String?
    public let identifier: String?
    public let language: String?

    public init(
        name: String?,
        version: String?,
        buildNumber: String?,
        identifier: String?,
        language: String?
    ) {
        self.name = name
        self.version = version
        self.buildNumber = buildNumber
        self.identifier = identifier
        self.language = language
    }

    public static func clear() -> AppConfig {
        AppConfig(
            name: nil,
            version: nil,
            buildNumber: nil,
            identifier: nil,
            language: nil
        )
    }

    public static func systemDefault() -> AppConfig {
        let details = getAppDetails()

        return AppConfig(
            name: details.name,
            version: details.version,
            buildNumber: details.buildNumber,
            identifier: details.identifier,
            language: details.language
        )
    }

    public static func == (lhs: AppConfig, rhs: AppConfig) -> Bool {
        lhs.name == rhs.name && lhs.version == rhs.version
            && lhs.buildNumber == rhs.buildNumber && lhs.identifier == rhs.identifier
            && lhs.language == rhs.language
    }
}

public struct DeviceConfig: Clearable, Equatable {
    public let id: String?
    public let model: String?
    public let manufacturer: String?
    public let os: String?
    public let osVersion: String?
    public let timezone: String?
    public let language: String?
    /// Carrier name, normalized: trimmed, and `nil` for blanks and placeholders (`--`, `unknown`, `wifi`).
    public let carrier: String?
    /// What the publisher stated about the category, if anything.
    enum CategoryOverride: Equatable {
        /// Nothing stated: the collected value is sent when the app enabled collection.
        case none
        /// The publisher's value wins over the collected one.
        case value(DeviceCategory)
        /// The publisher removed it: absent, with no fallback to the collected value
        /// (cross-SDK ruling 2026-11-13), until `resetDeviceConfig()`.
        case absent
    }

    let categoryOverride: CategoryOverride

    /// Reads the category from the platform; `nil` means automatic collection is off, which is the
    /// default: collection is opt-in through `AdMoai.enableDeviceCategoryCollection()`, because a
    /// workspace whose audience-signals contract is off refuses `device.category` (cross-SDK
    /// ruling 2026-11-13).
    let categoryProvider: (@Sendable () -> DeviceCategory?)?

    /// The category this configuration sends: the publisher's value when set (absent when the
    /// publisher removed it), otherwise the one collected from the platform (absent when
    /// collection is off, the default, or when the platform cannot classify the device).
    public var category: DeviceCategory? {
        switch categoryOverride {
        case let .value(category): category
        case .absent: nil
        case .none: categoryProvider?()
        }
    }

    public init(
        id: String?,
        model: String?,
        manufacturer: String?,
        os: String?,
        osVersion: String?,
        timezone: String?,
        language: String?
    ) {
        self.init(
            id: id, model: model, manufacturer: manufacturer, os: os, osVersion: osVersion,
            timezone: timezone, language: language, carrier: nil, category: nil
        )
    }

    /// The same configuration with the audience-signals fields; `carrier` is normalized
    /// (trimmed; blanks and placeholders become `nil`).
    public init(
        id: String?,
        model: String?,
        manufacturer: String?,
        os: String?,
        osVersion: String?,
        timezone: String?,
        language: String?,
        carrier: String?,
        category: DeviceCategory?
    ) {
        self.init(
            id: id, model: model, manufacturer: manufacturer, os: os, osVersion: osVersion,
            timezone: timezone, language: language, carrier: carrier,
            categoryOverride: category.map(CategoryOverride.value) ?? .none, categoryProvider: nil
        )
    }

    init(
        id: String?,
        model: String?,
        manufacturer: String?,
        os: String?,
        osVersion: String?,
        timezone: String?,
        language: String?,
        carrier: String?,
        categoryOverride: CategoryOverride,
        categoryProvider: (@Sendable () -> DeviceCategory?)?
    ) {
        self.id = id
        self.model = model
        self.manufacturer = manufacturer
        self.os = os
        self.osVersion = osVersion
        self.timezone = timezone
        self.language = language
        self.carrier = normalizeCarrier(carrier)
        self.categoryOverride = categoryOverride
        self.categoryProvider = categoryProvider
    }

    /// The same configuration with a different category source; everything else is preserved.
    func with(categoryProvider: (@Sendable () -> DeviceCategory?)?) -> DeviceConfig {
        DeviceConfig(
            id: id, model: model, manufacturer: manufacturer, os: os, osVersion: osVersion,
            timezone: timezone, language: language, carrier: carrier,
            categoryOverride: categoryOverride, categoryProvider: categoryProvider
        )
    }

    /// The same configuration with a different carrier and category override; the collection
    /// state (`categoryProvider`) is preserved.
    func with(carrier: String?, categoryOverride: CategoryOverride) -> DeviceConfig {
        DeviceConfig(
            id: id, model: model, manufacturer: manufacturer, os: os, osVersion: osVersion,
            timezone: timezone, language: language, carrier: carrier,
            categoryOverride: categoryOverride, categoryProvider: categoryProvider
        )
    }

    public static func clear() -> DeviceConfig {
        DeviceConfig(
            id: nil,
            model: nil,
            manufacturer: nil,
            os: nil,
            osVersion: nil,
            timezone: nil,
            language: nil,
            carrier: nil,
            category: nil
        )
    }

    /// The system device configuration. It collects no category: automatic collection is opt-in
    /// (`AdMoai.enableDeviceCategoryCollection()`).
    public static func systemDefault() -> DeviceConfig {
        systemDefault(categoryProvider: nil)
    }

    /// The system configuration with a category source: `currentDeviceCategory` once the app
    /// enabled collection, or an injected one in tests.
    static func systemDefault(categoryProvider: (@Sendable () -> DeviceCategory?)?) -> DeviceConfig {
        let details = getDeviceDetails()

        return DeviceConfig(
            id: details.id,
            model: details.model,
            manufacturer: details.manufacturer,
            os: details.os,
            osVersion: details.osVersion,
            timezone: details.timezone,
            language: details.language,
            // iOS never collects the carrier automatically; manual setDeviceCarrier(_:) remains.
            carrier: nil,
            categoryOverride: .none,
            categoryProvider: categoryProvider
        )
    }

    public static func == (lhs: DeviceConfig, rhs: DeviceConfig) -> Bool {
        lhs.id == rhs.id && lhs.model == rhs.model && lhs.manufacturer == rhs.manufacturer
            && lhs.os == rhs.os && lhs.osVersion == rhs.osVersion && lhs.timezone == rhs.timezone
            && lhs.language == rhs.language && lhs.carrier == rhs.carrier
            && lhs.categoryOverride == rhs.categoryOverride
            && (lhs.categoryProvider == nil) == (rhs.categoryProvider == nil)
    }
}

public struct UserConfig: Clearable, Equatable {
    public let id: String?
    public let ip: String?
    public let timezone: String?
    public let consent: User.Consent

    public init(
        id: String?,
        ip: String?,
        timezone: String?,
        consent: User.Consent = User.Consent()
    ) {
        self.id = id
        self.ip = ip
        self.timezone = timezone
        self.consent = consent
    }

    public static func clear() -> UserConfig {
        UserConfig(
            id: nil,
            ip: nil,
            timezone: nil,
            consent: User.Consent(gdpr: false)
        )
    }

    public static func == (lhs: UserConfig, rhs: UserConfig) -> Bool {
        lhs.id == rhs.id && lhs.ip == rhs.ip && lhs.timezone == rhs.timezone
            && lhs.consent == rhs.consent
    }
}
