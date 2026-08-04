import OSLog

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
            "User-Agent": "AdMoaiSDK/\(SDK_VERSION)"
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
        return AppConfig(
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
        return lhs.name == rhs.name && lhs.version == rhs.version
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

    public init(
        id: String?,
        model: String?,
        manufacturer: String?,
        os: String?,
        osVersion: String?,
        timezone: String?,
        language: String?
    ) {
        self.id = id
        self.model = model
        self.manufacturer = manufacturer
        self.os = os
        self.osVersion = osVersion
        self.timezone = timezone
        self.language = language
    }

    public static func clear() -> DeviceConfig {
        return DeviceConfig(
            id: nil,
            model: nil,
            manufacturer: nil,
            os: nil,
            osVersion: nil,
            timezone: nil,
            language: nil
        )
    }

    public static func systemDefault() -> DeviceConfig {
        let details = getDeviceDetails()

        return DeviceConfig(
            id: details.id,
            model: details.model,
            manufacturer: details.manufacturer,
            os: details.os,
            osVersion: details.osVersion,
            timezone: details.timezone,
            language: details.language
        )
    }

    public static func == (lhs: DeviceConfig, rhs: DeviceConfig) -> Bool {
        return lhs.id == rhs.id && lhs.model == rhs.model && lhs.manufacturer == rhs.manufacturer
            && lhs.os == rhs.os && lhs.osVersion == rhs.osVersion && lhs.timezone == rhs.timezone
            && lhs.language == rhs.language
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
        return UserConfig(
            id: nil,
            ip: nil,
            timezone: nil,
            consent: User.Consent(gdpr: false)
        )
    }

    public static func == (lhs: UserConfig, rhs: UserConfig) -> Bool {
        return lhs.id == rhs.id && lhs.ip == rhs.ip && lhs.timezone == rhs.timezone
            && lhs.consent == rhs.consent
    }
}
